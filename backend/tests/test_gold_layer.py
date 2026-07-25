"""Phase 10 — Gold Layer (Star Schema) tests.

Verify the gold_* views only count approved participations and that their
numbers match a direct computation from the operational tables.
"""

from datetime import datetime

from sqlalchemy import text
from sqlmodel import select

from app.gold import GOLD_VIEW_NAMES, create_gold_layer
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentStatus,
    User,
)


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _make_student(session, student_id_str="9001001", full_name="นิสิตโกลด์", faculty="วิศวกรรมศาสตร์", year_level=2):
    student = Student(
        student_id=student_id_str,
        full_name=full_name,
        faculty=faculty,
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=year_level,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


def _make_category_with_sub(session, cat_required=10, sub_required=6):
    category = HourCategory(name="หมวดโกลด์", required_hours=cat_required)
    session.add(category)
    session.commit()
    session.refresh(category)
    sub = HourSubcategory(category_id=category.id, name="ย่อยโกลด์", required_hours=sub_required)
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return category, sub


def _make_activity(session, subcategory_id, created_by, hours=4, name="กิจกรรมโกลด์"):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        hours=hours,
        subcategory_id=subcategory_id,
        created_by=created_by,
        approval_status=ApprovalStatus.approved,
        approved_by=created_by,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _join(session, student_id, activity_id, status=EvidenceStatus.approved, hours=4):
    p = Participation(
        student_id=student_id,
        activity_id=activity_id,
        evidence_status=status,
        hours_earned=hours,
    )
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def test_gold_fact_counts_only_approved(client, session):
    """gold_fact_participation excludes pending/rejected rows."""
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session), hours=4)

    approved = _join(session, student.id, activity.id, EvidenceStatus.approved, hours=4)
    _join(session, student.id, activity.id, EvidenceStatus.pending, hours=4)
    _join(session, student.id, activity.id, EvidenceStatus.rejected, hours=4)

    create_gold_layer(session)

    rows = session.execute(text("SELECT participation_id, hours_earned FROM gold_fact_participation")).all()
    assert len(rows) == 1
    assert rows[0][0] == approved.id
    assert rows[0][1] == 4


def test_gold_fact_date_key_and_dim_date(client, session):
    """The fact carries a YYYYMMDD date_key that joins to gold_dim_date."""
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session))  # start_at 2026-08-01
    _join(session, student.id, activity.id)

    create_gold_layer(session)

    fact = session.execute(text("SELECT date_key FROM gold_fact_participation")).all()
    assert fact[0][0] == 20260801

    dim = session.execute(
        text("SELECT year, month, semester, academic_year FROM gold_dim_date WHERE date_key = 20260801")
    ).all()
    assert dim[0][0] == 2026          # year
    assert dim[0][1] == 8             # month
    assert dim[0][2] == 1             # August -> semester 1
    assert dim[0][3] == 2569          # 2026 + 543 (Buddhist academic year)


def test_gold_student_hours_matches_operational(client, session):
    """gold_student_hours earned/completed matches a direct sum of approved hours."""
    category, sub = _make_category_with_sub(session, cat_required=10, sub_required=6)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session), hours=4)

    # 4 + 4 = 8 approved hours in this category (10 required -> not completed)
    _join(session, student.id, activity.id, EvidenceStatus.approved, hours=4)
    _join(session, student.id, activity.id, EvidenceStatus.approved, hours=4)
    _join(session, student.id, activity.id, EvidenceStatus.pending, hours=4)  # ignored

    create_gold_layer(session)

    row = session.execute(
        text(
            "SELECT earned_hours, required_hours, completed "
            "FROM gold_student_hours WHERE student_key = :sid AND category_key = :cid"
        ),
        {"sid": student.id, "cid": category.id},
    ).all()
    assert row[0][0] == 8          # only approved hours summed
    assert row[0][1] == 10         # category requirement
    assert row[0][2] == 0          # 8 < 10 -> not completed


def test_gold_student_hours_completed_flag(client, session):
    category, sub = _make_category_with_sub(session, cat_required=8, sub_required=4)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session), hours=8)
    _join(session, student.id, activity.id, EvidenceStatus.approved, hours=8)

    create_gold_layer(session)

    completed = session.execute(
        text("SELECT completed FROM gold_student_hours WHERE student_key = :sid AND category_key = :cid"),
        {"sid": student.id, "cid": category.id},
    ).all()[0][0]
    assert completed == 1  # 8 >= 8


def test_gold_student_hours_zero_row_for_no_participation(client, session):
    """A student with no approved hours still gets a 0 / required row per category."""
    category, _ = _make_category_with_sub(session, cat_required=10)
    student = _make_student(session)

    create_gold_layer(session)

    row = session.execute(
        text("SELECT earned_hours, completed FROM gold_student_hours WHERE student_key = :sid AND category_key = :cid"),
        {"sid": student.id, "cid": category.id},
    ).all()
    assert row[0][0] == 0
    assert row[0][1] == 0


def test_gold_dim_activity_and_student_present(client, session):
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session), hours=4)

    create_gold_layer(session)

    act = session.execute(
        text("SELECT name, hours, subcategory_key FROM gold_dim_activity WHERE activity_key = :aid"),
        {"aid": activity.id},
    ).all()
    assert act[0][1] == 4
    assert act[0][2] == sub.id

    stu = session.execute(
        text("SELECT student_code, faculty FROM gold_dim_student WHERE student_key = :sid"),
        {"sid": student.id},
    ).all()
    assert stu[0][0] == student.student_id


def test_gold_refresh_admin_only(client, tokens):
    """POST /gold/refresh is admin-only."""
    # default client is staff
    assert client.post("/gold/refresh").status_code == 403

    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    assert client.post("/gold/refresh", headers=student_headers).status_code == 403

    resp = client.post("/gold/refresh", headers=_admin_headers(tokens))
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "refreshed"
    assert set(body["views"]) == set(GOLD_VIEW_NAMES)


def test_gold_refresh_builds_queryable_views(client, session, tokens):
    """After an admin refresh the gold views exist and are queryable."""
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session))
    _join(session, student.id, activity.id)

    resp = client.post("/gold/refresh", headers=_admin_headers(tokens))
    assert resp.status_code == 200

    count = session.execute(text("SELECT COUNT(*) FROM gold_fact_participation")).all()[0][0]
    assert count == 1
