"""Phase 11 — Executive Dashboard API (reads the Gold Layer only).

Every endpoint is admin-only and reads exclusively from the ``gold_*`` views
(never the operational tables). All endpoints accept the optional drill-down
filters ``faculty``, ``year_level`` and ``semester``.

"Passing" is defined as a student's total APPROVED hours reaching the overall
requirement, which is the sum of every hour-category's ``required_hours``
(60 hours under the current TSU structure).
"""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlmodel import Session

from app.auth import require_admin
from app.database import get_session

router = APIRouter(
    prefix="/dashboard",
    tags=["dashboard"],
    dependencies=[Depends(require_admin)],  # admin only -> non-admin gets 403
)


# --------------------------- response models ---------------------------
class OverviewStats(BaseModel):
    total_students: int
    passed_count: int
    passed_percent: float
    avg_hours: float
    activity_count: int
    required_hours_total: float


class CategoryStat(BaseModel):
    category_key: Optional[int]  # None = "ไม่ระบุหมวด" bucket
    category_name: str
    required_hours: float
    avg_earned_hours: float


class AtRiskStudent(BaseModel):
    student_key: int
    student_code: str
    full_name: str
    faculty: str
    year_level: int
    earned_hours: float
    required_hours: float
    percent: float
    missing_hours: float


class LowParticipationActivity(BaseModel):
    activity_key: int
    name: str
    activity_type: str
    max_participants: int
    participant_count: int
    fill_percent: float


class FacultyStat(BaseModel):
    faculty: str
    year_level: int
    total_students: int
    passed_count: int
    passed_percent: float


class TrendPoint(BaseModel):
    period: str
    year: int
    month: int
    count: int


# --------------------------- helpers ---------------------------
def _required_total(session: Session) -> float:
    value = session.execute(
        text("SELECT COALESCE(SUM(required_hours), 0) FROM gold_dim_hour_category")
    ).scalar()
    return float(value or 0)


def _student_where(faculty: Optional[str], year_level: Optional[int]) -> tuple[str, dict]:
    """WHERE fragment for gold_dim_student (alias-free; the view is queried directly)."""
    clauses, params = [], {}
    if faculty:
        clauses.append("faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("year_level = :year_level")
        params["year_level"] = year_level
    where = (" WHERE " + " AND ".join(clauses)) if clauses else ""
    return where, params


def _earned_by_student(session: Session, semester: Optional[int]) -> dict[int, float]:
    """student_key -> total approved hours, optionally restricted to one semester."""
    sql = "SELECT f.student_key, SUM(f.hours_earned) FROM gold_fact_participation f"
    params: dict = {}
    if semester is not None:
        sql += " JOIN gold_dim_date d ON d.date_key = f.date_key WHERE d.semester = :semester"
        params["semester"] = semester
    sql += " GROUP BY f.student_key"
    return {row[0]: float(row[1] or 0) for row in session.execute(text(sql), params).all()}


def _filtered_students(session: Session, faculty, year_level) -> list:
    where, params = _student_where(faculty, year_level)
    return session.execute(
        text(
            "SELECT student_key, student_code, full_name, faculty, year_level "
            f"FROM gold_dim_student{where}"
        ),
        params,
    ).all()


# --------------------------- endpoints ---------------------------
@router.get("/overview", response_model=OverviewStats)
def overview(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    session: Session = Depends(get_session),
):
    required_total = _required_total(session)
    students = _filtered_students(session, faculty, year_level)
    earned = _earned_by_student(session, semester)

    totals = [earned.get(s[0], 0.0) for s in students]
    total_students = len(students)
    passed = sum(1 for t in totals if t >= required_total and required_total > 0)
    avg_hours = (sum(totals) / total_students) if total_students else 0.0
    passed_percent = (passed / total_students * 100) if total_students else 0.0

    act_sql = "SELECT COUNT(*) FROM gold_dim_activity a"
    act_params: dict = {}
    if semester is not None:
        act_sql += (
            " JOIN gold_dim_date d ON d.date_key = a.date_key"
            " WHERE a.approval_status = 'approved' AND d.semester = :semester"
        )
        act_params["semester"] = semester
    else:
        act_sql += " WHERE a.approval_status = 'approved'"
    activity_count = int(session.execute(text(act_sql), act_params).scalar() or 0)

    return OverviewStats(
        total_students=total_students,
        passed_count=passed,
        passed_percent=round(passed_percent, 2),
        avg_hours=round(avg_hours, 2),
        activity_count=activity_count,
        required_hours_total=required_total,
    )


@router.get("/by-category", response_model=list[CategoryStat])
def by_category(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    session: Session = Depends(get_session),
):
    students = _filtered_students(session, faculty, year_level)
    total_students = len(students)

    # Sum approved hours per category across the filtered student set.
    clauses = ["1 = 1"]
    params: dict = {}
    if faculty:
        clauses.append("s.faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("s.year_level = :year_level")
        params["year_level"] = year_level
    if semester is not None:
        clauses.append("d.semester = :semester")
        params["semester"] = semester

    # LEFT JOIN so approved hours on activities with no (or an orphaned)
    # subcategory are not silently dropped: they fall into a NULL category_key
    # bucket surfaced as "ไม่ระบุหมวด". This keeps the sum of per-category
    # averages equal to /overview's avg_hours (every approved hour is counted once).
    rows = session.execute(
        text(
            "SELECT sub.category_key, SUM(f.hours_earned) "
            "FROM gold_fact_participation f "
            "LEFT JOIN gold_dim_subcategory sub ON sub.subcategory_key = f.subcategory_key "
            "JOIN gold_dim_student s ON s.student_key = f.student_key "
            "JOIN gold_dim_date d ON d.date_key = f.date_key "
            f"WHERE {' AND '.join(clauses)} "
            "GROUP BY sub.category_key"
        ),
        params,
    ).all()
    earned_by_category = {row[0]: float(row[1] or 0) for row in rows}

    categories = session.execute(
        text("SELECT category_key, name, required_hours FROM gold_dim_hour_category ORDER BY category_key")
    ).all()

    def _avg(total_earned: float) -> float:
        return round((total_earned / total_students) if total_students else 0.0, 2)

    result = []
    for cat_key, name, required in categories:
        result.append(
            CategoryStat(
                category_key=cat_key,
                category_name=name,
                required_hours=float(required),
                avg_earned_hours=_avg(earned_by_category.get(cat_key, 0.0)),
            )
        )

    # Bucket for approved hours not tied to any category (subcategory_id NULL /
    # orphaned) — shown only when such hours exist.
    uncategorized = earned_by_category.get(None, 0.0)
    if uncategorized > 0:
        result.append(
            CategoryStat(
                category_key=None,
                category_name="ไม่ระบุหมวด",
                required_hours=0.0,
                avg_earned_hours=_avg(uncategorized),
            )
        )
    return result


@router.get("/at-risk", response_model=list[AtRiskStudent])
def at_risk(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    threshold: float = Query(50, ge=0, le=100, description="เปอร์เซ็นต์เกณฑ์กลุ่มเสี่ยง (ต่ำกว่านี้ = เสี่ยง)"),
    session: Session = Depends(get_session),
):
    required_total = _required_total(session)
    students = _filtered_students(session, faculty, year_level)
    earned = _earned_by_student(session, semester)

    result = []
    for student_key, code, full_name, fac, yr in students:
        earned_hours = earned.get(student_key, 0.0)
        percent = (earned_hours / required_total * 100) if required_total > 0 else 0.0
        if percent < threshold:
            result.append(
                AtRiskStudent(
                    student_key=student_key,
                    student_code=code,
                    full_name=full_name,
                    faculty=fac,
                    year_level=yr,
                    earned_hours=earned_hours,
                    required_hours=required_total,
                    percent=round(percent, 2),
                    missing_hours=round(max(required_total - earned_hours, 0.0), 2),
                )
            )
    # most at risk first
    result.sort(key=lambda s: s.earned_hours)
    return result


@router.get("/low-participation", response_model=list[LowParticipationActivity])
def low_participation(
    semester: Optional[int] = None,
    limit: int = Query(10, ge=1, le=100),
    session: Session = Depends(get_session),
):
    sql = (
        "SELECT a.activity_key, a.name, a.activity_type, a.max_participants, "
        "COUNT(f.participation_id) AS participants "
        "FROM gold_dim_activity a "
        "LEFT JOIN gold_fact_participation f ON f.activity_key = a.activity_key "
    )
    params: dict = {}
    where = ["a.approval_status = 'approved'"]
    if semester is not None:
        sql += "JOIN gold_dim_date d ON d.date_key = a.date_key "
        where.append("d.semester = :semester")
        params["semester"] = semester
    sql += (
        f"WHERE {' AND '.join(where)} "
        "GROUP BY a.activity_key, a.name, a.activity_type, a.max_participants "
        # NULLIF guards against a legacy 0-capacity row: Postgres raises on
        # divide-by-zero (SQLite returns NULL), so NULLIF -> NULL keeps it safe.
        "ORDER BY (CAST(COUNT(f.participation_id) AS FLOAT) / NULLIF(a.max_participants, 0)) ASC, participants ASC "
        "LIMIT :limit"
    )
    params["limit"] = limit

    rows = session.execute(text(sql), params).all()
    result = []
    for act_key, name, act_type, max_p, participants in rows:
        fill = (participants / max_p * 100) if max_p else 0.0
        result.append(
            LowParticipationActivity(
                activity_key=act_key,
                name=name,
                activity_type=act_type,
                max_participants=max_p,
                participant_count=participants,
                fill_percent=round(fill, 2),
            )
        )
    return result


@router.get("/by-faculty", response_model=list[FacultyStat])
def by_faculty(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    session: Session = Depends(get_session),
):
    required_total = _required_total(session)
    students = _filtered_students(session, faculty, year_level)
    earned = _earned_by_student(session, semester)

    # group by (faculty, year_level)
    groups: dict[tuple[str, int], dict] = {}
    for student_key, _code, _name, fac, yr in students:
        key = (fac, yr)
        g = groups.setdefault(key, {"total": 0, "passed": 0})
        g["total"] += 1
        if required_total > 0 and earned.get(student_key, 0.0) >= required_total:
            g["passed"] += 1

    result = []
    for (fac, yr), g in groups.items():
        percent = (g["passed"] / g["total"] * 100) if g["total"] else 0.0
        result.append(
            FacultyStat(
                faculty=fac,
                year_level=yr,
                total_students=g["total"],
                passed_count=g["passed"],
                passed_percent=round(percent, 2),
            )
        )
    result.sort(key=lambda s: (s.faculty, s.year_level))
    return result


@router.get("/trend", response_model=list[TrendPoint])
def trend(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    session: Session = Depends(get_session),
):
    clauses = ["1 = 1"]
    params: dict = {}
    if faculty:
        clauses.append("s.faculty = :faculty")
        params["faculty"] = faculty
    if year_level is not None:
        clauses.append("s.year_level = :year_level")
        params["year_level"] = year_level
    if semester is not None:
        clauses.append("d.semester = :semester")
        params["semester"] = semester

    rows = session.execute(
        text(
            "SELECT d.year, d.month, COUNT(*) "
            "FROM gold_fact_participation f "
            "JOIN gold_dim_date d ON d.date_key = f.date_key "
            "JOIN gold_dim_student s ON s.student_key = f.student_key "
            f"WHERE {' AND '.join(clauses)} "
            "GROUP BY d.year, d.month "
            "ORDER BY d.year, d.month"
        ),
        params,
    ).all()

    return [
        TrendPoint(period=f"{int(year)}-{int(month):02d}", year=int(year), month=int(month), count=count)
        for year, month, count in rows
    ]
