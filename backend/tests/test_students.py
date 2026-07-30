def _admin_headers(client):
    response = client.post("/auth/login", data={"username": "admin", "password": "admin123"})
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def make_student(client, student_id="6501001", full_name="ทดสอบ ระบบ"):
    payload = {
        "student_id": student_id,
        "full_name": full_name,
        "faculty": "วิศวกรรมศาสตร์",
        "major": "วิศวกรรมคอมพิวเตอร์",
        "year_level": 2,
        "status": "active",
    }
    # student master data is admin-only to create, regardless of which role is
    # logged in as the test's default `client`
    return client.post("/students", json=payload, headers=_admin_headers(client))


def test_create_and_get_student(client):
    response = make_student(client)
    assert response.status_code == 201
    body = response.json()
    assert body["student_id"] == "6501001"
    assert "id" in body

    get_response = client.get(f"/students/{body['id']}")
    assert get_response.status_code == 200
    assert get_response.json()["full_name"] == "ทดสอบ ระบบ"


def test_create_duplicate_student_id_rejected(client):
    make_student(client, student_id="6501002")
    response = make_student(client, student_id="6501002")
    assert response.status_code == 400


def test_list_students_with_pagination_and_filter(client):
    make_student(client, student_id="6501010", full_name="เอ บี")
    make_student(client, student_id="6501011", full_name="ซี ดี")

    response = client.get("/students", params={"skip": 0, "limit": 1})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 2
    assert len(body["items"]) == 1

    filtered = client.get("/students", params={"search": "เอ บี"})
    assert filtered.status_code == 200
    assert filtered.json()["total"] == 1


def test_update_student(client):
    created = make_student(client, student_id="6501020").json()
    response = client.put(
        f"/students/{created['id']}",
        json={"year_level": 4, "status": "inactive"},
        headers=_admin_headers(client),
    )
    assert response.status_code == 200
    body = response.json()
    assert body["year_level"] == 4
    assert body["status"] == "inactive"
    assert body["full_name"] == created["full_name"]


def test_list_students_order_is_stable_after_status_change(client):
    """สลับสถานะไป-กลับต้องไม่ทำให้ลำดับในรายการเปลี่ยน (ต้องเรียงตามรหัสนิสิตเสมอ)."""
    # สร้างสลับปีเข้าศึกษาไปมา เพื่อให้ลำดับ insert ไม่ตรงกับลำดับรหัส
    for code in ("6801001", "6501001", "6701001", "6601001"):
        assert make_student(client, student_id=code).status_code == 201

    expected = ["6501001", "6601001", "6701001", "6801001"]

    def codes():
        return [s["student_id"] for s in client.get("/students").json()["items"]]

    assert codes() == expected

    target = client.get("/students", params={"search": "6601001"}).json()["items"][0]
    headers = _admin_headers(client)
    assert client.put(
        f"/students/{target['id']}", json={"status": "inactive"}, headers=headers
    ).status_code == 200
    assert codes() == expected

    assert client.put(
        f"/students/{target['id']}", json={"status": "active"}, headers=headers
    ).status_code == 200
    assert codes() == expected


def test_delete_student(client, tokens):
    created = make_student(client, student_id="6501030").json()
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    response = client.delete(f"/students/{created['id']}", headers=headers)
    assert response.status_code == 204

    get_response = client.get(f"/students/{created['id']}")
    assert get_response.status_code == 404


def test_staff_cannot_create_student(client):
    # default `client` fixture is authenticated as staff
    payload = {
        "student_id": "6501099",
        "full_name": "พนักงานพยายามสร้าง",
        "faculty": "วิศวกรรมศาสตร์",
        "major": "วิศวกรรมคอมพิวเตอร์",
        "year_level": 1,
        "status": "active",
    }
    response = client.post("/students", json=payload)
    assert response.status_code == 403


def test_staff_cannot_update_student(client):
    created = make_student(client, student_id="6501032").json()
    # default `client` fixture is authenticated as staff
    response = client.put(f"/students/{created['id']}", json={"year_level": 3})
    assert response.status_code == 403


def test_staff_cannot_delete_student(client):
    # default `client` fixture is authenticated as staff
    created = make_student(client, student_id="6501031").json()
    response = client.delete(f"/students/{created['id']}")
    assert response.status_code == 403


def test_get_nonexistent_student_returns_404(client):
    response = client.get("/students/9999")
    assert response.status_code == 404
