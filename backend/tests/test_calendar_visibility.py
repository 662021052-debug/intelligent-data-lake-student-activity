"""ปฏิทินกิจกรรม: staff เห็นกิจกรรมของทุกคนเหมือน admin (all_owners) แต่จัดการได้เฉพาะของตัวเอง

การมองเห็นในปฏิทินเปลี่ยน — สิทธิ์แก้ไข/ดูผู้เข้าร่วม/QR ต้องคงเดิม (403 เมื่อยิงตรง)
"""

from sqlmodel import select

from app.models import Activity
from tests.test_activities import _admin_headers, _register_staff, future_start, make_activity


def _payload(name):
    return {
        "name": name,
        "activity_type": "วิชาการ",
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 50,
        "start_at": future_start(),
        "location": "ห้อง SC101",
        "hours": 4,
    }


def _ids(response):
    assert response.status_code == 200, response.text
    return {a["id"]: a for a in response.json()["items"]}


def _setup(client, tokens):
    admin = _admin_headers(tokens)
    admin_activity = client.post("/activities", json=_payload("กิจกรรมของ admin"), headers=admin).json()
    own_activity = make_activity(client, name="กิจกรรมของ staff").json()  # client เริ่มต้น = staff
    return admin, admin_activity, own_activity


def test_staff_calendar_sees_all_owners_but_management_page_stays_own(client, tokens):
    admin, admin_activity, own_activity = _setup(client, tokens)

    # หน้าจัดการกิจกรรม (ไม่ส่ง all_owners) — เดิม: เฉพาะของตัวเอง
    management = _ids(client.get("/activities"))
    assert own_activity["id"] in management and admin_activity["id"] not in management

    # ปฏิทิน — เห็นเท่า admin
    calendar = _ids(client.get("/activities", params={"all_owners": "true", "limit": 200}))
    admin_view = _ids(client.get("/activities", params={"limit": 200}, headers=admin))
    assert set(calendar) == set(admin_view)
    assert client.get("/activities", params={"all_owners": "true"}).json()["total"] == \
        client.get("/activities", headers=admin).json()["total"]

    # จัดการได้เฉพาะของตัวเอง
    assert calendar[own_activity["id"]]["can_manage"] is True
    assert calendar[admin_activity["id"]]["can_manage"] is False
    # admin จัดการได้ทุกอัน ส่ง all_owners ก็ไม่เปลี่ยนอะไร
    assert all(a["can_manage"] is True for a in admin_view.values())
    assert set(_ids(client.get("/activities", params={"all_owners": "true", "limit": 200}, headers=admin))) == set(admin_view)


def test_staff_still_cannot_manage_others_activity_seen_in_calendar(client, tokens):
    admin, admin_activity, _ = _setup(client, tokens)
    target = admin_activity["id"]
    assert target in _ids(client.get("/activities", params={"all_owners": "true"}))

    # สิทธิ์จริงที่ endpoint ไม่เปลี่ยน
    assert client.put(f"/activities/{target}", json=_payload("staff แอบแก้")).status_code == 403
    assert client.get(f"/activities/{target}/participations").status_code == 403
    assert client.get(f"/activities/{target}/checkin-qr").status_code == 403
    assert client.delete(f"/activities/{target}").status_code == 403
    assert client.get(f"/activities/{target}").status_code == 403
    # ข้อมูลไม่ถูกแก้
    assert client.get(f"/activities/{target}", headers=admin).json()["name"] == "กิจกรรมของ admin"


def test_second_staff_sees_first_staffs_activity_in_calendar_without_manage(client, tokens):
    _, _, first_staff_activity = _setup(client, tokens)
    staff2 = _register_staff(client, tokens, "staff_calendar_2")

    calendar = _ids(client.get("/activities", params={"all_owners": "true", "limit": 200}, headers=staff2))
    assert calendar[first_staff_activity["id"]]["can_manage"] is False
    assert first_staff_activity["id"] not in _ids(client.get("/activities", headers=staff2))
    assert client.put(
        f"/activities/{first_staff_activity['id']}", json=_payload("แก้ของคนอื่น"), headers=staff2
    ).status_code == 403


def test_all_owners_does_not_widen_what_students_see(client, tokens, session):
    admin, admin_activity, pending_staff_activity = _setup(client, tokens)  # ของ staff ยังรออนุมัติ
    hidden = client.post("/activities", json=_payload("กิจกรรมที่ซ่อน"), headers=admin).json()
    row = session.exec(select(Activity).where(Activity.id == hidden["id"])).one()
    row.is_hidden = True
    session.add(row)
    session.commit()

    student = {"Authorization": f"Bearer {tokens['student']}"}
    plain = _ids(client.get("/activities", params={"limit": 200}, headers=student))
    widened = _ids(client.get("/activities", params={"all_owners": "true", "limit": 200}, headers=student))
    assert set(plain) == set(widened)
    assert admin_activity["id"] in widened
    assert pending_staff_activity["id"] not in widened
    assert hidden["id"] not in widened
    assert all(a["can_manage"] is False for a in widened.values())
