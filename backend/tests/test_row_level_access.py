from datetime import datetime

from sqlmodel import select

from app.auth import hash_password
from app.models import Activity, EvidenceStatus, Participation, Student, StudentStatus, User, UserRole
from tests.test_activities import future_start


def _make_student(session, student_id, full_name):
    student = Student(
        student_id=student_id,
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


def _make_activity(session, name, created_by=None):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง SC101",
        created_by=created_by,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _make_participation(session, student_id, activity_id, evidence_status=EvidenceStatus.approved):
    participation = Participation(
        student_id=student_id, activity_id=activity_id, evidence_status=evidence_status
    )
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return participation


def _login(client, username, password):
    response = client.post("/auth/login", data={"username": username, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


def _setup_two_students_linked_user(session, client):
    own_student = _make_student(session, "OWN001", "เจ้าของบัญชี")
    other_student = _make_student(session, "OTHER001", "คนอื่น")
    staff_user = session.exec(select(User).where(User.username == "staff")).first()
    activity = _make_activity(session, "กิจกรรมทดสอบสิทธิ์", created_by=staff_user.id)

    own_participation = _make_participation(session, own_student.id, activity.id)
    other_participation = _make_participation(session, other_student.id, activity.id)

    linked_user = User(
        username="linked_student",
        hashed_password=hash_password("pw123456"),
        role=UserRole.student,
        student_id=own_student.id,
    )
    session.add(linked_user)
    session.commit()

    token = _login(client, "linked_student", "pw123456")
    return {
        "own_student": own_student,
        "other_student": other_student,
        "own_participation": own_participation,
        "other_participation": other_participation,
        "headers": {"Authorization": f"Bearer {token}"},
    }


def test_linked_student_sees_only_own_record_in_student_list(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get("/students", headers=ctx["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == ctx["own_student"].id


def test_linked_student_cannot_get_other_student_by_id(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get(f"/students/{ctx['other_student'].id}", headers=ctx["headers"])
    assert response.status_code == 403


def test_linked_student_can_get_own_student_by_id(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get(f"/students/{ctx['own_student'].id}", headers=ctx["headers"])
    assert response.status_code == 200
    assert response.json()["id"] == ctx["own_student"].id


def test_linked_student_sees_only_own_participations_in_list(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get("/participations", headers=ctx["headers"])
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["id"] == ctx["own_participation"].id


def test_linked_student_cannot_override_student_id_filter(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get(
        "/participations",
        params={"student_id": ctx["other_student"].id},
        headers=ctx["headers"],
    )
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["student_id"] == ctx["own_student"].id


def test_linked_student_cannot_get_other_participation_by_id(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get(f"/participations/{ctx['other_participation'].id}", headers=ctx["headers"])
    assert response.status_code == 403


def test_linked_student_can_get_own_participation_by_id(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.get(f"/participations/{ctx['own_participation'].id}", headers=ctx["headers"])
    assert response.status_code == 200
    assert response.json()["id"] == ctx["own_participation"].id


def test_unlinked_student_gets_empty_lists_not_error(client, session):
    # the shared "student" fixture user (conftest.py) has no student_id linkage
    headers = {"Authorization": f"Bearer {_login(client, 'student', 'student123')}"}
    _make_student(session, "SOMEONE", "คนอื่นอีกคน")

    students_response = client.get("/students", headers=headers)
    assert students_response.status_code == 200
    assert students_response.json()["total"] == 0

    participations_response = client.get("/participations", headers=headers)
    assert participations_response.status_code == 200
    assert participations_response.json()["total"] == 0


def test_staff_still_sees_all_students_and_participations(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    # default `client` fixture is authenticated as staff
    students_response = client.get("/students")
    assert students_response.json()["total"] == 2

    participations_response = client.get("/participations")
    assert participations_response.json()["total"] == 2


def test_linked_student_cannot_update_own_student_record(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.put(
        f"/students/{ctx['own_student'].id}",
        json={"year_level": 3},
        headers=ctx["headers"],
    )
    assert response.status_code == 403


def test_linked_student_cannot_delete_own_student_record(client, session):
    ctx = _setup_two_students_linked_user(session, client)
    response = client.delete(f"/students/{ctx['own_student'].id}", headers=ctx["headers"])
    assert response.status_code == 403


def test_student_cannot_create_activity(client, tokens):
    headers = {"Authorization": f"Bearer {tokens['student']}"}
    payload = {
        "name": "กิจกรรมที่นิสิตพยายามสร้าง",
        "activity_type": "วิชาการ",
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 10,
        "start_at": future_start(),
        "location": "ห้อง SC101",
        "hours": 4,
    }
    response = client.post("/activities", json=payload, headers=headers)
    assert response.status_code == 403


def test_student_cannot_update_or_delete_activity(client, tokens):
    activity = client.post(
        "/activities",
        json={
            "name": "กิจกรรมทดสอบสิทธิ์",
            "activity_type": "วิชาการ",
            "subcategory_id": 1,
            "is_required": False,
            "max_participants": 10,
            "start_at": future_start(),
            "location": "ห้อง SC101",
            "hours": 4,
        },
    ).json()
    headers = {"Authorization": f"Bearer {tokens['student']}"}

    update_response = client.put(
        f"/activities/{activity['id']}", json={"location": "ที่อื่น"}, headers=headers
    )
    assert update_response.status_code == 403

    delete_response = client.delete(f"/activities/{activity['id']}", headers=headers)
    assert delete_response.status_code == 403


def test_student_cannot_create_update_or_delete_participation(client, session, tokens):
    student = _make_student(session, "PERM001", "ทดสอบสิทธิ์")
    activity = _make_activity(session, "กิจกรรมสำหรับทดสอบสิทธิ์")
    participation = _make_participation(session, student.id, activity.id)
    headers = {"Authorization": f"Bearer {tokens['student']}"}

    create_response = client.post(
        "/participations",
        json={"student_id": student.id, "activity_id": activity.id},
        headers=headers,
    )
    assert create_response.status_code == 403

    update_response = client.put(
        f"/participations/{participation.id}",
        json={"evidence_status": "approved"},
        headers=headers,
    )
    assert update_response.status_code == 403

    delete_response = client.delete(f"/participations/{participation.id}", headers=headers)
    assert delete_response.status_code == 403
