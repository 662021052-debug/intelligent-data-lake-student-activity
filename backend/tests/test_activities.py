def make_activity(client, name="กิจกรรมทดสอบ", activity_type="วิชาการ"):
    payload = {
        "name": name,
        "activity_type": activity_type,
        "hour_category": "เลือกเสรี",
        "is_required": False,
        "max_participants": 50,
        "start_at": "2026-08-01T09:00:00",
        "location": "ห้อง SC101",
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


def test_get_nonexistent_activity_returns_404(client):
    response = client.get("/activities/9999")
    assert response.status_code == 404


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


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
            "hour_category": "เลือกเสรี",
            "is_required": False,
            "max_participants": 50,
            "start_at": "2026-08-01T09:00:00",
            "location": "ห้อง SC101",
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


def test_student_sees_only_approved_activities(client, tokens):
    make_activity(client, name="กิจกรรม pending")  # stays pending (staff-created)
    approved = make_activity(client, name="กิจกรรม approved").json()
    client.patch(f"/activities/{approved['id']}/approve", headers=_admin_headers(tokens))

    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    response = client.get("/activities", headers=student_headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["name"] == "กิจกรรม approved"
