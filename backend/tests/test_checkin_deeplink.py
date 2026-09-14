"""B3 — QR เก็บ URL เต็ม และ normalize_token รับได้ 3 รูปแบบ

จาก PHASE_F4_DeepLink_Checkin.md: กล้องมือถือปกติจะขึ้นปุ่ม "เปิดลิงก์" ให้
ก็ต่อเมื่อ QR เก็บ URL เต็ม ไม่ใช่ข้อความ token เปล่า ๆ — แต่ token เปล่ากับ
รูปแบบ `TSU-CHECKIN:` เดิมต้องยังใช้ได้ (QR ที่พิมพ์แจกไปแล้ว + ช่องกรอกมือ)
"""

from datetime import datetime, timedelta

import pytest
from sqlmodel import select

from app.auth import hash_password
from app.checkin import CHECKIN_QUERY_KEY, QR_PREFIX, normalize_token, qr_payload
from app.config import settings
from app.timeutil import now_th_naive
from app.models import (
    Activity,
    ApprovalStatus,
    Student,
    StudentStatus,
    User,
    UserRole,
)

TOKEN = "0123456789abcdef0123456789abcdef"


def _user_id(session, username):
    return session.exec(select(User).where(User.username == username)).first().id


def _make_linked_student_user(session, client, username="dl_student", student_code="9003001"):
    student = Student(
        student_id=student_code,
        full_name="นิสิตกดลิงก์จากกล้อง",
        faculty="วิศวกรรมศาสตร์",
        major="วิศวกรรมคอมพิวเตอร์",
        year_level=3,
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
    return student, {"Authorization": f"Bearer {login.json()['access_token']}"}


def _make_live_activity(session, owner_id, name="กิจกรรมกำลังจัด", max_participants=10):
    """กิจกรรมที่เริ่มตอนนี้พอดี (เวลาไทย) → อยู่กลางหน้าต่างเช็กอิน"""
    activity = Activity(
        name=name,
        activity_type="จิตอาสา",
        is_required=False,
        max_participants=max_participants,
        start_at=now_th_naive(),
        location="หอประชุม",
        hours=3,
        created_by=owner_id,
        approval_status=ApprovalStatus.approved,
        approved_by=owner_id,
        approved_at=datetime.utcnow(),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


# ---------- qr_payload: URL เต็ม ----------


def test_qr_payload_is_a_full_url_pointing_at_the_student_web_app():
    activity = Activity(
        name="x",
        activity_type="x",
        max_participants=1,
        start_at=datetime.utcnow(),
        location="x",
        hours=1,
        checkin_token=TOKEN,
    )
    payload = qr_payload(activity)

    base = settings.public_app_base_url.rstrip("/")
    assert payload == f"{base}/#/checkin?{CHECKIN_QUERY_KEY}={TOKEN}"
    # hash routing: main.dart ไม่ได้เรียก usePathUrlStrategy() จึงต้องมี `#`
    assert "/#/checkin?" in payload
    # ต้องวนกลับมาเป็น token เดิมได้ ไม่งั้น QR ที่ออกไปสแกนไม่ผ่าน
    assert normalize_token(payload) == TOKEN


@pytest.mark.parametrize(
    "base_url",
    [
        "https://activity.tsu.ac.th",
        "https://activity.tsu.ac.th/",       # slash ท้ายต้องไม่กลายเป็น //
        "  https://activity.tsu.ac.th  ",    # ช่องว่างติดมาจาก .env
        "activity.tsu.ac.th",                # ลืมใส่ scheme → ต้องเติม https ให้
    ],
)
def test_qr_payload_normalizes_a_sloppy_base_url(monkeypatch, base_url):
    """ตั้งค่าพลาดเล็ก ๆ ไม่ควรทำให้ QR สแกนแล้วกล้องไม่ขึ้นปุ่มเปิดลิงก์"""
    monkeypatch.setattr(settings, "public_app_base_url", base_url)
    activity = Activity(
        name="x",
        activity_type="x",
        max_participants=1,
        start_at=datetime.utcnow(),
        location="x",
        hours=1,
        checkin_token=TOKEN,
    )
    assert qr_payload(activity) == f"https://activity.tsu.ac.th/#/checkin?c={TOKEN}"


# ---------- normalize_token: รับ 3 รูปแบบ ----------


@pytest.mark.parametrize(
    "raw",
    [
        # 1. URL เต็มแบบ hash routing (ค่าที่ QR เก็บจริง)
        f"https://activity.tsu.ac.th/#/checkin?c={TOKEN}",
        f"http://localhost:8080/#/checkin?c={TOKEN}",
        # path url strategy (เผื่อวันหลังโปรเจกต์เปลี่ยนไปใช้)
        f"https://activity.tsu.ac.th/checkin?c={TOKEN}",
        # มีพารามิเตอร์อื่นปนมาด้วย
        f"https://activity.tsu.ac.th/#/checkin?c={TOKEN}&from=poster",
        f"https://activity.tsu.ac.th/checkin?utm=qr&c={TOKEN}",
        # 2. รูปแบบเดิมที่อาจพิมพ์แจกไปแล้ว
        f"{QR_PREFIX}{TOKEN}",
        f"  {QR_PREFIX}{TOKEN}  ",
        # 3. token เปล่าจากช่องกรอกมือ
        TOKEN,
        f"  {TOKEN}  ",
    ],
)
def test_normalize_token_accepts_all_three_shapes(raw):
    assert normalize_token(raw) == TOKEN


@pytest.mark.parametrize(
    "raw",
    [
        "",
        "   ",
        # URL ที่ไม่มีพารามิเตอร์ c เลย
        "https://activity.tsu.ac.th/#/checkin",
        "https://activity.tsu.ac.th/",
        "https://example.com/?x=1",
        # มี c= แต่ว่างเปล่า
        "https://activity.tsu.ac.th/#/checkin?c=",
        # ข้อความมั่วที่มีอักขระของ URL ปน
        "https://",
        "?c",
    ],
)
def test_normalize_token_rejects_urls_without_a_usable_token(raw):
    assert normalize_token(raw) == ""


def test_normalize_token_keeps_a_wrong_but_plain_code_as_is():
    """รหัสที่พิมพ์ผิดต้องถูกส่งต่อไปให้ backend ตัดสิน (จะกลายเป็น "QR ไม่ถูกต้อง")

    ไม่ใช่หน้าที่ของ normalize ที่จะตรวจว่ารหัสมีจริงไหม
    """
    assert normalize_token("รหัสมั่ว") == "รหัสมั่ว"


# ---------- ยิงผ่าน endpoint จริง ----------


def test_checkin_accepts_the_url_from_the_qr_endpoint(client, session):
    """ครบวง: staff ขอ QR → นิสิตยิง URL นั้นกลับมา → เช็กอินผ่าน"""
    staff_id = _user_id(session, "staff")
    activity = _make_live_activity(session, staff_id)

    qr = client.get(f"/activities/{activity.id}/checkin-qr")
    assert qr.status_code == 200, qr.text
    url = qr.json()["qr_payload"]
    assert url.startswith("http")

    _, headers = _make_linked_student_user(session, client)
    response = client.post("/participations/checkin", json={"token": url}, headers=headers)

    assert response.status_code == 200, response.text
    body = response.json()
    assert body["check_in_time"] is not None
    assert body["activity_name"] == activity.name
    # D2 ไม่เปลี่ยน: มาทางลิงก์ก็ยังไม่ได้ชั่วโมง
    assert body["hours_earned"] == 0
    assert body["evidence_status"] == "pending"


def test_checkin_still_accepts_the_legacy_prefixed_payload(client, session):
    activity = _make_live_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin",
        json={"token": f"{QR_PREFIX}{activity.checkin_token}"},
        headers=headers,
    )
    assert response.status_code == 200, response.text


def test_checkin_still_accepts_a_hand_typed_token(client, session):
    activity = _make_live_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin", json={"token": activity.checkin_token}, headers=headers
    )
    assert response.status_code == 200, response.text


def test_checkin_rejects_a_link_without_the_token(client, session):
    _make_live_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin",
        json={"token": "https://activity.tsu.ac.th/#/checkin"},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "QR ไม่ถูกต้อง"


def test_checkin_rejects_a_link_carrying_someone_elses_code(client, session):
    """ลิงก์รูปแบบถูกแต่ token ไม่มีจริง ต้องไม่หลุดเป็น 500"""
    _make_live_activity(session, _user_id(session, "admin"))
    _, headers = _make_linked_student_user(session, client)

    response = client.post(
        "/participations/checkin",
        json={"token": "https://activity.tsu.ac.th/#/checkin?c=deadbeef"},
        headers=headers,
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "QR ไม่ถูกต้อง"


def test_link_outside_the_window_is_still_rejected(client, session):
    """D1 ไม่เปลี่ยน: ลิงก์ที่ถ่ายรูปส่งต่อยังใช้ได้แค่ในช่วงเวลาเช็กอิน"""
    activity = _make_live_activity(session, _user_id(session, "admin"))
    activity.start_at = now_th_naive() - timedelta(days=2)
    session.add(activity)
    session.commit()

    _, headers = _make_linked_student_user(session, client)
    response = client.post(
        "/participations/checkin", json={"token": qr_payload(activity)}, headers=headers
    )
    assert response.status_code == 400
    assert response.json()["detail"] == "เลยเวลาเช็กอินแล้ว"


def test_staff_cannot_use_the_link_either(client, session):
    """เปิดลิงก์จากกล้องไม่ได้เปลี่ยนกฎว่าใครเช็กอินได้ — client fixture คือ staff"""
    activity = _make_live_activity(session, _user_id(session, "staff"))
    response = client.post(
        "/participations/checkin", json={"token": qr_payload(activity)}
    )
    assert response.status_code == 403
