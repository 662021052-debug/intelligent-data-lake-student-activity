from datetime import datetime, timedelta

from sqlmodel import select

from app.auth import hash_password
from app.models import Activity, ApprovalStatus, Student, StudentStatus, User, UserRole


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _admin_id(session):
    return session.exec(select(User).where(User.username == "admin")).first().id


def _make_linked_student_user(session, client, username="reg_student", student_id_str="9001001"):
    student = Student(
        student_id=student_id_str,
        full_name="นิสิตสมัครกิจกรรม",
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


def _make_approved_activity(
    session, admin_id, name="กิจกรรมเปิดรับสมัคร", max_participants=2, start_in_days=7
):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        hour_category="เลือกเสรี",
        is_required=False,
        max_participants=max_participants,
        start_at=datetime.utcnow() + timedelta(days=start_in_days),
        location="ห้อง SC101",
        created_by=admin_id,
        approval_status=ApprovalStatus.approved,
        approved_by=admin_id,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def test_student_can_register_for_approved_activity(client, session):
    activity = _make_approved_activity(session, _admin_id(session))
    student, headers = _make_linked_student_user(session, client)

    response = client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    assert response.status_code == 201
    body = response.json()
    assert body["student_id"] == student.id
    assert body["evidence_status"] == "pending"
    assert body["hours_earned"] == 0


def test_register_rejects_extra_hours_earned_field(client, session):
    activity = _make_approved_activity(session, _admin_id(session))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/register",
        json={"activity_id": activity.id, "hours_earned": 999},
        headers=headers,
    )
    assert response.status_code == 422


def test_register_rejects_student_id_override(client, session):
    activity = _make_approved_activity(session, _admin_id(session))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/register",
        json={"activity_id": activity.id, "student_id": 9999},
        headers=headers,
    )
    assert response.status_code == 422


def test_staff_cannot_use_self_registration(client):
    # default `client` fixture is authenticated as staff
    response = client.post("/participations/register", json={"activity_id": 1})
    assert response.status_code == 403


def test_register_duplicate_rejected(client, session):
    activity = _make_approved_activity(session, _admin_id(session))
    _, headers = _make_linked_student_user(session, client)

    client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    response = client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    assert response.status_code == 400


def test_register_pending_activity_rejected(client, session):
    admin_id = _admin_id(session)
    activity = Activity(
        name="กิจกรรมยังไม่อนุมัติ",
        activity_type="วิชาการ",
        hour_category="เลือกเสรี",
        is_required=False,
        max_participants=10,
        start_at=datetime.utcnow() + timedelta(days=7),
        location="ห้อง SC101",
        created_by=admin_id,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    _, headers = _make_linked_student_user(session, client)

    response = client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    assert response.status_code == 400


def test_register_full_activity_rejected(client, session):
    activity = _make_approved_activity(session, _admin_id(session), max_participants=1)
    _, first_headers = _make_linked_student_user(session, client, username="reg1", student_id_str="9001010")
    client.post("/participations/register", json={"activity_id": activity.id}, headers=first_headers)

    _, second_headers = _make_linked_student_user(session, client, username="reg2", student_id_str="9001011")
    response = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=second_headers
    )
    assert response.status_code == 400


def test_register_past_activity_rejected(client, session):
    activity = _make_approved_activity(session, _admin_id(session), start_in_days=-1)
    _, headers = _make_linked_student_user(session, client)

    response = client.post("/participations/register", json={"activity_id": activity.id}, headers=headers)
    assert response.status_code == 400


def test_student_can_cancel_own_pending_registration(client, session):
    activity = _make_approved_activity(session, _admin_id(session))
    _, headers = _make_linked_student_user(session, client)

    created = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=headers
    ).json()

    response = client.delete(f"/participations/{created['id']}", headers=headers)
    assert response.status_code == 204


def test_student_cannot_cancel_approved_registration(client, session, tokens):
    activity = _make_approved_activity(session, _admin_id(session))
    _, headers = _make_linked_student_user(session, client)

    created = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=headers
    ).json()
    client.put(
        f"/participations/{created['id']}",
        json={"evidence_status": "approved"},
        headers=_admin_headers(tokens),
    )

    response = client.delete(f"/participations/{created['id']}", headers=headers)
    assert response.status_code == 400


def test_student_cannot_cancel_others_registration(client, session):
    activity = _make_approved_activity(session, _admin_id(session), max_participants=5)
    _, headers_a = _make_linked_student_user(session, client, username="reg_a", student_id_str="9001020")
    _, headers_b = _make_linked_student_user(session, client, username="reg_b", student_id_str="9001021")

    created = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=headers_a
    ).json()

    response = client.delete(f"/participations/{created['id']}", headers=headers_b)
    assert response.status_code == 403
