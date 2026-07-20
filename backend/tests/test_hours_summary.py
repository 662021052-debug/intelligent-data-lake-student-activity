from datetime import datetime

from sqlmodel import select

from app.auth import hash_password
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
    UserRole,
)


def _admin_id(session):
    return session.exec(select(User).where(User.username == "admin")).first().id


def _make_linked_student_user(session, client, username="hours_student", student_id_str="9101001"):
    student = Student(
        student_id=student_id_str,
        full_name="นิสิตทดสอบชั่วโมง",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)

    user = User(
        username=username,
        hashed_password=hash_password("pw123456"),
        role=UserRole.student,
        student_id=student.id,
    )
    session.add(user)
    session.commit()

    login_response = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    token = login_response.json()["access_token"]
    return student, {"Authorization": f"Bearer {token}"}


def _make_category_with_sub(session, category_name, category_hours, sub_name, sub_hours):
    category = HourCategory(name=category_name, required_hours=category_hours)
    session.add(category)
    session.commit()
    session.refresh(category)

    subcategory = HourSubcategory(category_id=category.id, name=sub_name, required_hours=sub_hours)
    session.add(subcategory)
    session.commit()
    session.refresh(subcategory)
    return category, subcategory


def _make_activity(session, subcategory_id, admin_id, name="กิจกรรมทดสอบชั่วโมง"):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        subcategory_id=subcategory_id,
        created_by=admin_id,
        approval_status=ApprovalStatus.approved,
        approved_by=admin_id,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def test_hours_summary_rolls_up_approved_hours_only(client, session):
    admin_id = _admin_id(session)
    category, subcategory = _make_category_with_sub(session, "หมวดทดสอบ", 10, "ย่อยทดสอบ", 6)
    student, headers = _make_linked_student_user(session, client)

    activity_a = _make_activity(session, subcategory.id, admin_id, name="กิจกรรม A")
    activity_b = _make_activity(session, subcategory.id, admin_id, name="กิจกรรม B")

    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity_a.id,
            evidence_status=EvidenceStatus.approved,
            hours_earned=4,
        )
    )
    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity_b.id,
            evidence_status=EvidenceStatus.pending,  # not yet approved -> must NOT be counted
            hours_earned=100,
        )
    )
    session.commit()

    response = client.get("/students/me/hours-summary", headers=headers)
    assert response.status_code == 200
    body = response.json()

    result_category = next(c for c in body if c["id"] == category.id)
    assert result_category["earned_hours"] == 4
    assert result_category["required_hours"] == 10
    assert result_category["completed"] is False

    result_sub = result_category["subcategories"][0]
    assert result_sub["earned_hours"] == 4
    assert result_sub["completed"] is False  # 4 < 6


def test_hours_summary_category_completed_by_total_even_if_subcategory_short(client, session):
    admin_id = _admin_id(session)
    category, sub_a = _make_category_with_sub(session, "หมวดรวมยอด", 10, "ย่อย A", 8)
    sub_b = HourSubcategory(category_id=category.id, name="ย่อย B", required_hours=2)
    session.add(sub_b)
    session.commit()
    session.refresh(sub_b)

    student, headers = _make_linked_student_user(session, client)

    activity_a = _make_activity(session, sub_a.id, admin_id, name="กิจกรรม ย่อย A")
    activity_b = _make_activity(session, sub_b.id, admin_id, name="กิจกรรม ย่อย B")

    # ย่อย A ได้แค่ 3/8 (ไม่ครบ) แต่ย่อย B ได้ 7/2 (เกิน) รวมทั้งหมวด = 10 ครบพอดี
    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity_a.id,
            evidence_status=EvidenceStatus.approved,
            hours_earned=3,
        )
    )
    session.add(
        Participation(
            student_id=student.id,
            activity_id=activity_b.id,
            evidence_status=EvidenceStatus.approved,
            hours_earned=7,
        )
    )
    session.commit()

    response = client.get("/students/me/hours-summary", headers=headers)
    body = response.json()
    result_category = next(c for c in body if c["id"] == category.id)

    assert result_category["earned_hours"] == 10
    assert result_category["completed"] is True  # รวมยอดครบ แม้ย่อย A จะไม่ครบเกณฑ์ของตัวเอง

    sub_a_result = next(s for s in result_category["subcategories"] if s["id"] == sub_a.id)
    assert sub_a_result["completed"] is False  # 3 < 8, checkmark ของย่อยเองไม่ติ๊ก


def test_hours_summary_requires_student_role(client):
    # default `client` fixture is staff
    response = client.get("/students/me/hours-summary")
    assert response.status_code == 403


def test_hours_summary_unlinked_student_gets_403(client, tokens):
    # the shared "student" fixture user (conftest.py) has no student_id linkage
    headers = {"Authorization": f"Bearer {tokens['student']}"}
    response = client.get("/students/me/hours-summary", headers=headers)
    assert response.status_code == 403
