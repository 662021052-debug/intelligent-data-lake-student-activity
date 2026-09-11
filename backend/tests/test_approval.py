"""การอนุมัติการเข้าร่วม: ชั่วโมงจาก activity.hours + snapshot หน่วย/รายการเกณฑ์ ณ เวลาอนุมัติ."""

from datetime import datetime, timedelta

from sqlmodel import select

from app.approval import requirement_snapshot
from app.models import (
    Activity,
    ActivityRequirement,
    ApprovalStatus,
    CriteriaSet,
    LearningUnit,
    Participation,
    Requirement,
    Student,
    User,
    UserRole,
)


def _req(id, criteria_set_id, unit_id, name):
    return Requirement(
        id=id, criteria_set_id=criteria_set_id, learning_unit_id=unit_id, name=name, required_hours=4
    )


def test_snapshot_of_a_single_requirement():
    assert requirement_snapshot([_req(1, 10, 3, "ภาษา")], 10) == (3, "ภาษา")


def test_snapshot_prefers_the_students_own_criteria_set():
    requirements = [_req(1, 10, 3, "ของชุดใหม่"), _req(2, 20, 5, "ของชุดเก่า")]
    assert requirement_snapshot(requirements, 20) == (5, "ของชุดเก่า")
    # ไม่มีรายการในชุดของนิสิตเลย → ใช้ทั้งหมด (หน่วยต่างกันจึงไม่เดาหน่วย)
    assert requirement_snapshot(requirements, 99) == (None, "ของชุดใหม่ · ของชุดเก่า")


def test_snapshot_of_several_requirements_in_one_set():
    same_unit = [_req(2, 10, 1, "ข"), _req(1, 10, 1, "ก")]
    assert requirement_snapshot(same_unit, 10) == (1, "ก · ข")
    mixed_units = [_req(1, 10, 1, "ก"), _req(2, 10, 2, "ข")]
    assert requirement_snapshot(mixed_units, 10) == (None, "ก · ข")


def test_snapshot_of_a_legacy_activity_without_requirements():
    assert requirement_snapshot([], 10) == (None, None)


def test_staff_approval_takes_a_snapshot_and_rejection_clears_it(client, session, add_evidence):
    criteria_set = CriteriaSet(code="2567-regular", academic_year=2567, name="2567", total_required_hours=60)
    unit = LearningUnit(code="3", name="ศิลปวัฒนธรรมอาเซียน")
    session.add(criteria_set)
    session.add(unit)
    session.commit()
    requirement = Requirement(
        criteria_set_id=criteria_set.id,
        learning_unit_id=unit.id,
        name="ทักษะการใช้ภาษาเพื่อการสื่อสารในชีวิตประจำวัน",
        required_hours=10,
    )
    staff = session.exec(select(User).where(User.role == UserRole.staff)).first()
    student = Student(
        student_id="6920510001",
        full_name="นิสิตทดสอบ",
        faculty="คณะทดสอบ",
        major="ไม่ระบุ",
        year_level=1,
        criteria_set_id=criteria_set.id,
    )
    activity = Activity(
        name="English for Everyday Communication",
        activity_type="วิชาการ",
        max_participants=40,
        start_at=datetime.utcnow() - timedelta(days=1),
        location="อาคารเรียนรวม 1",
        hours=5,
        created_by=staff.id,
        approval_status=ApprovalStatus.approved,
    )
    session.add_all([requirement, student, activity])
    session.commit()
    session.add(ActivityRequirement(activity_id=activity.id, requirement_id=requirement.id))
    participation = Participation(student_id=student.id, activity_id=activity.id)
    session.add(participation)
    session.commit()
    add_evidence(participation.id)

    response = client.put(f"/participations/{participation.id}", json={"evidence_status": "approved"})
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["hours_earned"] == 5
    assert body["learning_unit_id"] == unit.id
    assert body["requirement_name"] == requirement.name

    response = client.put(f"/participations/{participation.id}", json={"evidence_status": "rejected"})
    assert response.status_code == 200, response.text
    body = response.json()
    assert (body["hours_earned"], body["learning_unit_id"], body["requirement_name"]) == (0, None, None)
