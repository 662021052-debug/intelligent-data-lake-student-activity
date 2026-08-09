"""รายการกิจกรรม "ที่กำลังจะถึง" — ค่าเริ่มต้นของฝั่งนิสิต (Prompt B)

กิจกรรมที่จัดไปแล้วสร้างผ่าน API ไม่ได้ (กฎกันย้อนหลัง) เทสต์จึงเขียนลงฐานข้อมูลตรง ๆ
และอิงวันนี้เสมอ ไม่ฝังวันที่ตายตัวไว้ ไม่งั้นพอเวลาผ่านไปเทสต์จะพังเอง
"""

from datetime import datetime, timedelta, timezone

from sqlmodel import select

from app.models import Activity, ApprovalStatus, User

TZ_TH = timezone(timedelta(hours=7))


def _today_th() -> datetime:
    """เที่ยงคืนของวันนี้ตามเวลาไทย แบบไม่มีโซน"""
    now = datetime.now(TZ_TH)
    return datetime(now.year, now.month, now.day)


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _add_activity(session, start_at: datetime, name: str, approved: bool = True):
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
        approval_status=ApprovalStatus.approved if approved else ApprovalStatus.pending,
    )
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return activity


def _student_headers(tokens):
    return {"Authorization": f"Bearer {tokens['student']}"}


def _names(response):
    return [a["name"] for a in response.json()["items"]]


def test_upcoming_hides_past_and_sorts_nearest_first(client, session, tokens):
    """นิสิตเปิดหน้ามาต้องเจออันที่ใกล้ที่สุดก่อน และไม่ต้องเลื่อนผ่านของที่จบไปแล้ว"""
    _add_activity(session, _today_th() - timedelta(days=3), "จัดไปแล้ว")
    _add_activity(session, _today_th() + timedelta(days=30), "อีกเดือนหน้า")
    _add_activity(session, _today_th() + timedelta(days=2), "อีกสองวัน")
    _add_activity(session, _today_th() + timedelta(days=9), "อีกเก้าวัน")

    response = client.get(
        "/activities", params={"upcoming": "true"}, headers=_student_headers(tokens)
    )
    assert response.status_code == 200
    assert _names(response) == ["อีกสองวัน", "อีกเก้าวัน", "อีกเดือนหน้า"]
    # total ต้องนับเฉพาะที่ผ่านตัวกรองแล้ว ไม่งั้นการแบ่งหน้าจะเพี้ยน
    assert response.json()["total"] == 3


def test_activity_earlier_today_still_counts_as_upcoming(client, session, tokens):
    """ตัดที่ "วัน" ไม่ใช่ที่นาที — ให้ตรงกับกฎกันย้อนหลังตอนสร้าง/แก้ไข
    กิจกรรมที่เริ่มไปแล้วเมื่อเช้ายังต้องอยู่ในรายการของวันนี้"""
    _add_activity(session, _today_th() + timedelta(hours=1), "เช้าวันนี้")
    _add_activity(session, _today_th() - timedelta(minutes=1), "ปลายเมื่อวาน")

    response = client.get(
        "/activities", params={"upcoming": "true"}, headers=_student_headers(tokens)
    )
    assert _names(response) == ["เช้าวันนี้"]


def test_without_upcoming_the_list_is_unchanged(client, session):
    """ไม่ส่ง upcoming มา ต้องได้ทุกกิจกรรมเรียงวันจัดจากใหม่ไปเก่าเหมือนเดิม
    (มุมมอง staff/admin ต้องไม่กระทบ)"""
    _add_activity(session, _today_th() - timedelta(days=3), "จัดไปแล้ว")
    _add_activity(session, _today_th() + timedelta(days=2), "อีกสองวัน")

    response = client.get("/activities")
    assert _names(response) == ["อีกสองวัน", "จัดไปแล้ว"]
    assert response.json()["total"] == 2


def test_upcoming_still_hides_unapproved_from_students(client, session, tokens):
    """upcoming เป็นตัวกรองเพิ่ม ไม่ใช่ตัวแทน — กติกา "นิสิตเห็นเฉพาะที่อนุมัติแล้ว" ต้องอยู่ครบ"""
    _add_activity(session, _today_th() + timedelta(days=2), "อนุมัติแล้ว", approved=True)
    _add_activity(session, _today_th() + timedelta(days=1), "ยังไม่อนุมัติ", approved=False)

    response = client.get(
        "/activities", params={"upcoming": "true"}, headers=_student_headers(tokens)
    )
    assert _names(response) == ["อนุมัติแล้ว"]


def test_upcoming_works_together_with_search(client, session, tokens):
    """ช่องค้นหายังใช้ต่อได้ตามเดิม แค่ไม่ต้องกดก่อนถึงจะเห็นรายการ"""
    _add_activity(session, _today_th() + timedelta(days=2), "ค่ายอาสา")
    _add_activity(session, _today_th() + timedelta(days=3), "แข่งกีฬา")
    _add_activity(session, _today_th() - timedelta(days=2), "ค่ายอาสาปีที่แล้ว")

    response = client.get(
        "/activities",
        params={"upcoming": "true", "search": "ค่ายอาสา"},
        headers=_student_headers(tokens),
    )
    assert _names(response) == ["ค่ายอาสา"]


def test_upcoming_pagination_starts_from_the_nearest(client, session, tokens):
    """หน้าแรกต้องเป็นอันที่ใกล้ที่สุด ไม่ใช่อันที่วันจัดไกลสุด"""
    _add_activity(session, _today_th() + timedelta(days=20), "ไกลสุด")
    _add_activity(session, _today_th() + timedelta(days=1), "พรุ่งนี้")
    _add_activity(session, _today_th() + timedelta(days=5), "อีกห้าวัน")

    response = client.get(
        "/activities",
        params={"upcoming": "true", "limit": 1},
        headers=_student_headers(tokens),
    )
    assert _names(response) == ["พรุ่งนี้"]
    assert response.json()["total"] == 3
