"""Gold Layer (Medallion Architecture) — analytics-ready Star Schema.

The dashboard (Phase 11+) must never query the operational tables directly.
Instead we expose a set of ``gold_*`` SQL views shaped as a Star Schema:

    fact  : gold_fact_participation        (grain = one APPROVED participation)
    dims  : gold_dim_student
            gold_dim_activity
            gold_dim_hour_category
            gold_dim_subcategory
            gold_dim_date
    ready : gold_student_hours             (per student × category rollup + pass/fail)

Only participations with ``evidence_status = 'approved'`` are counted — the same
rule the operational hours-summary uses (see ``students._build_hours_summary``).

Design notes
------------
* We use plain SQL **views**, not a separate Postgres schema, so the exact same
  DDL runs on SQLite (dev / tests) and Postgres (docker). The ``gold_`` prefix
  is what separates the analytical layer from the operational tables.
* Views are (re)created on every startup and can be rebuilt on demand via
  ``POST /gold/refresh`` — this stands in for the Bronze→Silver→Gold ETL refresh
  step (a plain view has no stored data to refresh, so recreation is enough).
* Date functions differ between SQLite and Postgres, so the small set of
  date expressions is dialect-aware; everything else is shared SQL.
"""

from __future__ import annotations

from sqlalchemy import text
from sqlmodel import Session

# Order does not matter for creation (every view reads base tables only), but we
# keep a canonical list so callers can report / drop them deterministically.
GOLD_VIEW_NAMES = [
    "gold_fact_participation",
    "gold_dim_student",
    "gold_dim_activity",
    "gold_dim_hour_category",
    "gold_dim_subcategory",
    "gold_dim_date",
    "gold_student_hours",
]


def _date_exprs(dialect: str, col: str) -> dict[str, str]:
    """Dialect-specific SQL expressions for pulling parts out of ``col`` (a datetime)."""
    if dialect == "postgresql":
        return {
            "date_key": f"CAST(to_char({col}, 'YYYYMMDD') AS INTEGER)",
            "full_date": f"CAST({col} AS DATE)",
            "year": f"CAST(EXTRACT(YEAR FROM {col}) AS INTEGER)",
            "month": f"CAST(EXTRACT(MONTH FROM {col}) AS INTEGER)",
        }
    # sqlite (dev / tests) — datetimes are stored as ISO-8601 text
    return {
        "date_key": f"CAST(strftime('%Y%m%d', {col}) AS INTEGER)",
        "full_date": f"date({col})",
        "year": f"CAST(strftime('%Y', {col}) AS INTEGER)",
        "month": f"CAST(strftime('%m', {col}) AS INTEGER)",
    }


def _view_definitions(dialect: str) -> list[tuple[str, str]]:
    """Return ``(view_name, select_sql)`` pairs for the whole gold layer."""
    d = _date_exprs(dialect, "a.start_at")

    # Thai academic calendar: semester 1 = Jun–Oct, semester 2 = Nov–Mar,
    # semester 3 (summer) = Apr–May. Academic year is Buddhist (พ.ศ.); months
    # Jan–May belong to the academic year that started the previous June.
    semester_case = (
        f"CASE WHEN {d['month']} BETWEEN 6 AND 10 THEN 1 "
        f"WHEN {d['month']} IN (11, 12, 1, 2, 3) THEN 2 "
        f"ELSE 3 END"
    )
    academic_year_case = (
        f"CASE WHEN {d['month']} >= 6 THEN {d['year']} + 543 "
        f"ELSE {d['year']} + 542 END"
    )

    fact = f"""
        SELECT
            p.id                AS participation_id,
            p.student_id        AS student_key,
            p.activity_id       AS activity_key,
            a.subcategory_id    AS subcategory_key,
            {d['date_key']}     AS date_key,
            p.hours_earned      AS hours_earned,
            p.evidence_status   AS evidence_status
        FROM participation p
        JOIN activity a ON a.id = p.activity_id
        WHERE p.evidence_status = 'approved'
    """

    dim_student = """
        SELECT
            s.id          AS student_key,
            s.student_id  AS student_code,
            s.full_name   AS full_name,
            s.faculty     AS faculty,
            s.major       AS major,
            s.year_level  AS year_level,
            s.status      AS status
        FROM student s
    """

    dim_activity = f"""
        SELECT
            a.id               AS activity_key,
            a.name             AS name,
            a.activity_type    AS activity_type,
            a.subcategory_id   AS subcategory_key,
            a.hours            AS hours,
            a.max_participants AS max_participants,
            a.approval_status  AS approval_status,
            a.created_by       AS created_by,
            {d['date_key']}    AS date_key
        FROM activity a
    """

    dim_hour_category = """
        SELECT
            c.id             AS category_key,
            c.name           AS name,
            c.required_hours AS required_hours
        FROM hourcategory c
    """

    dim_subcategory = """
        SELECT
            sub.id             AS subcategory_key,
            sub.category_id    AS category_key,
            sub.name           AS name,
            sub.required_hours AS required_hours
        FROM hoursubcategory sub
    """

    dim_date = f"""
        SELECT DISTINCT
            {d['date_key']}      AS date_key,
            {d['full_date']}     AS full_date,
            {d['year']}          AS year,
            {d['month']}         AS month,
            {semester_case}      AS semester,
            {academic_year_case} AS academic_year
        FROM activity a
        WHERE a.start_at IS NOT NULL
    """

    # Per student × hour-category rollup of APPROVED hours, with pass/fail against
    # the category requirement. A CROSS JOIN guarantees a row for every category
    # even when the student has earned nothing in it (0 / required).
    student_hours = """
        SELECT
            s.id                        AS student_key,
            s.student_id                AS student_code,
            s.full_name                 AS full_name,
            s.faculty                   AS faculty,
            s.year_level                AS year_level,
            c.id                        AS category_key,
            c.name                      AS category_name,
            c.required_hours            AS required_hours,
            COALESCE(agg.earned_hours, 0) AS earned_hours,
            CASE WHEN COALESCE(agg.earned_hours, 0) >= c.required_hours
                 THEN 1 ELSE 0 END      AS completed
        FROM student s
        CROSS JOIN hourcategory c
        LEFT JOIN (
            SELECT
                p.student_id     AS student_id,
                sub.category_id  AS category_id,
                SUM(p.hours_earned) AS earned_hours
            FROM participation p
            JOIN activity a       ON a.id = p.activity_id
            JOIN hoursubcategory sub ON sub.id = a.subcategory_id
            WHERE p.evidence_status = 'approved'
            GROUP BY p.student_id, sub.category_id
        ) agg ON agg.student_id = s.id AND agg.category_id = c.id
    """

    return [
        ("gold_fact_participation", fact),
        ("gold_dim_student", dim_student),
        ("gold_dim_activity", dim_activity),
        ("gold_dim_hour_category", dim_hour_category),
        ("gold_dim_subcategory", dim_subcategory),
        ("gold_dim_date", dim_date),
        ("gold_student_hours", student_hours),
    ]


def create_gold_layer(session: Session) -> None:
    """(Re)create every gold view on the session's database.

    Idempotent: each view is dropped first, so this doubles as the refresh step.
    """
    dialect = session.get_bind().dialect.name
    for name, select_sql in _view_definitions(dialect):
        session.execute(text(f"DROP VIEW IF EXISTS {name}"))
        session.execute(text(f"CREATE VIEW {name} AS {select_sql}"))
    session.commit()


def init_gold_layer(engine) -> None:
    """Startup helper: open a short-lived session and (re)build the gold layer."""
    with Session(engine) as session:
        create_gold_layer(session)
