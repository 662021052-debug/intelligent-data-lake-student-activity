"""เวลาสิ้นสุดกิจกรรม (activity.end_at) — ไม่บังคับ · ต้องอยู่หลัง start_at

end_at เป็นเวลาไทยแบบไม่มีโซนเหมือน start_at และเป็นข้อมูลประกอบเท่านั้น: เทสต์ท้ายไฟล์
ยืนยันว่าไม่กระทบช่วงเช็กอินที่คำนวณจาก start_at + hours
"""

from datetime import datetime, timedelta, timezone

from sqlmodel import select

from app.checkin import checkin_window
from app.models import Activity, User
from app.routers.activities import END_BEFORE_START_DETAIL

TZ_TH = timezone(timedelta(hours=7))


def _tomorrow_9am() -> datetime:
    now = datetime.now(TZ_TH)
    return datetime(now.year, now.month, now.day, 9) + timedelta(days=1)


def _payload(start_at: datetime, end_at=None, **extra):
    body = {
        "name": "กิจกรรมทดสอบเวลาสิ้นสุด",
        "activity_type": "วิชาการ",
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 50,
        "start_at": start_at.isoformat(),
        "location": "ห้อง SC101",
        "hours": 4,
    }
    if end_at is not None:
        body["end_at"] = end_at.isoformat()
    body.update(extra)
    return body


# ---------- สร้าง ----------


def test_create_without_end_at_still_works(client):
    response = client.post("/activities", json=_payload(_tomorrow_9am()))
    assert response.status_code == 201, response.text
    assert response.json()["end_at"] is None


def test_create_with_end_at_after_start_is_saved_and_returned(client):
    start = _tomorrow_9am()
    end = start + timedelta(hours=4)
    response = client.post("/activities", json=_payload(start, end))
    assert response.status_code == 201, response.text
    assert datetime.fromisoformat(response.json()["end_at"]) == end

    # อ่านกลับผ่าน list ก็ต้องเห็นค่าเดิม (ไม่ใช่แค่ response ของ POST)
    listed = client.get("/activities").json()["items"][0]
    assert datetime.fromisoformat(listed["end_at"]) == end


def test_create_with_end_at_on_a_later_day_is_allowed(client):
    start = _tomorrow_9am()
    response = client.post("/activities", json=_payload(start, start + timedelta(days=2)))
    assert response.status_code == 201, response.text


def test_create_with_end_at_before_start_is_rejected_in_thai(client):
    start = _tomorrow_9am()
    response = client.post("/activities", json=_payload(start, start - timedelta(hours=1)))
    assert response.status_code == 422
    assert response.json()["detail"] == END_BEFORE_START_DETAIL
    assert client.get("/activities").json()["total"] == 0  # ต้องไม่หลุดเข้าฐานข้อมูล


def test_create_with_end_at_equal_to_start_is_rejected(client):
    start = _tomorrow_9am()
    response = client.post("/activities", json=_payload(start, start))
    assert response.status_code == 422
    assert response.json()["detail"] == END_BEFORE_START_DETAIL


def test_create_with_timezone_aware_end_is_compared_in_thai_time(client):
    """08:00+07:00 = 01:00Z: เทียบหลังแปลงเป็นเวลาไทย ไม่ใช่ TypeError (naive vs aware)"""
    start = _tomorrow_9am()
    before = (start - timedelta(hours=1)).replace(tzinfo=TZ_TH)
    response = client.post("/activities", json=_payload(start, before))
    assert response.status_code == 422
    after = (start + timedelta(hours=1)).replace(tzinfo=TZ_TH)
    assert client.post("/activities", json=_payload(start, after)).status_code == 201


# ---------- แก้ไข ----------


def _create(client, end=True):
    start = _tomorrow_9am()
    response = client.post(
        "/activities", json=_payload(start, start + timedelta(hours=4) if end else None)
    )
    assert response.status_code == 201, response.text
    return response.json()


def test_update_can_set_change_and_clear_end_at(client):
    created = _create(client, end=False)
    start = datetime.fromisoformat(created["start_at"])
    url = f"/activities/{created['id']}"

    set_it = client.put(url, json={"end_at": (start + timedelta(hours=3)).isoformat()})
    assert set_it.status_code == 200, set_it.text
    assert datetime.fromisoformat(set_it.json()["end_at"]) == start + timedelta(hours=3)

    # ไม่ส่งคีย์ end_at = ไม่แตะของเดิม
    untouched = client.put(url, json={"location": "ห้องใหม่"})
    assert datetime.fromisoformat(untouched.json()["end_at"]) == start + timedelta(hours=3)

    # ส่ง null มา = ล้าง
    cleared = client.put(url, json={"end_at": None})
    assert cleared.status_code == 200, cleared.text
    assert cleared.json()["end_at"] is None


def test_update_end_at_not_after_start_is_rejected(client):
    created = _create(client, end=False)
    start = datetime.fromisoformat(created["start_at"])
    response = client.put(
        f"/activities/{created['id']}", json={"end_at": (start - timedelta(minutes=1)).isoformat()}
    )
    assert response.status_code == 422
    assert response.json()["detail"] == END_BEFORE_START_DETAIL


def test_update_moving_start_past_existing_end_is_rejected(client):
    """ส่งแค่ start_at ใหม่ที่เลยเวลาสิ้นสุดเดิม ก็ต้องไม่ผ่าน"""
    created = _create(client)
    start = datetime.fromisoformat(created["start_at"])
    response = client.put(
        f"/activities/{created['id']}", json={"start_at": (start + timedelta(days=1)).isoformat()}
    )
    assert response.status_code == 422
    assert response.json()["detail"] == END_BEFORE_START_DETAIL


def test_update_that_does_not_touch_times_is_not_blocked(client):
    created = _create(client)
    response = client.put(f"/activities/{created['id']}", json={"name": "ชื่อใหม่"})
    assert response.status_code == 200, response.text


def test_update_of_old_activity_without_end_at_keeps_working(client, session):
    """กิจกรรมเดิมก่อนมีคอลัมน์นี้ (end_at เป็น NULL) ต้องแก้ไขฟิลด์อื่นได้ตามปกติ"""
    old = Activity(
        name="กิจกรรมเดิม",
        activity_type="วิชาการ",
        subcategory_id=1,
        max_participants=10,
        start_at=_tomorrow_9am(),
        location="ห้อง A",
        hours=2,
        created_by=session.exec(select(User).where(User.username == "staff")).first().id,
    )
    session.add(old)
    session.commit()
    session.refresh(old)
    assert old.end_at is None
    assert client.put(f"/activities/{old.id}", json={"name": "แก้ชื่อ"}).status_code == 200


# ---------- ไม่กระทบการนับชั่วโมง / เช็กอิน ----------


def test_end_at_does_not_change_checkin_window(session):
    start = _tomorrow_9am()
    plain = Activity(
        name="ก", activity_type="x", max_participants=1, start_at=start, location="a", hours=4
    )
    with_end = Activity(
        name="ข",
        activity_type="x",
        max_participants=1,
        start_at=start,
        end_at=start + timedelta(hours=12),
        location="a",
        hours=4,
    )
    assert checkin_window(plain) == checkin_window(with_end)
