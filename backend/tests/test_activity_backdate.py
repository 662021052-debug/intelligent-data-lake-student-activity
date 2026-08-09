"""กันตั้งกิจกรรมย้อนหลัง (FIX_Activity_NoBackdate_and_HourCategoryAdmin งานที่ 1)

start_at ที่ฟอร์มส่งมาเป็น "เวลาไทยแบบไม่มีโซน" เทสต์จึงประกอบวันที่แบบเดียวกัน
และอิงวันนี้เสมอ ไม่ฝังวันที่ตายตัวไว้ ไม่งั้นพอเวลาผ่านไปเทสต์จะพังเอง
(เหมือนที่ `2026-08-01` ในเทสต์ชุดเดิมกลายเป็นอดีตไปแล้ว)
"""

from datetime import datetime, timedelta, timezone

from sqlmodel import select

from app.models import Activity, User
from app.routers.activities import BACKDATED_DETAIL

TZ_TH = timezone(timedelta(hours=7))


def _today_th() -> datetime:
    """เที่ยงคืนของวันนี้ตามเวลาไทย แบบไม่มีโซน"""
    now = datetime.now(TZ_TH)
    return datetime(now.year, now.month, now.day)


def _payload(start_at: datetime, name="กิจกรรมทดสอบวันย้อนหลัง"):
    return {
        "name": name,
        "activity_type": "วิชาการ",
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 50,
        "start_at": start_at.isoformat(),
        "location": "ห้อง SC101",
        "hours": 4,
    }


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _past_activity(session, start_at: datetime, name="กิจกรรมที่จัดไปแล้ว"):
    activity = Activity(
        name=name,
        activity_type="วิชาการ",
        subcategory_id=1,
        is_required=False,
        max_participants=50,
        start_at=start_at,
        location="ห้อง SC101",
        hours=4,
        created_by=_staff_id(session),
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


# ---------- สร้าง ----------


def test_create_activity_yesterday_is_rejected(client):
    response = client.post("/activities", json=_payload(_today_th() - timedelta(days=1)))
    assert response.status_code == 400
    assert response.json()["detail"] == BACKDATED_DETAIL
    # ต้องไม่หลุดเข้าไปในฐานข้อมูล
    assert client.get("/activities").json()["total"] == 0


def test_create_activity_far_in_the_past_is_rejected(client):
    response = client.post("/activities", json=_payload(_today_th() - timedelta(days=365)))
    assert response.status_code == 400


def test_create_activity_today_is_allowed(client):
    """วันนี้ยังสร้างได้ แม้เวลาที่กรอกจะผ่านไปแล้ว — กติกาห้ามแค่ "วันก่อนวันนี้"
    ให้ตรงกับ date picker ที่ล็อกได้แค่ระดับวัน"""
    response = client.post("/activities", json=_payload(_today_th() + timedelta(minutes=1)))
    assert response.status_code == 201


def test_create_activity_in_the_future_is_allowed(client):
    response = client.post("/activities", json=_payload(_today_th() + timedelta(days=30)))
    assert response.status_code == 201


def test_admin_cannot_backdate_either(client, tokens):
    """admin สร้างกิจกรรมแล้วอนุมัติอัตโนมัติ ถ้าเว้นช่องโหว่ไว้จะปั๊มชั่วโมงย้อนหลังได้"""
    response = client.post(
        "/activities",
        json=_payload(_today_th() - timedelta(days=1), name="กิจกรรมย้อนหลังของ admin"),
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400


# ---------- แก้ไข ----------


def test_update_cannot_move_start_at_into_the_past(client, session):
    created = client.post("/activities", json=_payload(_today_th() + timedelta(days=7))).json()
    yesterday = _today_th() - timedelta(days=1)

    response = client.put(f"/activities/{created['id']}", json={"start_at": yesterday.isoformat()})
    assert response.status_code == 400
    assert response.json()["detail"] == BACKDATED_DETAIL

    session.expire_all()
    assert session.get(Activity, created["id"]).start_at.date() != yesterday.date()


def test_update_can_move_start_at_forward(client):
    created = client.post("/activities", json=_payload(_today_th() + timedelta(days=7))).json()
    later = _today_th() + timedelta(days=14)

    response = client.put(f"/activities/{created['id']}", json={"start_at": later.isoformat()})
    assert response.status_code == 200
    assert response.json()["start_at"].startswith(later.date().isoformat())


def test_past_activity_can_still_edit_other_fields(client, session):
    activity = _past_activity(session, _today_th() - timedelta(days=30))

    response = client.put(f"/activities/{activity.id}", json={"location": "ห้องใหม่"})
    assert response.status_code == 200
    assert response.json()["location"] == "ห้องใหม่"


def test_past_activity_resending_unchanged_start_at_is_allowed(client, session):
    """ฟอร์มแก้ไขส่งทุกฟิลด์กลับมาเสมอ รวม start_at เดิมที่เป็นอดีต — ต้องไม่โดนบล็อก
    ไม่งั้นกิจกรรมที่จัดไปแล้วจะแก้อะไรไม่ได้เลยผ่านหน้าเว็บ"""
    past = _today_th() - timedelta(days=30)
    activity = _past_activity(session, past)

    response = client.put(
        f"/activities/{activity.id}",
        json={**_payload(past, name="ชื่อใหม่"), "location": "ห้องใหม่"},
    )
    assert response.status_code == 200
    assert response.json()["name"] == "ชื่อใหม่"


def test_past_activity_cannot_be_moved_to_another_past_day(client, session):
    activity = _past_activity(session, _today_th() - timedelta(days=30))
    other_past_day = _today_th() - timedelta(days=2)

    response = client.put(
        f"/activities/{activity.id}", json={"start_at": other_past_day.isoformat()}
    )
    assert response.status_code == 400
