from datetime import datetime, timedelta

from tests.test_students import make_student


def future_start(days: int = 30) -> str:
    """วันเวลาเริ่มกิจกรรมข้างหน้า — สร้างกิจกรรมย้อนหลังไม่ได้แล้ว
    (ดู test_activity_backdate.py) และการฝังวันที่ตายตัวก็พังเองเมื่อเวลาผ่านไป"""
    return (datetime.now() + timedelta(days=days)).replace(microsecond=0).isoformat()


def make_activity(client, name="กิจกรรมทดสอบ", activity_type="วิชาการ", hours=4):
    payload = {
        "name": name,
        "activity_type": activity_type,
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 50,
        "start_at": future_start(),
        "location": "ห้อง SC101",
        "hours": hours,
    }
    return client.post("/activities", json=payload)


def test_create_and_get_activity(client):
    response = make_activity(client)
    assert response.status_code == 201
    body = response.json()
    assert body["name"] == "กิจกรรมทดสอบ"

    get_response = client.get(f"/activities/{body['id']}")
    assert get_response.status_code == 200
    assert get_response.json()["max_participants"] == 50


def test_list_activities_filter_by_type(client):
    make_activity(client, name="ค่ายอาสา", activity_type="จิตอาสา")
    make_activity(client, name="แข่งกีฬา", activity_type="กีฬา")

    response = client.get("/activities", params={"activity_type": "จิตอาสา"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "ค่ายอาสา"


def test_update_activity(client):
    created = make_activity(client).json()
    response = client.put(f"/activities/{created['id']}", json={"location": "หอประชุมใหญ่"})
    assert response.status_code == 200
    assert response.json()["location"] == "หอประชุมใหญ่"


def test_delete_activity(client):
    created = make_activity(client).json()
    response = client.delete(f"/activities/{created['id']}")
    assert response.status_code == 204

    get_response = client.get(f"/activities/{created['id']}")
    assert get_response.status_code == 404


def test_list_activities_order_is_stable_after_approval(client, tokens):
    """อนุมัติกิจกรรมแล้วลำดับในรายการต้องไม่เปลี่ยน (เรียงตามวันจัดกิจกรรมเสมอ)."""
    # สร้างสลับวันไปมา เพื่อให้ลำดับ insert ไม่ตรงกับลำดับที่ควรแสดง
    for name, start_at in (
        ("กิจกรรม ก", future_start(32)),
        ("กิจกรรม ข", future_start(30)),
        ("กิจกรรม ค", future_start(31)),
    ):
        response = client.post(
            "/activities",
            json={
                "name": name,
                "activity_type": "วิชาการ",
                "subcategory_id": 1,
                "is_required": False,
                "max_participants": 50,
                "start_at": start_at,
                "location": "ห้อง SC101",
                "hours": 4,
            },
        )
        assert response.status_code == 201

    expected = ["กิจกรรม ก", "กิจกรรม ค", "กิจกรรม ข"]  # start_at ใหม่สุดขึ้นก่อน

    def names():
        return [a["name"] for a in client.get("/activities").json()["items"]]

    assert names() == expected

    middle = next(a for a in client.get("/activities").json()["items"] if a["name"] == "กิจกรรม ค")
    approve = client.patch(f"/activities/{middle['id']}/approve", headers=_admin_headers(tokens))
    assert approve.status_code == 200
    assert names() == expected


def test_get_nonexistent_activity_returns_404(client):
    response = client.get("/activities/9999")
    assert response.status_code == 404


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _student_headers(tokens):
    return {"Authorization": f"Bearer {tokens['student']}"}


def _staff_id(client, tokens):
    response = client.get("/auth/users", headers=_admin_headers(tokens))
    for u in response.json()["items"]:
        if u["username"] == "staff":
            return u["id"]
    raise AssertionError("seeded staff user not found")


def _register_staff(client, tokens, username):
    client.post(
        "/auth/register",
        json={"username": username, "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    login_response = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return {"Authorization": f"Bearer {login_response.json()['access_token']}"}


def test_staff_cannot_see_admin_created_activity(client, tokens):
    # C1: ownership filter is real — an activity created by admin is invisible to staff
    admin_activity = client.post(
        "/activities",
        json={
            "name": "กิจกรรมที่ admin สร้าง",
            "activity_type": "วิชาการ",
            "subcategory_id": 1,
            "is_required": False,
            "max_participants": 50,
            "start_at": future_start(),
            "location": "ห้อง SC101",
            "hours": 4,
        },
        headers=_admin_headers(tokens),
    ).json()

    # default client is staff
    listing = client.get("/activities").json()
    assert all(item["id"] != admin_activity["id"] for item in listing["items"])
    assert client.get(f"/activities/{admin_activity['id']}").status_code == 403


def test_staff_created_activity_is_pending_and_owned(client, tokens):
    created = make_activity(client, name="กิจกรรมของ staff").json()
    assert created["approval_status"] == "pending"
    assert created["created_by"] == _staff_id(client, tokens)


def test_admin_created_activity_is_auto_approved(client, tokens):
    response = client.post(
        "/activities",
        json={
            "name": "กิจกรรมของ admin",
            "activity_type": "วิชาการ",
            "subcategory_id": 1,
            "is_required": False,
            "max_participants": 50,
            "start_at": future_start(),
            "location": "ห้อง SC101",
            "hours": 4,
        },
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 201
    body = response.json()
    assert body["approval_status"] == "approved"
    assert body["approved_by"] is not None


def test_second_staff_cannot_see_or_edit_first_staffs_activity(client, tokens):
    created = make_activity(client, name="กิจกรรมของ staff คนแรก").json()
    other_staff_headers = _register_staff(client, tokens, "staff2")

    list_response = client.get("/activities", headers=other_staff_headers)
    assert list_response.json()["total"] == 0

    get_response = client.get(f"/activities/{created['id']}", headers=other_staff_headers)
    assert get_response.status_code == 403

    update_response = client.put(
        f"/activities/{created['id']}", json={"location": "ที่อื่น"}, headers=other_staff_headers
    )
    assert update_response.status_code == 403

    delete_response = client.delete(f"/activities/{created['id']}", headers=other_staff_headers)
    assert delete_response.status_code == 403


def test_staff_cannot_approve_activity(client):
    created = make_activity(client, name="กิจกรรมรออนุมัติ").json()
    response = client.patch(f"/activities/{created['id']}/approve")
    assert response.status_code == 403


def test_admin_can_approve_activity(client, tokens):
    created = make_activity(client, name="กิจกรรมรอ admin อนุมัติ").json()
    response = client.patch(f"/activities/{created['id']}/approve", headers=_admin_headers(tokens))
    assert response.status_code == 200
    body = response.json()
    assert body["approval_status"] == "approved"
    assert body["approved_at"] is not None


def test_staff_edit_resets_approval_to_pending(client, tokens):
    created = make_activity(client, name="กิจกรรมที่จะแก้ไข").json()
    client.patch(f"/activities/{created['id']}/approve", headers=_admin_headers(tokens))

    response = client.put(f"/activities/{created['id']}", json={"location": "ที่ใหม่"})
    assert response.status_code == 200
    assert response.json()["approval_status"] == "pending"


def test_rename_activity_saves_and_returns_to_pending(client, tokens):
    """เปลี่ยน "ชื่อกิจกรรม" ได้ (เช่น กิจกรรมเดิมที่จัดปีถัดไปแล้วเปลี่ยนชื่อ)
    — ชื่อใหม่ต้องบันทึกจริง และกิจกรรมกลับไป pending รออนุมัติใหม่ตามกติกาเดิม"""
    created = make_activity(client, name="ค่ายอาสาปี 2568").json()
    client.patch(f"/activities/{created['id']}/approve", headers=_admin_headers(tokens))

    response = client.put(f"/activities/{created['id']}", json={"name": "ค่ายอาสาปี 2569"})
    assert response.status_code == 200
    body = response.json()
    assert body["name"] == "ค่ายอาสาปี 2569"
    assert body["approval_status"] == "pending"
    assert body["approved_by"] is None
    assert body["approved_at"] is None

    # อ่านซ้ำจาก DB ไม่ใช่แค่ response ของ PUT
    assert client.get(f"/activities/{created['id']}").json()["name"] == "ค่ายอาสาปี 2569"


def test_rename_activity_via_full_form_payload(client):
    """ฟอร์มฝั่ง Flutter ส่งทุกฟิลด์กลับมาเสมอ (รวม start_at เดิม) เปลี่ยนแค่ชื่อ
    — เส้นทางนี้ต้องผ่าน ไม่ใช่ผ่านเฉพาะตอนส่ง {"name": ...} มาเดี่ยว ๆ"""
    created = make_activity(client, name="ชื่อเดิม").json()

    response = client.put(
        f"/activities/{created['id']}",
        json={
            "name": "ชื่อใหม่",
            "activity_type": created["activity_type"],
            "subcategory_id": created["subcategory_id"],
            "hours": created["hours"],
            "is_required": created["is_required"],
            "max_participants": created["max_participants"],
            "start_at": created["start_at"],
            "location": created["location"],
        },
    )
    assert response.status_code == 200
    assert response.json()["name"] == "ชื่อใหม่"


def test_rename_activity_keeps_checkin_token_and_participations(client):
    """เปลี่ยนชื่อแล้วต้องไม่กระทบ checkin_token (QR ที่ปริ๊นต์ไปแล้วยังใช้ได้)
    และผู้เข้าร่วมที่ลงไว้แล้วต้องยังผูกอยู่กับกิจกรรมเดิม"""
    created = make_activity(client, name="กิจกรรมมีคนสมัครแล้ว").json()
    token_before = client.get(f"/activities/{created['id']}/checkin-qr").json()["token"]
    student = make_student(client, student_id="6509001").json()
    participation = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": created["id"]}
    ).json()

    assert client.put(f"/activities/{created['id']}", json={"name": "ชื่อใหม่"}).status_code == 200

    qr = client.get(f"/activities/{created['id']}/checkin-qr").json()
    assert qr["token"] == token_before
    assert qr["activity_name"] == "ชื่อใหม่"  # QR ใบใหม่โชว์ชื่อใหม่ แต่ token เดิม

    parts = client.get(f"/activities/{created['id']}/participations").json()
    assert [p["id"] for p in parts] == [participation["id"]]


def test_activity_requires_hours(client):
    # A1: hours is mandatory and must be > 0
    payload = {
        "name": "กิจกรรมไม่มีชั่วโมง",
        "activity_type": "วิชาการ",
        "subcategory_id": 1,
        "is_required": False,
        "max_participants": 50,
        "start_at": future_start(),
        "location": "ห้อง SC101",
    }
    assert client.post("/activities", json=payload).status_code == 422
    assert client.post("/activities", json={**payload, "hours": 0}).status_code == 422


def test_activity_read_exposes_hours(client):
    created = make_activity(client, name="กิจกรรมมีชั่วโมง", hours=6).json()
    assert created["hours"] == 6
    assert client.get(f"/activities/{created['id']}").json()["hours"] == 6


def test_student_sees_only_approved_activities(client, tokens):
    make_activity(client, name="กิจกรรม pending")  # stays pending (staff-created)
    approved = make_activity(client, name="กิจกรรม approved").json()
    client.patch(f"/activities/{approved['id']}/approve", headers=_admin_headers(tokens))

    response = client.get("/activities", headers=_student_headers(tokens))
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "กิจกรรม approved"


def test_student_list_hides_pending_from_total_not_just_items(client, tokens):
    """`total` มาจาก count query คนละตัวกับ items — ถ้ากรองแค่ items จำนวนกิจกรรม
    ที่รออนุมัติจะรั่วออกไปทาง pagination ได้"""
    for i in range(3):
        make_activity(client, name=f"กิจกรรม pending {i}")
    approved = make_activity(client, name="กิจกรรม approved").json()
    client.patch(f"/activities/{approved['id']}/approve", headers=_admin_headers(tokens))

    body = client.get("/activities", headers=_student_headers(tokens)).json()
    assert body["total"] == 1
    assert len(body["items"]) == 1


def test_student_cannot_get_pending_activity_by_id(client, tokens):
    """การกรองในรายการอย่างเดียวไม่พอ — นิสิตที่เดา id ได้ต้องโดน 403 ด้วย"""
    pending = make_activity(client, name="กิจกรรมที่ยังไม่อนุมัติ").json()

    response = client.get(f"/activities/{pending['id']}", headers=_student_headers(tokens))
    assert response.status_code == 403

    client.patch(f"/activities/{pending['id']}/approve", headers=_admin_headers(tokens))
    assert client.get(f"/activities/{pending['id']}", headers=_student_headers(tokens)).status_code == 200


def test_student_filters_cannot_surface_pending_activity(client, tokens):
    """ตัวกรอง (search/type) ต้องทำงานบนชุดที่กรอง role แล้ว ไม่ใช่บนทั้งตาราง"""
    make_activity(client, name="ค่ายอาสาลับ", activity_type="จิตอาสา")  # pending

    student_headers = _student_headers(tokens)
    by_search = client.get("/activities", params={"search": "ค่ายอาสาลับ"}, headers=student_headers)
    assert by_search.json()["total"] == 0

    by_type = client.get("/activities", params={"activity_type": "จิตอาสา"}, headers=student_headers)
    assert by_type.json()["total"] == 0


def test_staff_and_admin_still_see_pending_activities(client, tokens):
    """กันการแก้เกินขอบเขต: การกรองต้องมีผลกับ role=student เท่านั้น"""
    pending = make_activity(client, name="กิจกรรมรออนุมัติของ staff").json()

    # staff เห็นของตัวเองทุกสถานะ (default client คือ staff)
    staff_items = client.get("/activities").json()["items"]
    assert any(item["id"] == pending["id"] for item in staff_items)
    assert client.get(f"/activities/{pending['id']}").status_code == 200

    # admin เห็นทุกกิจกรรมทุกสถานะ
    admin_body = client.get("/activities", headers=_admin_headers(tokens)).json()
    assert any(item["id"] == pending["id"] for item in admin_body["items"])
    assert any(item["approval_status"] == "pending" for item in admin_body["items"])
