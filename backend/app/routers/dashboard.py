"""Phase 11 — Executive Dashboard API (reads the Gold Layer only).

Every endpoint is admin-only and reads exclusively from the ``gold_*`` views
(never the operational tables). All endpoints accept the optional drill-down
filters ``faculty``, ``year_level`` and ``semester``.

"Passing" = every criteria item of the student's own criteria set is complete
(``gold_student_hours``, rules in :mod:`app.completion`) — not "total hours ≥ 60":
60 hours earned in a single item used to count as passing. Progress/at-risk use
the hours that count toward the criteria (capped per item), so 100% == passed.
With a ``semester`` filter every figure is recomputed from that semester's hours
only (``gold_fact_item_hours``).
"""

from typing import Optional

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy import text
from sqlmodel import Session

from app.auth import require_admin
from app.completion import StudentProgress, progress_by_student
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


def _student_items(
    session: Session, faculty: Optional[str], year_level: Optional[int], semester: Optional[int]
) -> list[tuple]:
    """(student_key, item_key, item_name, required, earned, unit_key, unit_name) ของทุกรายการ

    ไม่กรองภาคเรียน = ชั่วโมงจาก gold_student_hours ตรง ๆ · กรองภาคเรียน = คำนวณชั่วโมงของ
    แต่ละรายการใหม่จากการเข้าร่วมในภาคนั้นเท่านั้น
    """
    where, params = _student_where(faculty, year_level)
    rows = session.execute(
        text(
            "SELECT student_key, category_key, category_name, required_hours, earned_hours, "
            "learning_unit_key, learning_unit_name "
            f"FROM gold_student_hours{where} ORDER BY student_key, category_key"
        ),
        params,
    ).all()
    if semester is None:
        return [tuple(r) for r in rows]

    earned = {
        (student_key, item_key): float(hours or 0)
        for student_key, item_key, hours in session.execute(
            text(
                "SELECT f.student_key, f.item_key, SUM(f.hours_earned) "
                "FROM gold_fact_item_hours f "
                "JOIN gold_dim_date d ON d.date_key = f.date_key "
                "WHERE d.semester = :semester GROUP BY f.student_key, f.item_key"
            ),
            {"semester": semester},
        ).all()
    }
    return [
        (sk, ik, name, required, earned.get((sk, ik), 0.0), unit_key, unit_name)
        for sk, ik, name, required, _all_time, unit_key, unit_name in rows
    ]


def _progress(items: list[tuple]) -> dict[int, StudentProgress]:
    return progress_by_student(
        (sk, ik, name, required, earned) for sk, ik, name, required, earned, _uk, _un in items
    )


# --------------------------- endpoints ---------------------------
@router.get("/overview", response_model=OverviewStats)
def overview(
    faculty: Optional[str] = None,
    year_level: Optional[int] = None,
    semester: Optional[int] = None,
    session: Session = Depends(get_session),
):
    students = _filtered_students(session, faculty, year_level)
    earned = _earned_by_student(session, semester)
    progress = _progress(_student_items(session, faculty, year_level, semester))

    totals = [earned.get(s[0], 0.0) for s in students]
    total_students = len(students)
    passed = sum(1 for s in students if s[0] in progress and progress[s[0]].completed)
    avg_hours = (sum(totals) / total_students) if total_students else 0.0
    passed_percent = (passed / total_students * 100) if total_students else 0.0
    # เกณฑ์ต่างกันได้ตามชุดเกณฑ์ของแต่ละคน — การ์ดบนหน้าจอโชว์ค่าเฉลี่ยของคนที่มีเกณฑ์
    # (ทุกคนอยู่ชุดเดียวกันก็คือเกณฑ์ของชุดนั้นตรง ๆ) ไม่มีใครเลยค่อยใช้หมวดชั่วโมงเดิม
    requirements = [p.required_hours for p in progress.values() if p.required_hours > 0]
    required_total = (
        round(sum(requirements) / len(requirements), 2) if requirements else _required_total(session)
    )

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
    """ชั่วโมงเฉลี่ยต่อคนเทียบเป้าเฉลี่ยต่อคน แยกตามหน่วยการเรียนรู้

    หน่วยการเรียนรู้ 5 หน่วยเป็น taxonomy ที่ทุกชุดเกณฑ์ใช้ร่วมกัน กราฟจึงเทียบกันได้แม้นิสิต
    อยู่คนละชุด (นิสิตที่ยังไม่มีชุดเกณฑ์ใช้หมวดชั่วโมงเดิม ซึ่งชื่อตรงกับหน่วยอยู่แล้ว
    — แท่งชื่อเดียวกันจึงรวมเป็นแท่งเดียว)
    """
    students = _filtered_students(session, faculty, year_level)
    total_students = len(students)
    items = _student_items(session, faculty, year_level, semester)

    buckets: dict[str, dict] = {}
    for _sk, item_key, _name, required, earned, unit_key, unit_name in items:
        name = unit_name or "ไม่ระบุหน่วย"
        key = unit_key if unit_key is not None else item_key
        bucket = buckets.setdefault(name, {"key": key, "required": 0.0, "earned": 0.0})
        bucket["key"] = min(bucket["key"], key)
        bucket["required"] += float(required or 0)
        bucket["earned"] += float(earned or 0)

    def _avg(total: float) -> float:
        return round((total / total_students) if total_students else 0.0, 2)

    result = [
        CategoryStat(
            category_key=b["key"],
            category_name=name,
            required_hours=_avg(b["required"]),
            avg_earned_hours=_avg(b["earned"]),
        )
        for name, b in sorted(buckets.items(), key=lambda kv: kv[1]["key"])
    ]

    # ชั่วโมงที่อนุมัติแล้วแต่ไม่นับเข้ารายการใดของเกณฑ์นิสิตคนนั้น (เช่น กิจกรรมที่ยังไม่ได้
    # ผูกรายการเกณฑ์) — แยกเป็นแท่งของตัวเองให้เห็น แทนที่จะหายไปเงียบ ๆ
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
    unmapped = session.execute(
        text(
            "SELECT COALESCE(SUM(f.hours_earned), 0) "
            "FROM gold_fact_participation f "
            "JOIN gold_dim_student s ON s.student_key = f.student_key "
            "JOIN gold_dim_date d ON d.date_key = f.date_key "
            f"WHERE {' AND '.join(clauses)} AND NOT EXISTS ("
            "SELECT 1 FROM gold_fact_item_hours fi WHERE fi.participation_id = f.participation_id)"
        ),
        params,
    ).scalar()
    if float(unmapped or 0) > 0:
        result.append(
            CategoryStat(
                category_key=None,
                category_name="ไม่ระบุหมวด",
                required_hours=0.0,
                avg_earned_hours=_avg(float(unmapped)),
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
    students = _filtered_students(session, faculty, year_level)
    progress = _progress(_student_items(session, faculty, year_level, semester))

    result = []
    for student_key, code, full_name, fac, yr in students:
        p = progress.get(student_key)
        # ไม่มีเกณฑ์ให้วัด (ยังไม่ผูกชุดเกณฑ์และไม่มีหมวดเดิม) = ตัดสินไม่ได้ว่าเสี่ยง
        if p is None or p.required_hours <= 0:
            continue
        if p.percent < threshold:
            result.append(
                AtRiskStudent(
                    student_key=student_key,
                    student_code=code,
                    full_name=full_name,
                    faculty=fac,
                    year_level=yr,
                    # ชั่วโมงที่นับเข้าเกณฑ์ (ตัดส่วนเกินรายรายการ) ให้ตรงกับ percent/missing
                    earned_hours=round(p.counted_hours, 2),
                    required_hours=p.required_hours,
                    percent=round(p.percent, 2),
                    missing_hours=round(p.missing_hours, 2),
                )
            )
    # most at risk first
    result.sort(key=lambda s: (s.percent, s.earned_hours))
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
    students = _filtered_students(session, faculty, year_level)
    progress = _progress(_student_items(session, faculty, year_level, semester))

    # group by (faculty, year_level)
    groups: dict[tuple[str, int], dict] = {}
    for student_key, _code, _name, fac, yr in students:
        key = (fac, yr)
        g = groups.setdefault(key, {"total": 0, "passed": 0})
        g["total"] += 1
        if student_key in progress and progress[student_key].completed:
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
