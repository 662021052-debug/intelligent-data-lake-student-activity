from datetime import datetime


def _admin_headers(client):
    response = client.post("/auth/login", data={"username": "admin", "password": "admin123"})
    token = response.json()["access_token"]
    return {"Authorization": f"Bearer {token}"}


def make_student(
    client,
    student_id="6501001",
    full_name="ทดสอบ ระบบ",
    email=None,
    faculty="วิศวกรรมศาสตร์",
    year_level=2,
):
    payload = {
        "student_id": student_id,
        "full_name": full_name,
        "faculty": faculty,
        "major": "วิศวกรรมคอมพิวเตอร์",
        "year_level": year_level,
        "status": "active",
    }
    if email is not None:
        payload["email"] = email
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

def _make_student_with_account(
    client,
    student_id="6509001",
    full_name="นิสิต ใหม่",
    username=None,
    password=None,
    headers=None,
    extra=None,
):
    payload = {
        "student_id": student_id,
        "full_name": full_name,
        "faculty": "วิศวกรรมศาสตร์",
        "major": "วิศวกรรมคอมพิวเตอร์",
        "year_level": 1,
        "status": "active",
        "create_user": True,
    }
    if username is not None:
        payload["username"] = username
    if password is not None:
        payload["password"] = password
    if extra:
        payload.update(extra)
    return client.post(
        "/students", json=payload, headers=headers if headers is not None else _admin_headers(client)
    )


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


def test_response_reports_the_username_that_was_created(client):
    """ผู้ดูแลต้องรู้จากคำตอบเลยว่านิสิตจะล็อกอินด้วยชื่อผู้ใช้อะไร"""
    body = _make_student_with_account(client, student_id="6509010").json()
    assert body["username"] == "6509010"
    # ต้องไม่คืนรหัสผ่านหรือ hash กลับไปเด็ดขาด
    assert "password" not in body
    assert "hashed_password" not in body


def test_response_username_is_null_when_no_account_requested(client):
    assert make_student(client, student_id="6509011").json()["username"] is None


def test_custom_username_and_password_are_used(client):
    """กรอกเองได้ — ต้องล็อกอินด้วยค่าที่กรอก ไม่ใช่ค่าดีฟอลต์"""
    body = _make_student_with_account(
        client, student_id="6509012", username="somchai.j", password="secret-pw-1"
    ).json()
    assert body["username"] == "somchai.j"

    ok = client.post("/auth/login", data={"username": "somchai.j", "password": "secret-pw-1"})
    assert ok.status_code == 200

    # ค่าดีฟอลต์ต้องใช้ไม่ได้ เพราะถูกแทนที่ด้วยค่าที่กรอกไปแล้ว
    assert client.post(
        "/auth/login", data={"username": "6509012", "password": "6509012"}
    ).status_code == 401


def test_custom_username_still_links_to_the_new_student(client):
    student = _make_student_with_account(
        client, student_id="6509013", username="malee.k"
    ).json()
    users = client.get("/auth/users", params={"search": "malee.k"}, headers=_admin_headers(client))
    item = users.json()["items"][0]
    assert item["role"] == "student"
    assert item["student_id"] == student["id"]


def test_blank_username_and_password_fall_back_to_student_id(client):
    """ช่องว่าง ๆ ต้องถือว่า "ไม่ได้กรอก" ไม่ใช่สร้างบัญชีชื่อว่าง"""
    body = _make_student_with_account(
        client, student_id="6509014", username="   ", password=""
    ).json()
    assert body["username"] == "6509014"
    assert client.post(
        "/auth/login", data={"username": "6509014", "password": "6509014"}
    ).status_code == 200


def test_duplicate_custom_username_rolls_back_student_too(client):
    """ชื่อผู้ใช้ที่กรอกเองซ้ำ ก็ต้องไม่เหลือข้อมูลนิสิตค้างเหมือนกัน"""
    client.post(
        "/auth/register",
        json={"username": "taken.name", "password": "pw123456", "role": "staff"},
        headers=_admin_headers(client),
    )

    response = _make_student_with_account(
        client, student_id="6509015", username="taken.name"
    )
    assert response.status_code == 400
    assert "taken.name" in response.json()["detail"]

    found = client.get("/students", params={"search": "6509015"}, headers=_admin_headers(client))
    assert found.json()["total"] == 0


def test_extra_fields_are_rejected(client):
    """ยัดฟิลด์ที่ระบบเป็นเจ้าของต้องถูกปฏิเสธ ไม่ใช่ถูกกลืนเงียบ ๆ"""
    response = _make_student_with_account(
        client, student_id="6509016", extra={"hashed_password": "ปลอม"}
    )
    assert response.status_code == 422

    # และต้องไม่เหลืออะไรค้างจากคำขอที่ถูกปฏิเสธ
    found = client.get("/students", params={"search": "6509016"}, headers=_admin_headers(client))
    assert found.json()["total"] == 0


def test_role_cannot_be_escalated_through_the_form(client):
    """กันไม่ให้กรอก role มาเองเพื่อสร้างบัญชี admin"""
    response = _make_student_with_account(
        client, student_id="6509017", extra={"role": "admin"}
    )
    assert response.status_code == 422


def test_staff_cannot_create_student_with_account(client):
    """เจ้าหน้าที่สร้างบัญชีนิสิตทางลัดนี้ไม่ได้ (client ดีฟอลต์ล็อกอินเป็น staff)"""
    response = _make_student_with_account(client, student_id="6509018", headers={})
    assert response.status_code == 403

    found = client.get("/students", params={"search": "6509018"}, headers=_admin_headers(client))
    assert found.json()["total"] == 0


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


# ---- ตัวกรองคณะ / ชั้นปี และรายชื่อคณะ ----

def _filter_world(client):
    """นิสิต 4 คน คร่อมสองคณะ สองชั้นปี — พอให้แยกได้ว่าตัวกรองไหนทำงาน"""
    make_student(client, student_id="6503001", full_name="เอ วิศวะ", faculty="คณะวิศวกรรมศาสตร์", year_level=1)
    make_student(client, student_id="6503002", full_name="บี วิศวะ", faculty="คณะวิศวกรรมศาสตร์", year_level=4)
    make_student(client, student_id="6503003", full_name="ซี นิติ", faculty="คณะนิติศาสตร์", year_level=1)
    make_student(client, student_id="6503004", full_name="ดี นิติ", faculty="คณะนิติศาสตร์", year_level=4)


def test_faculties_lists_each_faculty_once_sorted(client):
    _filter_world(client)
    # คณะซ้ำต้องไม่โผล่สองครั้ง
    make_student(client, student_id="6503005", full_name="อี วิศวะ", faculty="คณะวิศวกรรมศาสตร์")

    response = client.get("/faculties")

    assert response.status_code == 200
    assert response.json() == ["คณะนิติศาสตร์", "คณะวิศวกรรมศาสตร์"]


def test_faculties_requires_login(client):
    """รายชื่อคณะไม่ใช่ข้อมูลสาธารณะ — ต้องล็อกอินก่อนเหมือน endpoint อื่น"""
    assert client.get("/faculties", headers={"Authorization": "Bearer not-a-token"}).status_code == 401


def test_filter_students_by_faculty(client):
    _filter_world(client)

    body = client.get("/students", params={"faculty": "คณะนิติศาสตร์"}).json()

    assert body["total"] == 2
    assert {s["full_name"] for s in body["items"]} == {"ซี นิติ", "ดี นิติ"}


def test_filter_students_by_year_level(client):
    _filter_world(client)

    body = client.get("/students", params={"year_level": 4}).json()

    assert body["total"] == 2
    assert {s["full_name"] for s in body["items"]} == {"บี วิศวะ", "ดี นิติ"}


def test_filters_combine_with_each_other_and_with_search(client):
    _filter_world(client)

    both = client.get(
        "/students", params={"faculty": "คณะวิศวกรรมศาสตร์", "year_level": 1}
    ).json()
    assert both["total"] == 1
    assert both["items"][0]["full_name"] == "เอ วิศวะ"

    with_search = client.get(
        "/students",
        params={"faculty": "คณะนิติศาสตร์", "year_level": 1, "search": "ซี"},
    ).json()
    assert with_search["total"] == 1
    assert with_search["items"][0]["full_name"] == "ซี นิติ"

    # ตัวกรองที่ขัดกันเองต้องได้ศูนย์ ไม่ใช่เงียบ ๆ แล้วคืนทั้งหมด
    contradictory = client.get(
        "/students", params={"faculty": "คณะนิติศาสตร์", "search": "วิศวะ"}
    ).json()
    assert contradictory["total"] == 0
    assert contradictory["items"] == []


def test_total_counts_after_filtering_not_the_whole_table(client):
    """total ต้องเป็นยอดหลังกรอง ไม่งั้นแถบแบ่งหน้าจะพาไปหน้าที่ไม่มีข้อมูล"""
    _filter_world(client)

    body = client.get(
        "/students", params={"faculty": "คณะวิศวกรรมศาสตร์", "limit": 1}
    ).json()

    assert body["total"] == 2       # ไม่ใช่ 4
    assert len(body["items"]) == 1  # จำกัดหน้าละ 1


def test_year_level_out_of_range_is_rejected(client):
    assert client.get("/students", params={"year_level": 0}).status_code == 422
    assert client.get("/students", params={"year_level": 99}).status_code == 422


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


# ---- อีเมลนิสิต: ไม่บังคับ แต่ถ้ากรอกต้องถูกรูปแบบ ----

def test_create_student_without_an_email_is_allowed(client):
    """ปล่อยว่างได้ — ไม่ใช่ทุกคนที่มีอีเมลตั้งแต่วันแรก และระบบไม่เดาให้"""
    response = make_student(client, student_id="6502001")

    assert response.status_code == 201
    assert response.json()["email"] is None


def test_email_can_be_filled_in_later(client):
    created = make_student(client, student_id="6502002").json()
    assert created["email"] is None

    response = client.put(
        f"/students/{created['id']}",
        json={"email": "6502002@tsu.ac.th"},
        headers=_admin_headers(client),
    )

    assert response.status_code == 200
    assert response.json()["email"] == "6502002@tsu.ac.th"
    # อ่านซ้ำต้องยังอยู่ ไม่ใช่ค้างอยู่แค่ใน response ของ PUT
    assert client.get(f"/students/{created['id']}").json()["email"] == "6502002@tsu.ac.th"


def test_email_can_be_cleared_back_to_empty(client):
    created = make_student(client, student_id="6502003", email="6502003@tsu.ac.th").json()
    assert created["email"] == "6502003@tsu.ac.th"

    # ฟอร์มส่งสตริงว่างมาเมื่อผู้ดูแลล้างช่องทิ้ง ต้องกลายเป็น "ยังไม่ระบุ" ไม่ใช่ค่าว่าง
    response = client.put(
        f"/students/{created['id']}", json={"email": ""}, headers=_admin_headers(client)
    )

    assert response.status_code == 200
    assert response.json()["email"] is None


def test_malformed_email_is_rejected_on_create(client):
    for bad in ["ไม่ใช่อีเมล", "somchai@", "@tsu.ac.th", "somchai tsu.ac.th", "a b@tsu.ac.th"]:
        response = make_student(client, student_id="6502009", email=bad)
        assert response.status_code == 422, f"ต้องปฏิเสธ {bad!r}"


def test_malformed_email_is_rejected_on_update(client):
    created = make_student(client, student_id="6502004").json()

    response = client.put(
        f"/students/{created['id']}",
        json={"email": "somchai.tsu.ac.th"},
        headers=_admin_headers(client),
    )

    assert response.status_code == 422
    assert client.get(f"/students/{created['id']}").json()["email"] is None


def test_email_is_trimmed_before_saving(client):
    response = make_student(client, student_id="6502005", email="  6502005@tsu.ac.th  ")

    assert response.status_code == 201
    assert response.json()["email"] == "6502005@tsu.ac.th"


def test_updating_other_fields_leaves_the_email_alone(client):
    created = make_student(client, student_id="6502006", email="6502006@tsu.ac.th").json()

    response = client.put(
        f"/students/{created['id']}", json={"year_level": 3}, headers=_admin_headers(client)
    )

    assert response.status_code == 200
    assert response.json()["email"] == "6502006@tsu.ac.th"


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


# ---- ลบนิสิตแล้วต้องไม่เหลือบัญชีกำพร้า ----

def test_delete_student_also_deletes_the_linked_account(client):
    """ลบนิสิตแล้วบัญชีที่ผูกไว้ต้องหายไปด้วย ไม่ใช่ค้างให้ล็อกอินได้ต่อ"""
    created = _make_student_with_account(client, student_id="6509020").json()
    headers = _admin_headers(client)

    # ก่อนลบ: ล็อกอินได้
    assert client.post(
        "/auth/login", data={"username": "6509020", "password": "6509020"}
    ).status_code == 200

    assert client.delete(f"/students/{created['id']}", headers=headers).status_code == 204

    # หลังลบ: ไม่มีบัญชีเหลือ และล็อกอินไม่ได้อีก
    users = client.get("/auth/users", params={"search": "6509020"}, headers=headers)
    assert users.json()["total"] == 0
    assert client.post(
        "/auth/login", data={"username": "6509020", "password": "6509020"}
    ).status_code == 401


def test_delete_student_removes_account_created_with_custom_username(client):
    """บัญชีที่ตั้งชื่อเองก็ต้องถูกลบตาม เพราะผูกด้วย student_id ไม่ใช่ชื่อ"""
    created = _make_student_with_account(
        client, student_id="6509021", username="orphan.check"
    ).json()
    headers = _admin_headers(client)

    assert client.delete(f"/students/{created['id']}", headers=headers).status_code == 204

    users = client.get("/auth/users", params={"search": "orphan.check"}, headers=headers)
    assert users.json()["total"] == 0


def test_delete_student_without_account_still_works(client):
    """ไม่มีบัญชีผูกอยู่ก็ต้องลบได้ตามปกติ ไม่ใช่พังเพราะหาไม่เจอ"""
    created = make_student(client, student_id="6509022").json()
    headers = _admin_headers(client)
    assert client.delete(f"/students/{created['id']}", headers=headers).status_code == 204
    assert client.get(f"/students/{created['id']}").status_code == 404


def test_delete_student_keeps_other_students_accounts(client):
    """ต้องลบเฉพาะบัญชีของนิสิตคนที่ถูกลบ ไม่กวาดคนอื่นไปด้วย"""
    victim = _make_student_with_account(client, student_id="6509023").json()
    _make_student_with_account(client, student_id="6509024")
    headers = _admin_headers(client)

    assert client.delete(f"/students/{victim['id']}", headers=headers).status_code == 204

    survivors = client.get("/auth/users", params={"search": "6509024"}, headers=headers)
    assert survivors.json()["total"] == 1
    assert client.post(
        "/auth/login", data={"username": "6509024", "password": "6509024"}
    ).status_code == 200


def test_delete_student_with_history_is_blocked(client, session, tokens):
    """นิสิตที่เคยเข้าร่วมกิจกรรมลบไม่ได้ — ลบทิ้งจะพา lineage หายไปด้วย"""
    from app.models import Activity, ApprovalStatus, Participation

    created = _make_student_with_account(client, student_id="6509030").json()
    activity = Activity(
        name="อบรมความปลอดภัย",
        activity_type="อบรม",
        max_participants=30,
        start_at=datetime(2026, 6, 1, 9, 0),
        location="หอประชุม",
        hours=3,
        approval_status=ApprovalStatus.approved,
    )
    session.add(activity)
    session.commit()
    session.add(Participation(student_id=created["id"], activity_id=activity.id))
    session.commit()

    headers = _admin_headers(client)
    response = client.delete(f"/students/{created['id']}", headers=headers)
    assert response.status_code == 400
    assert response.json()["detail"] == "ลบไม่ได้: นิสิตมีประวัติเข้าร่วม 1 รายการ"

    # ห้ามลบอะไรทิ้งไปแล้วค่อยเด้ง — ทั้งนิสิต บัญชี และประวัติต้องอยู่ครบ
    assert client.get(f"/students/{created['id']}", headers=headers).status_code == 200
    users = client.get("/auth/users", params={"search": "6509030"}, headers=headers)
    assert users.json()["total"] == 1
    assert client.post(
        "/auth/login", data={"username": "6509030", "password": "6509030"}
    ).status_code == 200


def test_delete_student_error_reports_the_real_number_of_records(client, session):
    """ข้อความต้องบอกจำนวนจริง ผู้ดูแลจะได้รู้ว่ากำลังจะทำลายอะไรไปบ้าง"""
    from app.models import Activity, ApprovalStatus, Participation

    created = _make_student_with_account(client, student_id="6509031").json()
    for index in range(3):
        activity = Activity(
            name=f"กิจกรรมที่ {index}",
            activity_type="อบรม",
            max_participants=30,
            start_at=datetime(2026, 6, 1, 9, 0),
            location="หอประชุม",
            hours=3,
            approval_status=ApprovalStatus.approved,
        )
        session.add(activity)
        session.commit()
        session.add(Participation(student_id=created["id"], activity_id=activity.id))
    session.commit()

    response = client.delete(f"/students/{created['id']}", headers=_admin_headers(client))
    assert response.status_code == 400
    assert response.json()["detail"] == "ลบไม่ได้: นิสิตมีประวัติเข้าร่วม 3 รายการ"


def test_delete_student_unlinks_staff_account_instead_of_deleting_it(client, session):
    """บัญชีที่ไม่ใช่ role=student ต้องถูกปลดการผูก ไม่ใช่ถูกลบทิ้ง

    API ปกติสร้างสถานะนี้ไม่ได้ (staff/admin ถูกบังคับให้ student_id เป็น None
    เสมอ) จึงต้องยัดผ่าน session ตรง ๆ เพื่อทดสอบด่านสุดท้าย
    """
    from app.auth import hash_password
    from app.models import User, UserRole

    created = make_student(client, student_id="6509025").json()
    session.add(
        User(
            username="staff.linked",
            hashed_password=hash_password("pw123456"),
            role=UserRole.staff,
            student_id=created["id"],
        )
    )
    session.commit()

    headers = _admin_headers(client)
    assert client.delete(f"/students/{created['id']}", headers=headers).status_code == 204

    users = client.get("/auth/users", params={"search": "staff.linked"}, headers=headers)
    items = users.json()["items"]
    assert len(items) == 1, "บัญชีเจ้าหน้าที่ต้องยังอยู่"
    assert items[0]["student_id"] is None, "แต่ต้องไม่ผูกกับนิสิตที่ถูกลบแล้ว"
    assert client.post(
        "/auth/login", data={"username": "staff.linked", "password": "pw123456"}
    ).status_code == 200


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
