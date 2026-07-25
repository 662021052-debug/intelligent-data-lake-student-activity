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


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _register_staff(client, tokens, username):
    client.post(
        "/auth/register",
        json={"username": username, "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_student(session, student_id_str="8201001", full_name="นิสิตสรุปชั่วโมง"):
    student = Student(
        student_id=student_id_str,
        full_name=full_name,
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


def _link_student_user(session, client, student, username="summary_student"):
    user = User(
        username=username,
        hashed_password=hash_password("pw123456"),
        role=UserRole.student,
        student_id=student.id,
    )
    session.add(user)
    session.commit()
    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_category_with_sub(session):
    category = HourCategory(name="หมวดทดสอบ", required_hours=10)
    session.add(category)
    session.commit()
    session.refresh(category)
    sub = HourSubcategory(category_id=category.id, name="ย่อยทดสอบ", required_hours=6)
    session.add(sub)
    session.commit()
    session.refresh(sub)
    return category, sub


def _make_activity(session, subcategory_id, created_by):
    activity = Activity(
        name="กิจกรรมทดสอบ",
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
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


def _join(session, student_id, activity_id, hours=4):
    session.add(
        Participation(
            student_id=student_id,
            activity_id=activity_id,
            evidence_status=EvidenceStatus.approved,
            hours_earned=hours,
        )
    )
    session.commit()


def test_staff_can_view_summary_of_student_in_own_activity(client, session):
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session))  # owned by default staff
    _join(session, student.id, activity.id, hours=4)

    response = client.get(f"/students/{student.id}/hours-summary")  # default client = staff
    assert response.status_code == 200
    body = response.json()
    assert any(c["earned_hours"] == 4 for c in body)


def test_staff_cannot_view_summary_of_student_not_in_own_activity(client, session, tokens):
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    other_staff_headers = _register_staff(client, tokens, "other_staff")
    other_staff_id = session.exec(select(User).where(User.username == "other_staff")).first().id
    activity = _make_activity(session, sub.id, other_staff_id)
    _join(session, student.id, activity.id)

    # default staff does not own the activity the student joined
    response = client.get(f"/students/{student.id}/hours-summary")
    assert response.status_code == 403


def test_admin_can_view_any_student_summary(client, session, tokens):
    _, sub = _make_category_with_sub(session)
    student = _make_student(session)
    activity = _make_activity(session, sub.id, _staff_id(session))
    _join(session, student.id, activity.id)

    response = client.get(f"/students/{student.id}/hours-summary", headers=_admin_headers(tokens))
    assert response.status_code == 200


def test_student_cannot_view_other_student_summary(client, session):
    _, sub = _make_category_with_sub(session)
    target = _make_student(session, student_id_str="8201002", full_name="เป้าหมาย")
    viewer = _make_student(session, student_id_str="8201003", full_name="ผู้ดู")
    viewer_headers = _link_student_user(session, client, viewer)

    response = client.get(f"/students/{target.id}/hours-summary", headers=viewer_headers)
    assert response.status_code == 403


def test_student_can_view_own_summary_via_id(client, session):
    _, sub = _make_category_with_sub(session)
    student = _make_student(session, student_id_str="8201004")
    headers = _link_student_user(session, client, student)
    activity = _make_activity(session, sub.id, _staff_id(session))
    _join(session, student.id, activity.id, hours=5)

    response = client.get(f"/students/{student.id}/hours-summary", headers=headers)
    assert response.status_code == 200


def test_hours_summary_nonexistent_student_returns_404(client, tokens):
    response = client.get("/students/999999/hours-summary", headers=_admin_headers(tokens))
    assert response.status_code == 404
