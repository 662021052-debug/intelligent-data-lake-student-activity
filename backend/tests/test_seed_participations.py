"""เฟส 5: การเข้าร่วมจำลองตามสถานะ ผ่าน/ไม่ผ่าน ในไฟล์นำเข้า

คุม: คนที่ผ่านได้ครบทุกรายการ 60 ชม. พอดี · คนที่ไม่ผ่านขาด 1–2 รายการจริง · Social สองด้าน
กระจายสมดุล · ไม่มีกิจกรรมไหนเกินที่นั่ง · ไม่มีใครลงสองกิจกรรมเวลาเดียวกัน · รันซ้ำไม่สร้างซ้ำ
"""

from collections import Counter, defaultdict
from datetime import date, datetime, timedelta

import pytest
from sqlmodel import func, select

from app.models import (
    Activity,
    ActivityRequirement,
    CriteriaSet,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    ImportedCompletion,
    Participation,
    Requirement,
    Student,
)
from seed_activities_2567 import populate as seed_activities
from seed_criteria import populate as seed_criteria
from seed_participations import SeedAborted, Slot, _StudentBooking, populate

TODAY = date(2026, 9, 11)
SOCIAL_PAIR = ("ด้านการสร้างนวัตกรรมสังคม", "ด้านการเป็นผู้ประกอบการ")


@pytest.fixture
def criteria(session):
    seed_criteria(session)
    session.commit()
    return session.exec(select(CriteriaSet).where(CriteriaSet.code == "2567-regular")).one()


def _add_students(session, criteria_set, passed, failed=0, start=0, cohort=2569):
    statuses = [ImportedCompletion.passed] * passed + [ImportedCompletion.failed] * failed
    for offset, status in enumerate(statuses):
        i = start + offset
        session.add(
            Student(
                student_id=f"{cohort % 100}{i:08d}",
                full_name=f"นิสิตทดสอบ {i}",
                faculty="คณะทดสอบ",
                major="ไม่ระบุ",
                year_level=1,
                cohort=cohort,
                criteria_set_id=criteria_set.id if criteria_set else None,
                imported_completion=status,
            )
        )
    session.commit()


@pytest.fixture
def world(session, criteria):
    """นิสิต 30 ผ่าน + 6 ไม่ผ่าน กับกิจกรรมเฟส 4 ที่คำนวณที่นั่งจากคนกลุ่มนี้."""
    _add_students(session, criteria, passed=30, failed=6)
    seed_activities(session, today=TODAY)
    session.commit()
    return criteria


def _seed(session, **kwargs):
    report = populate(session, today=TODAY, **kwargs)
    session.commit()
    return report


def _requirements(session, criteria_set):
    return {
        r.id: r
        for r in session.exec(select(Requirement).where(Requirement.criteria_set_id == criteria_set.id))
    }


def _earned(session):
    """student.id → requirement.id → ชั่วโมงที่ได้."""
    rows = session.exec(
        select(Participation.student_id, ActivityRequirement.requirement_id, Participation.hours_earned)
        .join(ActivityRequirement, ActivityRequirement.activity_id == Participation.activity_id)
    ).all()
    earned = defaultdict(lambda: defaultdict(float))
    for student_id, requirement_id, hours in rows:
        earned[student_id][requirement_id] += hours
    return earned


def _meets(requirements, earned):
    social = sum(earned.get(r.id, 0) for r in requirements.values() if r.name in SOCIAL_PAIR)
    others = all(
        earned.get(r.id, 0) >= r.required_hours
        for r in requirements.values()
        if r.name not in SOCIAL_PAIR
    )
    return others and social >= 16


def test_passed_students_finish_every_requirement_with_exactly_60_hours(session, world):
    report = _seed(session)

    assert (report.passed, report.failed) == (30, 6)
    assert report.hours_of_passed == {60: 30}
    requirements = _requirements(session, world)
    earned = _earned(session)
    for student in session.exec(select(Student)).all():
        if student.imported_completion != ImportedCompletion.passed:
            continue
        mine = earned[student.id]
        assert _meets(requirements, mine), student.student_id
        for requirement in requirements.values():
            if requirement.name not in SOCIAL_PAIR:
                assert mine[requirement.id] == requirement.required_hours, requirement.name
        assert sum(mine[r.id] for r in requirements.values() if r.name in SOCIAL_PAIR) == 16


def test_failed_students_miss_one_or_two_requirements(session, world):
    report = _seed(session)

    requirements = _requirements(session, world)
    earned = _earned(session)
    failed = [
        s for s in session.exec(select(Student)).all()
        if s.imported_completion == ImportedCompletion.failed
    ]
    assert len(failed) == 6
    for student in failed:
        mine = earned[student.id]
        assert not _meets(requirements, mine), student.student_id
        short = [
            r.name for r in requirements.values()
            if r.name not in SOCIAL_PAIR and mine[r.id] < r.required_hours
        ]
        if sum(mine[r.id] for r in requirements.values() if r.name in SOCIAL_PAIR) < 16:
            short.append("social")
        assert 1 <= len(short) <= 2, (student.student_id, short)
        assert sum(mine.values()) < 60
    assert sum(report.short_units.values()) >= 6


def test_rows_are_approved_with_activity_hours_and_a_requirement_snapshot(session, world):
    _seed(session)

    rows = session.exec(
        select(Participation, Activity, Requirement)
        .join(Activity, Activity.id == Participation.activity_id)
        .join(ActivityRequirement, ActivityRequirement.activity_id == Activity.id)
        .join(Requirement, Requirement.id == ActivityRequirement.requirement_id)
    ).all()
    assert rows
    for participation, activity, requirement in rows:
        assert participation.evidence_status == EvidenceStatus.approved
        assert participation.hours_earned == activity.hours
        assert participation.learning_unit_id == requirement.learning_unit_id
        assert participation.requirement_name == requirement.name
        assert activity.start_at.date() < TODAY  # ลงเฉพาะรอบที่จัดไปแล้ว
        assert activity.start_at - timedelta(minutes=20) <= participation.check_in_time
        assert participation.check_in_time <= activity.start_at


def test_social_sides_are_balanced_among_passed_students(session, world):
    report = _seed(session)

    # 30 คนหมุน 3 แบบ → แบบละ 10 พอดี
    assert sorted(report.social_patterns.values()) == [10, 10, 10]
    requirements = _requirements(session, world)
    earned = _earned(session)
    side_a, side_b = (
        next(r.id for r in requirements.values() if r.name == name) for name in SOCIAL_PAIR
    )
    passed = [
        s.id for s in session.exec(select(Student)).all()
        if s.imported_completion == ImportedCompletion.passed
    ]
    split = Counter((earned[sid][side_a], earned[sid][side_b]) for sid in passed)
    assert split == {(16, 0): 10, (0, 16): 10, (8, 8): 10}


def test_no_activity_overflows_and_no_student_joins_twice(session, world):
    _seed(session)

    counts = session.exec(
        select(Participation.activity_id, func.count()).group_by(Participation.activity_id)
    ).all()
    for activity_id, count in counts:
        assert count <= session.get(Activity, activity_id).max_participants

    pairs = session.exec(select(Participation.student_id, Participation.activity_id)).all()
    assert len(set(pairs)) == len(pairs)


def _slot(activity_id, day, hour, hours=3, remaining=10):
    return Slot(activity_id, datetime(2026, 7, day, hour), hours, remaining)


def test_booking_avoids_overlapping_times_when_it_can():
    booking = _StudentBooking(enrolled_from=None)
    first = booking.pick([_slot(1, 6, 9, hours=5)], 5)          # 09:00–14:00
    # 13:00 ของวันเดียวกันทับช่วงท้าย · วันถัดไปว่าง — ต้องได้วันถัดไปแม้ที่นั่งเหลือน้อยกว่า
    second = booking.pick([_slot(2, 6, 13, remaining=50), _slot(3, 7, 13, remaining=5)], 3)

    assert [s.activity_id for s in first + second] == [1, 3]
    assert booking.clashes == 0


def test_booking_accepts_a_clash_rather_than_leave_hours_missing():
    booking = _StudentBooking(enrolled_from=None)
    booking.pick([_slot(1, 6, 13)], 3)
    picked = booking.pick([_slot(2, 6, 13)], 3)  # รอบเดียวที่มี ทับเวลาเดิมพอดี

    assert [s.activity_id for s in picked] == [2]
    assert booking.clashes == 1


def test_booking_skips_full_rounds_and_rounds_before_enrolment():
    booking = _StudentBooking(enrolled_from=datetime(2026, 7, 7))
    pool = [_slot(1, 6, 9), _slot(2, 8, 9, remaining=0), _slot(3, 9, 9)]

    assert [s.activity_id for s in booking.pick(pool, 3)] == [3]
    assert pool[2].remaining == 9
    booking.release(pool[2])
    assert pool[2].remaining == 10 and not booking.booked


def test_real_scale_has_no_clashes(session, criteria):
    """ขนาดจริง (~2,000 คน) เฟส 4 วางรอบพอให้ทุกคนมีตารางไม่ทับกัน — ขนาดเล็กทำไม่ได้โดยโครงสร้าง
    (เช่น วิชาเลือก 4 รายการมีรายการละรอบเดียว วันเวลาเดียวกัน)."""
    _add_students(session, criteria, passed=1990, failed=10)
    seed_activities(session, today=TODAY)
    session.commit()

    report = _seed(session)
    assert report.clashes == 0
    assert report.hours_of_passed == {60: 1990}


def test_rerun_creates_nothing(session, world):
    first = _seed(session)
    total = len(session.exec(select(Participation)).all())

    again = _seed(session)
    assert again.participations == 0
    assert again.skipped_existing == first.passed + first.failed
    assert len(session.exec(select(Participation)).all()) == total


def test_same_seed_gives_the_same_result(session, world):
    def plan(seed):
        populate(session, today=TODAY, seed=seed)
        result = sorted(
            (p.student_id, p.activity_id)
            for p in session.exec(select(Participation)).all()
        )
        session.rollback()
        return result

    assert plan(7) == plan(7)
    assert plan(7) != plan(8)


def test_not_enough_seats_aborts_without_writing(session, world):
    orientation = session.exec(
        select(Activity)
        .join(ActivityRequirement, ActivityRequirement.activity_id == Activity.id)
        .join(Requirement, Requirement.id == ActivityRequirement.requirement_id)
        .where(Requirement.name == "กิจกรรมปฐมนิเทศนิสิต")
    ).all()
    for activity in orientation:
        activity.max_participants = 5
        session.add(activity)
    session.commit()

    with pytest.raises(SeedAborted, match="กิจกรรมปฐมนิเทศนิสิต"):
        populate(session, today=TODAY)
    session.rollback()
    assert session.exec(select(Participation)).all() == []


def test_students_without_status_or_activities_are_skipped(session, world):
    # นิสิตที่ผู้ดูแลเพิ่มเองไม่มีสถานะจากไฟล์
    session.add(
        Student(
            student_id="6999999999",
            full_name="เพิ่มผ่านหน้าจอ",
            faculty="คณะทดสอบ",
            major="ไม่ระบุ",
            year_level=1,
            criteria_set_id=world.id,
        )
    )
    # รุ่นเก่าอยู่ชุด legacy ซึ่งไม่มีกิจกรรมรอบที่จัดไปแล้วเลย
    category = HourCategory(name="พัฒนาทักษะชีวิต", required_hours=4)
    session.add(category)
    session.commit()
    session.add(HourSubcategory(category_id=category.id, name="หมวดย่อยเดิม", required_hours=4))
    session.commit()
    seed_criteria(session)
    session.commit()
    legacy = session.exec(select(CriteriaSet).where(CriteriaSet.code == "legacy-2566")).one()
    _add_students(session, legacy, passed=2, start=900, cohort=2565)

    report = _seed(session)
    assert report.skipped_no_status == 1
    assert report.skipped_no_activities == 2
    assert any("legacy-2566" in w for w in report.warnings)
    assert (report.passed, report.failed) == (30, 6)


def test_aborts_when_no_student_has_a_status(session, criteria):
    with pytest.raises(SeedAborted, match="load_students"):
        populate(session, today=TODAY)
