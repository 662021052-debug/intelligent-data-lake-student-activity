"""Gold Layer (Medallion Architecture) — analytics-ready Star Schema.

The dashboard (Phase 11+) must never query the operational tables directly.
Instead we expose a set of ``gold_*`` SQL views shaped as a Star Schema:

    fact  : gold_fact_participation        (grain = one APPROVED participation)
            gold_fact_item_hours           (grain = APPROVED participation × criteria item)
    dims  : gold_dim_student
            gold_dim_activity
            gold_dim_hour_category
            gold_dim_subcategory
            gold_dim_date
    ready : gold_student_hours             (per student × criteria item + pass/fail)
            gold_activity_item             (activity → criteria items it counts toward)
            gold_activity_catalog          (public activity list + registration count)

Only participations with ``evidence_status = 'approved'`` are counted — the same
rule the operational hours-summary uses (see ``students._build_hours_summary``).

Criteria items (เฟส 6 ของการรื้อ DB)
------------------------------------
"ครบเกณฑ์" ถูกวัดเทียบกับ **ชุดเกณฑ์ของนิสิตแต่ละคน** (``student.criteria_set_id``) ไม่ใช่
หมวดชั่วโมงชุดเดียวของทั้งระบบ แต่ละชุดแตกเป็น *รายการที่ตรวจความครบ* (criteria item):

* ``min_per_requirement`` (เช่น 2567-regular): หนึ่งรายการต่อ requirement ที่ไม่อยู่ในกลุ่ม
  + หนึ่งรายการต่อ requirement_group (ตรวจที่ยอดรวมของสมาชิก — กฎ Social รวม ≥ 16)
* ``total_per_unit`` (ชุด legacy): หนึ่งรายการต่อหน่วยการเรียนรู้ = ยอดรวมของ requirement
  ในหน่วยนั้น (แบบเดียวกับหมวดชั่วโมงเดิม)
* นิสิตที่ยังไม่ผูกชุดเกณฑ์: ใช้หมวดชั่วโมงเดิม (hourcategory) เหมือนก่อนมีชุดเกณฑ์

นิสิตครบเกณฑ์ = ทุกรายการครบ (บังคับครบทุกตัว ∧ เลือกครบทุกรายการ ∧ กลุ่มครบยอดรวม)
item_key เป็นเลขเต็ม: requirement.id ของรายการเดี่ยว / requirement.id ที่น้อยที่สุดของสมาชิก
กลุ่มหรือหน่วย / hourcategory.id ของนิสิตที่ไม่มีชุดเกณฑ์ — ไม่ชนกันภายในนิสิตคนเดียว

กิจกรรมนับเข้ารายการผ่าน activity_requirement (ผูกหลายรายการได้ นับเต็มชั่วโมงให้ทุกรายการ
แต่นับครั้งเดียวต่อรายการ) ส่วนกิจกรรมโครงเดิมที่มีแต่ subcategory_id นับเข้า requirement
ที่ชื่อตรงกับหมวดย่อยในชุดเกณฑ์ของนิสิต (ชุด legacy แปลงชื่อมาจากหมวดย่อยตรง ๆ)

Design notes
------------
* We use plain SQL **views**, not a separate Postgres schema, so the exact same
  DDL runs on SQLite (dev / tests) and Postgres (docker). The ``gold_`` prefix
  is what separates the analytical layer from the operational tables.
* Views are (re)created on every startup and can be rebuilt on demand via
  ``POST /gold/refresh`` — this stands in for the Bronze→Silver→Gold ETL refresh
  step (a plain view has no stored data to refresh, so recreation is enough).
* Every view reads **base tables only** — shared pieces are composed as SQL
  subqueries in Python, never as a view reading another view. Migrations drop
  ``GOLD_VIEW_NAMES`` in any order without CASCADE, which Postgres only allows
  when no view depends on another.
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
    "gold_fact_item_hours",
    "gold_dim_student",
    "gold_dim_activity",
    "gold_dim_hour_category",
    "gold_dim_subcategory",
    "gold_dim_date",
    "gold_student_hours",
    "gold_activity_item",
    "gold_activity_catalog",
]

# ---- ชิ้นส่วน SQL ที่หลาย view ใช้ร่วม (ฝังเป็น subquery — view อ่านตารางจริงเท่านั้น) ----

# requirement → รายการที่ตรวจความครบ (item) ภายในชุดเกณฑ์ของมัน
_REQUIREMENT_ITEM = """
    SELECT
        r.id              AS requirement_key,
        r.criteria_set_id AS criteria_set_key,
        CASE
            WHEN cs.counting_rule = 'total_per_unit' THEN (
                SELECT MIN(r2.id) FROM requirement r2
                WHERE r2.criteria_set_id = r.criteria_set_id
                  AND r2.learning_unit_id = r.learning_unit_id)
            WHEN r.group_id IS NOT NULL THEN (
                SELECT MIN(r2.id) FROM requirement r2 WHERE r2.group_id = r.group_id)
            ELSE r.id
        END AS item_key
    FROM requirement r
    JOIN criteria_set cs ON cs.id = r.criteria_set_id
"""

# นิยามของแต่ละรายการในแต่ละชุดเกณฑ์ — ชื่อ ชนิด เป้าชั่วโมง บังคับไหม อยู่หน่วย/Talent ไหน
_CRITERIA_ITEM = """
    SELECT
        r.criteria_set_id AS criteria_set_key,
        r.id              AS item_key,
        r.name            AS item_name,
        'requirement'     AS item_kind,
        CASE WHEN r.is_mandatory THEN 1 ELSE 0 END AS is_mandatory,
        r.required_hours  AS required_hours,
        lu.id             AS learning_unit_key,
        lu.name           AS learning_unit_name,
        t.id              AS talent_key,
        t.name            AS talent_name,
        t.sort_order      AS talent_order
    FROM requirement r
    JOIN criteria_set cs  ON cs.id = r.criteria_set_id
    JOIN learning_unit lu ON lu.id = r.learning_unit_id
    LEFT JOIN talent t    ON t.id = r.talent_id
    WHERE cs.counting_rule <> 'total_per_unit' AND r.group_id IS NULL

    UNION ALL

    SELECT
        g.criteria_set_id, m.item_key, g.name, 'group', m.is_mandatory, g.required_hours,
        lu.id, lu.name, t.id, t.name, t.sort_order
    FROM requirement_group g
    JOIN criteria_set cs ON cs.id = g.criteria_set_id
    JOIN (
        SELECT
            r.group_id,
            MIN(r.id) AS item_key,
            MAX(CASE WHEN r.is_mandatory THEN 1 ELSE 0 END) AS is_mandatory,
            -- สมาชิกอยู่หน่วย/Talent เดียวกัน = ของกลุ่ม · ต่างกัน = ไม่ระบุ (ไม่เดาให้)
            CASE WHEN MIN(r.learning_unit_id) = MAX(r.learning_unit_id)
                 THEN MIN(r.learning_unit_id) END AS learning_unit_key,
            CASE WHEN MIN(r.talent_id) = MAX(r.talent_id)
                 THEN MIN(r.talent_id) END AS talent_key
        FROM requirement r
        WHERE r.group_id IS NOT NULL
        GROUP BY r.group_id
    ) m ON m.group_id = g.id
    LEFT JOIN learning_unit lu ON lu.id = m.learning_unit_key
    LEFT JOIN talent t         ON t.id = m.talent_key
    WHERE cs.counting_rule <> 'total_per_unit'

    UNION ALL

    SELECT
        r.criteria_set_id, MIN(r.id), lu.name, 'unit',
        MAX(CASE WHEN r.is_mandatory THEN 1 ELSE 0 END), SUM(r.required_hours),
        lu.id, lu.name, NULL, NULL, NULL
    FROM requirement r
    JOIN criteria_set cs  ON cs.id = r.criteria_set_id
    JOIN learning_unit lu ON lu.id = r.learning_unit_id
    WHERE cs.counting_rule = 'total_per_unit'
    GROUP BY r.criteria_set_id, lu.id, lu.name
"""

# กิจกรรม → requirement ที่นับให้: ผูกผ่าน activity_requirement หรือ (กิจกรรมโครงเดิมที่ยัง
# ไม่ได้ผูกเลย) requirement ที่ชื่อตรงกับหมวดย่อยของมัน
_ACTIVITY_LINK = """
    SELECT ar.activity_id AS activity_key, ar.requirement_id AS requirement_key
    FROM activity_requirement ar
    UNION
    SELECT a.id, r.id
    FROM activity a
    JOIN hoursubcategory sub ON sub.id = a.subcategory_id
    JOIN requirement r       ON r.name = sub.name
    WHERE NOT EXISTS (SELECT 1 FROM activity_requirement ar2 WHERE ar2.activity_id = a.id)
"""


def _fact_item_sql(date_key: str) -> str:
    """การเข้าร่วมที่อนุมัติแล้ว × รายการที่นับให้ — ของนิสิตแต่ละคนตามชุดเกณฑ์ของตัวเอง

    DISTINCT: กิจกรรมที่ผูกหลาย requirement ซึ่งตกรายการเดียวกัน (สมาชิกกลุ่ม/หน่วยเดียวกัน)
    ต้องนับชั่วโมงเข้ารายการนั้นครั้งเดียว
    """
    return f"""
        SELECT DISTINCT
            p.id              AS participation_id,
            p.student_id      AS student_key,
            s.criteria_set_id AS criteria_set_key,
            ri.item_key       AS item_key,
            p.hours_earned    AS hours_earned,
            {date_key}        AS date_key
        FROM participation p
        JOIN student s  ON s.id = p.student_id
        JOIN activity a ON a.id = p.activity_id
        JOIN ({_ACTIVITY_LINK}) l ON l.activity_key = a.id
        JOIN ({_REQUIREMENT_ITEM}) ri
             ON ri.requirement_key = l.requirement_key
            AND ri.criteria_set_key = s.criteria_set_id
        WHERE p.evidence_status = 'approved'

        UNION ALL

        SELECT
            p.id, p.student_id, NULL, sub.category_id, p.hours_earned, {date_key}
        FROM participation p
        JOIN student s           ON s.id = p.student_id
        JOIN activity a          ON a.id = p.activity_id
        JOIN hoursubcategory sub ON sub.id = a.subcategory_id
        WHERE p.evidence_status = 'approved' AND s.criteria_set_id IS NULL
    """


# นิสิต × รายการที่ต้องทำให้ครบ (ยังไม่มีชั่วโมง) — มีแถวเสมอแม้ยังไม่ได้ชั่วโมงเลย
_STUDENT_ITEM = f"""
    SELECT
        s.id AS student_key, s.student_id AS student_code, s.full_name AS full_name,
        s.faculty AS faculty, s.year_level AS year_level,
        cs.id AS criteria_set_key, cs.code AS criteria_set_code,
        ci.item_key, ci.item_name, ci.item_kind, ci.is_mandatory, ci.required_hours,
        ci.learning_unit_key, ci.learning_unit_name, ci.talent_key, ci.talent_name, ci.talent_order
    FROM student s
    JOIN criteria_set cs ON cs.id = s.criteria_set_id
    JOIN ({_CRITERIA_ITEM}) ci ON ci.criteria_set_key = cs.id

    UNION ALL

    SELECT
        s.id, s.student_id, s.full_name, s.faculty, s.year_level,
        NULL, NULL,
        c.id, c.name, 'category', 0, c.required_hours,
        NULL, c.name, NULL, NULL, NULL
    FROM student s
    CROSS JOIN hourcategory c
    WHERE s.criteria_set_id IS NULL
"""


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
            s.status      AS status,
            -- อีเมลรายคน (NULL = ยังไม่ระบุ) — การแจ้งเตือนกลุ่มเสี่ยงอ่านจากที่นี่
            -- พร้อมกับชั่วโมง จะได้ไม่ต้องวิ่งถามตาราง student อีกรอบ
            s.email       AS email
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
            a.is_hidden        AS is_hidden,
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

    fact_item_sql = _fact_item_sql(d["date_key"])

    # Per student × criteria item: APPROVED hours vs the item's target, with pass/fail.
    # Every item the student must finish has a row even with 0 hours earned.
    # ``category_key``/``category_name`` keep their old names (readers — reports,
    # e-mail, chatbot — predate criteria sets); they now mean "the criteria item".
    student_hours = f"""
        SELECT
            si.student_key, si.student_code, si.full_name, si.faculty, si.year_level,
            si.item_key                   AS category_key,
            si.item_name                  AS category_name,
            si.required_hours             AS required_hours,
            COALESCE(e.earned_hours, 0)   AS earned_hours,
            CASE WHEN COALESCE(e.earned_hours, 0) >= si.required_hours
                 THEN 1 ELSE 0 END        AS completed,
            si.criteria_set_key, si.criteria_set_code, si.item_kind, si.is_mandatory,
            si.learning_unit_key, si.learning_unit_name,
            si.talent_key, si.talent_name, si.talent_order
        FROM ({_STUDENT_ITEM}) si
        LEFT JOIN (
            SELECT f.student_key, f.item_key, SUM(f.hours_earned) AS earned_hours
            FROM ({fact_item_sql}) f
            GROUP BY f.student_key, f.item_key
        ) e ON e.student_key = si.student_key AND e.item_key = si.item_key
    """

    # Which criteria items an activity counts toward, per criteria set — the chatbot
    # uses it to recommend activities for the items a student is still missing.
    activity_item = f"""
        SELECT DISTINCT l.activity_key, ri.criteria_set_key, ri.item_key
        FROM ({_ACTIVITY_LINK}) l
        JOIN ({_REQUIREMENT_ITEM}) ri ON ri.requirement_key = l.requirement_key
    """

    # Public activity catalog for the student chatbot: every activity plus its
    # category/subcategory names, whether it is required, and how many students
    # have registered (all statuses) so "open for registration" = approved AND
    # participant_count < max_participants. Activities are public, so this view
    # carries no per-student data and needs no student filter.
    #
    # กิจกรรมที่ถูกซ่อน (is_hidden) ถูกตัดออกตรงนี้ เพราะ view นี้มีผู้อ่านคนเดียวคือ
    # แชตบอตของนิสิต — แนะนำกิจกรรมที่สมัครไม่ได้แล้วก็ได้แต่ทำให้เข้าใจผิด
    # (ชั่วโมงที่นับไปแล้วอยู่ใน gold_student_hours/gold_fact_participation ไม่กระทบ)
    activity_catalog = f"""
        SELECT
            a.id               AS activity_key,
            a.name             AS name,
            a.activity_type    AS activity_type,
            a.is_required      AS is_required,
            a.hours            AS hours,
            a.max_participants AS max_participants,
            a.approval_status  AS approval_status,
            a.start_at         AS start_at,
            {d['date_key']}    AS date_key,
            sub.id             AS subcategory_key,
            sub.name           AS subcategory_name,
            c.id               AS category_key,
            -- กิจกรรมชุดเกณฑ์ใหม่ไม่มีหมวดเดิม → แสดงชื่อรายการเกณฑ์ที่ผูกไว้แทน
            COALESCE(c.name, r.name) AS category_name,
            r.id               AS requirement_key,
            r.name             AS requirement_name,
            (SELECT COUNT(*) FROM participation p WHERE p.activity_id = a.id)
                               AS participant_count
        FROM activity a
        LEFT JOIN hoursubcategory sub ON sub.id = a.subcategory_id
        LEFT JOIN hourcategory c ON c.id = sub.category_id
        -- ผูกหลายรายการได้ — catalog เป็นหนึ่งแถวต่อกิจกรรม จึงแสดงรายการแรกเป็นตัวแทน
        LEFT JOIN (
            SELECT ar.activity_id, MIN(ar.requirement_id) AS requirement_id
            FROM activity_requirement ar
            GROUP BY ar.activity_id
        ) link ON link.activity_id = a.id
        LEFT JOIN requirement r ON r.id = link.requirement_id
        WHERE NOT a.is_hidden
    """

    return [
        ("gold_fact_participation", fact),
        ("gold_fact_item_hours", fact_item_sql),
        ("gold_dim_student", dim_student),
        ("gold_dim_activity", dim_activity),
        ("gold_dim_hour_category", dim_hour_category),
        ("gold_dim_subcategory", dim_subcategory),
        ("gold_dim_date", dim_date),
        ("gold_student_hours", student_hours),
        ("gold_activity_item", activity_item),
        ("gold_activity_catalog", activity_catalog),
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
