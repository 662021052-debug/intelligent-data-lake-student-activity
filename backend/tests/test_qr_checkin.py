"""เช็กอินหน้างานด้วย QR (ขอบเขต 6.4) — PHASE_OnSite_QR_Checkin.md"""

from datetime import datetime, timedelta

from sqlmodel import select

from app.auth import hash_password
from app.checkin import QR_PREFIX, normalize_token, qr_payload
from app.config import settings
from app.timeutil import now_th_naive
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    Participation,
    Student,
    StudentStatus,
    User,
    UserRole,
)


def _user_id(session, username):
    return session.exec(select(User).where(User.username == username)).first().id


def _headers(token):
    return {"Authorization": f"Bearer {token}"}


def _make_linked_student_user(session, client, username="qr_student", student_code="9002001"):
    student = Student(
        student_id=student_code,
        full_name="นิสิตสแกนคิวอาร์",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(student)
    session.commit()
    session.refresh(student)

    session.add(
        User(
            username=username,
            hashed_password=hash_password("pw123456"),
            role=UserRole.student,
            student_id=student.id,
        )
    )
    session.commit()

    login = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return student, _headers(login.json()["access_token"])


def _make_activity(
    session,
    owner_id,
    name="กิจกรรมหน้างาน",
    max_participants=10,
    starts_in=timedelta(0),
    hours=3,
    approved=True,
):
    """กิจกรรมที่ (โดยดีฟอลต์) เริ่มตอนนี้พอดี → อยู่ในช่วงเช็กอินแน่นอน"""
    activity = Activity(
        name=name,
        activity_type="จิตอาสา",
        is_required=False,
        max_participants=max_participants,
        # start_at เป็นเวลาไทยแบบไม่มีโซน (app/timeutil.py) — หน้าต่างเช็กอินเทียบกับเวลาไทย
        start_at=now_th_naive() + starts_in,
        location="หอประชุม",
        hours=hours,
        created_by=owner_id,
        approval_status=ApprovalStatus.approved if approved else ApprovalStatus.pending,
        approved_by=owner_id if approved else None,
        approved_at=datetime.utcnow() if approved else None,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def test_checkin_window_follows_thai_time_and_still_stores_utc(client, session):
    """งานที่เริ่มไปแล้ว 30 นาที (เวลาไทย) ต้องเช็กอินได้

    เดิมเทียบหน้าต่างกับ utcnow() ซึ่งช้ากว่าเวลาไทย 7 ชม. จึงตอบ "ยังไม่ถึงเวลาเช็กอิน"
    ส่วน check_in_time ที่บันทึกยังเป็น UTC เหมือนเดิม (หน้าเว็บแปลงด้วย serverTimeToLocal)
    """
    activity = _make_activity(session, _user_id(session, "admin"), starts_in=timedelta(minutes=-30))
    # เงื่อนไขที่โค้ดเดิมพลาด: เทียบด้วย UTC แล้วยังไม่ถึงเวลาเปิดหน้าต่าง
    assert datetime.utcnow() < activity.start_at - timedelta(minutes=settings.checkin_open_before_minutes)
    _, headers = _make_linked_student_user(session, client, username="qr_thai", student_code="9002099")

    before = datetime.utcnow()
    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 200, response.text
    checked_in = datetime.fromisoformat(response.json()["check_in_time"])
    assert before - timedelta(seconds=5) <= checked_in <= datetime.utcnow() + timedelta(seconds=5)


# ---------- B1: token ประจำกิจกรรม + endpoint แสดง QR ----------


def test_every_activity_gets_a_unique_checkin_token(session):
    admin_id = _user_id(session, "admin")
    first = _make_activity(session, admin_id, name="กิจกรรม ก")
    second = _make_activity(session, admin_id, name="กิจกรรม ข")

    assert first.checkin_token
    assert second.checkin_token
    assert first.checkin_token != second.checkin_token


def test_owner_staff_can_get_checkin_qr(client, session):
    staff_id = _user_id(session, "staff")
    activity = _make_activity(session, staff_id)

    response = client.get(f"/activities/{activity.id}/checkin-qr")
    assert response.status_code == 200, response.text
    body = response.json()
    # token ล้วนไว้ให้เจ้าหน้าที่อ่านให้นิสิตกรอกมือ, qr_payload เป็น URL เต็ม
    # เพื่อให้กล้องมือถือปกติขึ้นปุ่มเปิดลิงก์ให้ (F4/B3)
    assert body["token"] == activity.checkin_token
    assert body["qr_payload"] == (
        f"{settings.public_app_base_url.rstrip('/')}/#/checkin?c={activity.checkin_token}"
    )
    assert normalize_token(body["qr_payload"]) == activity.checkin_token
    assert body["activity_name"] == activity.name
    # หน้าต่างเวลาที่ backend บังคับจริง ส่งไปให้หน้าจอแสดงด้วย
    assert body["checkin_opens_at"] < body["start_at"] < body["checkin_closes_at"]


def test_admin_can_get_checkin_qr_of_any_activity(client, session, tokens):
    staff_id = _user_id(session, "staff")
    activity = _make_activity(session, staff_id)

    response = client.get(
        f"/activities/{activity.id}/checkin-qr", headers=_headers(tokens["admin"])
    )
    assert response.status_code == 200


def test_staff_cannot_get_checkin_qr_of_others_activity(client, session):
    admin_id = _user_id(session, "admin")
    activity = _make_activity(session, admin_id)

    # client fixture ล็อกอินเป็น staff ที่ไม่ได้เป็นเจ้าของกิจกรรมนี้
    response = client.get(f"/activities/{activity.id}/checkin-qr")
    assert response.status_code == 403


def test_student_cannot_get_checkin_qr(client, session):
    activity = _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.get(f"/activities/{activity.id}/checkin-qr", headers=headers)
    assert response.status_code == 403


def test_checkin_token_is_not_exposed_in_activity_read(client, session, tokens):
    activity = _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    detail = client.get(f"/activities/{activity.id}", headers=headers)
    assert detail.status_code == 200
    assert "checkin_token" not in detail.json()

    listing = client.get("/activities", headers=headers).json()
    assert all("checkin_token" not in item for item in listing["items"])


def test_checkin_qr_missing_activity_returns_404(client):
    assert client.get("/activities/99999/checkin-qr").status_code == 404


# ---------- B2: นิสิตสแกนแล้วเช็กอิน ----------


def test_registered_student_checks_in_successfully(client, session):
    # เริ่มอีก 30 นาที: ยังสมัครล่วงหน้าได้ และหน้าต่างเช็กอิน (เปิดก่อน 60 นาที) เปิดแล้ว
    activity = _make_activity(session, _user_id(session, "admin"), starts_in=timedelta(minutes=30))
    student, headers = _make_linked_student_user(session, client)
    registered = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=headers
    ).json()
    assert "id" in registered, registered

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["id"] == registered["id"]
    assert body["student_id"] == student.id
    assert body["check_in_time"] is not None
    assert body["activity_name"] == activity.name


def test_checkin_accepts_the_prefixed_qr_payload(client, session):
    activity = _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin",
        json={"token": f"{QR_PREFIX}{activity.checkin_token}"},
        headers=headers,
    )
    assert response.status_code == 200, response.text


def test_checkin_grants_no_hours(client, session):
    """D2: สแกน QR บันทึกแค่ว่ามาร่วมงาน ชั่วโมงยังต้องส่งหลักฐาน + อนุมัติ (A3)"""
    activity = _make_activity(session, _user_id(session, "admin"), hours=6)
    _, headers = _make_linked_student_user(session, client)

    body = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    ).json()
    assert body["hours_earned"] == 0
    assert body["evidence_status"] == EvidenceStatus.pending.value
    assert body["has_evidence"] is False


def test_walkup_student_gets_a_new_participation(client, session):
    activity = _make_activity(session, _user_id(session, "admin"))
    student, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 200, response.text

    rows = session.exec(
        select(Participation).where(
            Participation.student_id == student.id, Participation.activity_id == activity.id
        )
    ).all()
    assert len(rows) == 1
    assert rows[0].check_in_time is not None


def test_walkup_rejected_when_activity_is_full(client, session):
    activity = _make_activity(session, _user_id(session, "admin"), max_participants=1)
    _, first_headers = _make_linked_student_user(
        session, client, username="qr_a", student_code="9002010"
    )
    assert (
        client.post(
            "/participations/checkin", json={"token": activity.checkin_token}, headers=first_headers
        ).status_code
        == 200
    )

    _, second_headers = _make_linked_student_user(
        session, client, username="qr_b", student_code="9002011"
    )
    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=second_headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "กิจกรรมนี้เต็มแล้ว"


def test_checkin_twice_rejected(client, session):
    activity = _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    client.post("/participations/checkin", json={"token": activity.checkin_token}, headers=headers)
    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "คุณเช็กอินกิจกรรมนี้แล้ว"


def test_unknown_token_rejected(client, session):
    _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": "ไม่ใช่ของจริง"}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "QR ไม่ถูกต้อง"


def test_empty_token_rejected(client, session):
    _, headers = _make_linked_student_user(session, client)
    response = client.post("/participations/checkin", json={"token": ""}, headers=headers)
    assert response.status_code == 422


def test_checkin_before_window_rejected(client, session):
    activity = _make_activity(session, _user_id(session, "admin"), starts_in=timedelta(days=2))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "ยังไม่ถึงเวลาเช็กอิน"


def test_checkin_after_window_rejected(client, session):
    activity = _make_activity(session, _user_id(session, "admin"), starts_in=timedelta(days=-2))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "เลยเวลาเช็กอินแล้ว"


def test_checkin_just_inside_window_accepted(client, session):
    """เปิดให้เช็กอินก่อนเริ่ม 60 นาที — 30 นาทีก่อนเริ่มจึงต้องผ่าน"""
    activity = _make_activity(session, _user_id(session, "admin"), starts_in=timedelta(minutes=30))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 200, response.text


def test_checkin_unapproved_activity_rejected(client, session):
    activity = _make_activity(session, _user_id(session, "staff"), approved=False)
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "กิจกรรมนี้ยังไม่เปิดให้เช็กอิน"


# ---------- สแกนแทนกันไม่ได้ ----------


def test_staff_cannot_checkin(client, session):
    activity = _make_activity(session, _user_id(session, "staff"))
    # client fixture ล็อกอินเป็น staff
    response = client.post("/participations/checkin", json={"token": activity.checkin_token})
    assert response.status_code == 403


def test_admin_cannot_checkin(client, session, tokens):
    activity = _make_activity(session, _user_id(session, "admin"))
    response = client.post(
        "/participations/checkin",
        json={"token": activity.checkin_token},
        headers=_headers(tokens["admin"]),
    )
    assert response.status_code == 403


def test_student_account_without_student_record_cannot_checkin(client, session, tokens):
    activity = _make_activity(session, _user_id(session, "admin"))
    # บัญชี "student" จาก conftest ไม่ได้ผูกกับข้อมูลนิสิต
    response = client.post(
        "/participations/checkin",
        json={"token": activity.checkin_token},
        headers=_headers(tokens["student"]),
    )
    assert response.status_code == 403


def test_checkin_rejects_injected_student_id(client, session):
    """token เดียวกันใครก็ยิงได้ แต่ระบุตัวคนเช็กอินเองไม่ได้ — มาจาก JWT เท่านั้น"""
    activity = _make_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin",
        json={"token": activity.checkin_token, "student_id": 9999},
        headers=headers,
    )
    assert response.status_code == 422


def test_same_token_checks_in_each_student_separately(client, session):
    """นิสิตสองคนยิง token เดียวกัน → ต่างคนต่างได้ participation ของตัวเอง"""
    activity = _make_activity(session, _user_id(session, "admin"), max_participants=5)
    student_a, headers_a = _make_linked_student_user(
        session, client, username="qr_x", student_code="9002020"
    )
    student_b, headers_b = _make_linked_student_user(
        session, client, username="qr_y", student_code="9002021"
    )

    body_a = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers_a
    ).json()
    body_b = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers_b
    ).json()

    assert body_a["student_id"] == student_a.id
    assert body_b["student_id"] == student_b.id
    assert body_a["id"] != body_b["id"]


def test_checkin_does_not_touch_another_students_participation(client, session):
    """คนที่ยังไม่มาเช็กอิน ต้องไม่ถูกทำเครื่องหมายว่ามา"""
    activity = _make_activity(
        session, _user_id(session, "admin"), max_participants=5, starts_in=timedelta(minutes=30)
    )
    absent, absent_headers = _make_linked_student_user(
        session, client, username="qr_absent", student_code="9002030"
    )
    registered = client.post(
        "/participations/register", json={"activity_id": activity.id}, headers=absent_headers
    )
    assert registered.status_code == 201, registered.text

    _, present_headers = _make_linked_student_user(
        session, client, username="qr_present", student_code="9002031"
    )
    client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=present_headers
    )

    absent_row = session.exec(
        select(Participation).where(
            Participation.student_id == absent.id, Participation.activity_id == activity.id
        )
    ).first()
    assert absent_row.check_in_time is None
