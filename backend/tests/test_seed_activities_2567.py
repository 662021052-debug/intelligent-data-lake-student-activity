"""เฟส 4: กิจกรรมจำลองของชุดเกณฑ์ 2567

คุม: ทุกรายการเกณฑ์มีกิจกรรมทั้งที่จัดไปแล้วและที่กำลังจะถึง · ที่นั่งรอบย้อนหลังพอให้นิสิต
ทุกคนทำครบชั่วโมง (สิ่งที่เฟส 5 ต้องพึ่ง) · ชั่วโมงต่อรอบหารเกณฑ์ลงตัว · รันซ้ำไม่สร้างซ้ำ
"""

import math
from collections import defaultdict
from datetime import date, datetime, timedelta

import pytest
from sqlmodel import select

from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    CriteriaSet,
    Requirement,
    Student,
    User,
    UserRole,
)
from seed_activities_2567 import (
    ACTIVITY_TYPES,
    HEADROOM,
    PLANS,
    SeedAborted,
    populate,
    spread_dates,
)
from seed_criteria import REQUIREMENTS_2567_REGULAR
from seed_criteria import populate as seed_criteria

TODAY = date(2026, 9, 11)  # ปีการศึกษา 2569 ภาค 1 — วันที่ข้อมูลจริงถูกนำเข้า
YEAR_START = date(2026, 6, 1)
SEMESTER_2_END = date(2027, 3, 20)
PLAN_BY_NAME = {plan.requirement: plan for plan in PLANS}
SOCIAL_PAIR = ("ด้านการสร้างนวัตกรรมสังคม", "ด้านการเป็นผู้ประกอบการ")


@pytest.fixture
def criteria(session):
    seed_criteria(session)
    session.commit()
    return session.exec(select(CriteriaSet).where(CriteriaSet.code == "2567-regular")).one()


def _add_students(session, criteria_set, count, start=0):
    for i in range(start, start + count):
        session.add(
            Student(
                student_id=f"69{i:08d}",
                full_name=f"นิสิตทดสอบ {i}",
                faculty="คณะทดสอบ",
                major="ไม่ระบุ",
                year_level=1,
                cohort=2569,
                criteria_set_id=criteria_set.id,
            )
        )
    session.commit()


def _seed(session, today=TODAY, **kwargs):
    report = populate(session, today=today, **kwargs)
    session.commit()
    return report


def _by_requirement(session):
    """ชื่อรายการเกณฑ์ → กิจกรรมที่ผูกอยู่."""
    rows = session.exec(
        select(Requirement.name, Activity)
        .join(ActivityRequirement, ActivityRequirement.requirement_id == Requirement.id)
        .join(Activity, Activity.id == ActivityRequirement.activity_id)
    ).all()
    grouped = defaultdict(list)
    for name, activity in rows:
        grouped[name].append(activity)
    return grouped


def _is_past(activity, today=TODAY):
    return activity.start_at.date() < today


def test_plans_cover_every_2567_requirement_with_hours_that_divide_evenly():
    specs = {spec.name: spec for spec in REQUIREMENTS_2567_REGULAR}
    assert set(PLAN_BY_NAME) == set(specs)
    assert len(PLAN_BY_NAME) == len(PLANS)  # ไม่มีแผนซ้ำรายการเดียวกัน

    for plan in PLANS:
        # หารลงตัว = เฟส 5 ให้ชั่วโมงได้พอดีเกณฑ์ ไม่เกิน
        assert specs[plan.requirement].required_hours % plan.hours == 0, plan.requirement
        assert plan.capacity > 0 and plan.themes
        for theme in plan.themes:
            assert theme.activity_type in ACTIVITY_TYPES, theme.name
            assert theme.location


def test_every_requirement_gets_past_and_upcoming_activities(session, criteria):
    _add_students(session, criteria, 3)
    report = _seed(session)

    assert report.warnings == []
    admin = session.exec(select(User).where(User.role == UserRole.admin)).first()
    staff = session.exec(select(User).where(User.role == UserRole.staff)).first()
    requirements = {
        r.name: r
        for r in session.exec(select(Requirement).where(Requirement.criteria_set_id == criteria.id))
    }
    grouped = _by_requirement(session)

    assert set(grouped) == set(requirements)
    for name, activities in grouped.items():
        plan = PLAN_BY_NAME[name]
        past = [a for a in activities if _is_past(a)]
        upcoming = [a for a in activities if not _is_past(a)]
        # นิสิตแค่ 3 คน ที่นั่งรอบเดียวก็พอ แต่คนหนึ่งต้องเข้าคนละรอบให้ครบชั่วโมง
        assert len(past) >= math.ceil(requirements[name].required_hours / plan.hours), name
        assert len(upcoming) == plan.upcoming, name
        for activity in activities:
            assert activity.approval_status == ApprovalStatus.approved
            assert activity.approved_by == admin.id
            assert activity.created_by == staff.id
            assert not activity.is_hidden
            assert activity.hours == plan.hours
            assert activity.is_required == requirements[name].is_mandatory
            assert activity.subcategory_id is None  # จัดหมวดผ่านชุดเกณฑ์ใหม่อย่างเดียว
            assert activity.approved_at <= activity.start_at

    # กิจกรรมละหนึ่งรายการเกณฑ์ — ชั่วโมงนับเข้ารายการไหนต้องไม่กำกวม
    links = session.exec(select(ActivityRequirement)).all()
    per_activity = defaultdict(int)
    for link in links:
        per_activity[link.activity_id] += 1
    assert set(per_activity.values()) == {1}
    assert len(per_activity) == len(session.exec(select(Activity)).all())


def test_past_seats_are_enough_for_every_student_to_finish(session, criteria):
    students = 900
    _add_students(session, criteria, students)
    _seed(session)

    grouped = _by_requirement(session)
    specs = {spec.name: spec for spec in REQUIREMENTS_2567_REGULAR}
    for plan in PLANS:
        seats = sum(a.max_participants for a in grouped[plan.requirement] if _is_past(a))
        sessions_each = math.ceil(specs[plan.requirement].required_hours / plan.hours)
        assert seats >= students * sessions_each * plan.demand_share * HEADROOM, plan.requirement

    # สองด้านของ Social ใช้เป้า 16 ชม. ร่วมกัน — รวมกันต้องพอให้ทุกคนได้ 4 รอบ × 4 ชม.
    pair_seats = sum(
        a.max_participants for name in SOCIAL_PAIR for a in grouped[name] if _is_past(a)
    )
    assert pair_seats >= students * 4


def test_dates_stay_inside_their_windows(session, criteria):
    _add_students(session, criteria, 50)
    _seed(session)

    grouped = _by_requirement(session)
    everything = [a for activities in grouped.values() for a in activities]
    for activity in everything:
        day = activity.start_at.date()
        assert day.weekday() != 6, activity.name  # ไม่จัดวันอาทิตย์
        if _is_past(activity):
            assert YEAR_START <= day < TODAY, activity.name
        else:
            assert TODAY + timedelta(days=3) <= day <= SEMESTER_2_END, activity.name

    # ปฐมนิเทศต้องมาก่อนกิจกรรมอื่นทั้งหมดของปี
    orientation = min(a.start_at for a in grouped["กิจกรรมปฐมนิเทศนิสิต"])
    assert orientation == min(a.start_at for a in everything)


def test_rerun_creates_nothing_and_more_students_add_only_past_sessions(session, criteria):
    _add_students(session, criteria, 3)
    _seed(session)
    first = {a.id: (a.name, a.start_at) for a in session.exec(select(Activity)).all()}

    again = _seed(session)
    assert again.created == 0
    assert {a.id: (a.name, a.start_at) for a in session.exec(select(Activity)).all()} == first

    _add_students(session, criteria, 900, start=3)
    grown = _seed(session)
    assert grown.created > 0
    assert all(row.upcoming_created == 0 for row in grown.rows)

    activities = session.exec(select(Activity)).all()
    assert len({a.name for a in activities}) == len(activities)  # ชื่อไม่ชนกัน
    # ของเดิมไม่ถูกย้ายวันหรือเปลี่ยนชื่อ
    assert {a.id: (a.name, a.start_at) for a in activities if a.id in first} == first
    new = [a for a in activities if a.id not in first]
    assert new and all(_is_past(a) for a in new)


def test_existing_usable_activities_count_toward_seats(session, criteria):
    _add_students(session, criteria, 100)
    orientation = session.exec(
        select(Requirement)
        .where(Requirement.criteria_set_id == criteria.id)
        .where(Requirement.name == "กิจกรรมปฐมนิเทศนิสิต")
    ).one()

    def add(name, **kwargs):
        activity = Activity(
            name=name,
            activity_type="อบรม/สัมมนา",
            max_participants=5000,
            start_at=datetime(2026, 6, 10, 9),
            location="หอประชุมใหญ่",
            hours=4,
            **kwargs,
        )
        session.add(activity)
        session.flush()
        session.add(ActivityRequirement(activity_id=activity.id, requirement_id=orientation.id))

    add("ปฐมนิเทศที่รออนุมัติ", approval_status=ApprovalStatus.pending)
    add("ปฐมนิเทศที่ถูกซ่อน", approval_status=ApprovalStatus.approved, is_hidden=True)
    session.commit()

    # ที่รออนุมัติ/ถูกซ่อนสร้างการเข้าร่วมไม่ได้ จึงไม่นับเป็นที่นั่ง
    row = next(r for r in _seed(session).rows if r.requirement == "กิจกรรมปฐมนิเทศนิสิต")
    assert (row.past_existing, row.past_created) == (0, 1)

    add("ปฐมนิเทศที่ staff สร้างเอง", approval_status=ApprovalStatus.approved)
    session.commit()
    _add_students(session, criteria, 3000, start=100)  # ต้องการเกินรอบเดียวของแผน (2,500)
    row = next(r for r in _seed(session).rows if r.requirement == "กิจกรรมปฐมนิเทศนิสิต")
    assert row.past_existing == 2
    assert row.past_created == 0  # 5,000 + 2,500 ที่ ≥ 3,100 × 1.1


def test_before_the_year_starts_only_upcoming_sessions_are_made(session, criteria):
    report = _seed(session, today=YEAR_START)

    assert report.past_window is None
    assert any("ยังไม่เริ่ม" in w for w in report.warnings)
    activities = session.exec(select(Activity)).all()
    assert activities and all(a.start_at.date() >= YEAR_START for a in activities)


def test_aborts_without_the_2567_criteria_set(session):
    with pytest.raises(SeedAborted, match="seed_criteria"):
        populate(session, today=TODAY)
    assert session.exec(select(Activity)).all() == []


def test_aborts_without_an_admin_to_approve(session, criteria):
    for user in session.exec(select(User).where(User.role == UserRole.admin)).all():
        session.delete(user)
    session.commit()

    with pytest.raises(SeedAborted, match="admin"):
        populate(session, today=TODAY)
    assert session.exec(select(Activity)).all() == []


def test_spread_dates_is_deterministic_and_avoids_sundays():
    start, end = date(2026, 6, 1), date(2026, 9, 10)
    days = spread_dates(start, end, 12)

    assert days == spread_dates(start, end, 12)
    assert days == sorted(days)
    assert all(start <= d <= end and d.weekday() != 6 for d in days)
    assert spread_dates(start, end, 0) == []
    assert spread_dates(start, start, 3) == [start] * 3  # หน้าต่างวันเดียว


def test_students_see_upcoming_sessions_with_their_requirement(
    session, criteria, client, tokens, monkeypatch
):
    monkeypatch.setattr("app.routers.activities.today_th", lambda: TODAY)
    _add_students(session, criteria, 3)
    _seed(session)

    response = client.get(
        "/activities",
        params={"upcoming": True, "limit": 200},
        headers={"Authorization": f"Bearer {tokens['student']}"},
    )
    assert response.status_code == 200, response.text
    items = response.json()["items"]

    expected = sum(plan.upcoming for plan in PLANS)
    assert response.json()["total"] == expected
    assert all(len(item["requirement_ids"]) == 1 for item in items)
    assert all(item["start_at"] >= TODAY.isoformat() for item in items)
