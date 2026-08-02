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


# ---- สร้างนิสิต + บัญชีเข้าใช้งานพร้อมกันในขั้นเดียว ----

def _make_student_with_account(client, student_id="6509001", full_name="นิสิต ใหม่"):
    payload = {
        "student_id": student_id,
        "full_name": full_name,
        "faculty": "วิศวกรรมศาสตร์",
        "major": "วิศวกรรมคอมพิวเตอร์",
        "year_level": 1,
        "status": "active",
        "create_user": True,
    }
    return client.post("/students", json=payload, headers=_admin_headers(client))


def test_create_student_with_account_creates_both(client):
    response = _make_student_with_account(client, student_id="6509001")
    assert response.status_code == 201
    student = response.json()

    users = client.get("/auth/users", params={"search": "6509001"}, headers=_admin_headers(client))
    items = users.json()["items"]
    assert len(items) == 1
    assert items[0]["username"] == "6509001"
    assert items[0]["role"] == "student"
    assert items[0]["student_id"] == student["id"]


def test_new_student_can_login_with_student_id_and_see_own_data(client):
    """นิสิตใหม่ต้องล็อกอินด้วยรหัสนิสิตได้ทันที ไม่ต้องรอผู้ดูแลไปสร้างบัญชีอีกหน้า"""
    created = _make_student_with_account(client, student_id="6509002", full_name="สมชาย ใจดี").json()

    login = client.post("/auth/login", data={"username": "6509002", "password": "6509002"})
    assert login.status_code == 200
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}

    listing = client.get("/students", headers=headers).json()
    assert listing["total"] == 1
    assert listing["items"][0]["id"] == created["id"]
    assert listing["items"][0]["full_name"] == "สมชาย ใจดี"

    # ผูกบัญชีแล้วจึงต้องเรียก endpoint แบบ /me ได้ ไม่ติด 403
    assert client.get("/students/me/hours-summary", headers=headers).status_code == 200


def test_duplicate_username_rolls_back_student_too(client):
    """ถ้าชื่อผู้ใช้ซ้ำ ต้องไม่เหลือข้อมูลนิสิตค้างไว้ให้ตามลบ"""
    # มีบัญชีชื่อ 6509003 อยู่ก่อนแล้ว แต่ยังไม่มีข้อมูลนิสิตรหัสนี้
    client.post(
        "/auth/register",
        json={"username": "6509003", "password": "pw123456", "role": "staff"},
        headers=_admin_headers(client),
    )

    response = _make_student_with_account(client, student_id="6509003")
    assert response.status_code == 400
    assert "6509003" in response.json()["detail"]

    # ต้องไม่มีข้อมูลนิสิตค้าง
    found = client.get("/students", params={"search": "6509003"}, headers=_admin_headers(client))
    assert found.json()["total"] == 0


def test_duplicate_student_id_creates_no_user(client):
    """รหัสนิสิตซ้ำต้องหยุดตั้งแต่ต้น ไม่แอบสร้างบัญชีทิ้งไว้"""
    _make_student_with_account(client, student_id="6509004")
    before = client.get("/auth/users", headers=_admin_headers(client)).json()["total"]

    response = _make_student_with_account(client, student_id="6509004")
    assert response.status_code == 400
    assert response.json()["detail"] == "รหัสนิสิตนี้มีอยู่ในระบบแล้ว"

    after = client.get("/auth/users", headers=_admin_headers(client)).json()["total"]
    assert after == before


def test_create_student_without_account_stays_the_default(client):
    """ผู้เรียกเดิมที่ไม่ได้ขอบัญชี ต้องไม่ได้บัญชีเพิ่มมาเงียบ ๆ"""
    make_student(client, student_id="6509005")
    users = client.get("/auth/users", params={"search": "6509005"}, headers=_admin_headers(client))
    assert users.json()["total"] == 0


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
