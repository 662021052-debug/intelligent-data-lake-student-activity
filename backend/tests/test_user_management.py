"""Group D — admin user management (create linked to student, edit/delete)."""
from tests.test_students import make_student


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _admin_id(client, tokens):
    users = client.get("/auth/users", headers=_admin_headers(tokens)).json()["items"]
    return next(u["id"] for u in users if u["username"] == "admin")


# ---- D1: บัญชีนิสิตสร้างได้ทางเดียวคือฟอร์มเพิ่มนิสิต ----
#
# เดิม endpoint นี้สร้าง role=student แบบยังไม่ผูก (student_id=null) ได้ แล้วค่อย
# ผูกทีหลัง ผลคือมีบัญชีที่ล็อกอินได้แต่ใช้อะไรไม่ได้เลย ตอนนี้ปิดทางนั้นทั้งหมด

_STUDENT_FORM_MESSAGE = "การสร้างบัญชีนิสิตต้องใช้ฟอร์มเพิ่มนิสิต (กรอกข้อมูลนิสิตให้ครบ)"


def test_register_rejects_student_role_and_points_to_the_student_form(client, tokens):
    response = client.post(
        "/auth/register",
        json={"username": "loner", "password": "pw123456", "role": "student"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400
    assert response.json()["detail"] == _STUDENT_FORM_MESSAGE
    # ต้องไม่แอบสร้างบัญชีทิ้งไว้
    users = client.get("/auth/users", params={"search": "loner"}, headers=_admin_headers(tokens))
    assert users.json()["total"] == 0


def test_register_rejects_student_role_even_with_a_valid_student_id(client, tokens):
    """แม้ส่ง student_id ที่มีอยู่จริงมาด้วยก็ยังต้องไปใช้ฟอร์มเพิ่มนิสิต"""
    student = make_student(client, student_id="770100101").json()
    response = client.post(
        "/auth/register",
        json={
            "username": "linked_new",
            "password": "pw123456",
            "role": "student",
            "student_id": student["id"],
        },
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400
    assert response.json()["detail"] == _STUDENT_FORM_MESSAGE


def test_register_still_creates_staff_and_admin(client, tokens):
    for username, role in (("new_staff", "staff"), ("new_admin", "admin")):
        response = client.post(
            "/auth/register",
            json={"username": username, "password": "pw123456", "role": role},
            headers=_admin_headers(tokens),
        )
        assert response.status_code == 201, response.text
        body = response.json()
        assert body["role"] == role
        # staff/admin ไม่เคยผูกกับข้อมูลนิสิต
        assert body["student_id"] is None


def test_register_ignores_student_id_sent_for_staff(client, tokens):
    """ส่ง student_id มากับ role=staff ต้องไม่ทำให้เกิดการผูกที่ไม่ควรมี"""
    student = make_student(client, student_id="770100102").json()
    created = client.post(
        "/auth/register",
        json={
            "username": "staff_with_link",
            "password": "pw123456",
            "role": "staff",
            "student_id": student["id"],
        },
        headers=_admin_headers(tokens),
    ).json()
    assert created["student_id"] is None


def test_student_account_from_the_student_form_is_always_linked(client, tokens):
    """ทางที่เหลืออยู่ทางเดียวต้องได้บัญชีที่ผูกครบเสมอ"""
    from tests.test_students import _make_student_with_account

    student = _make_student_with_account(client, student_id="770100103").json()
    users = client.get(
        "/auth/users", params={"search": "770100103"}, headers=_admin_headers(tokens)
    ).json()["items"]
    assert len(users) == 1
    assert users[0]["role"] == "student"
    assert users[0]["student_id"] == student["id"]


def test_no_api_path_creates_a_student_account_without_a_link(client, tokens):
    """เกณฑ์ว่าเสร็จข้อสำคัญ: ต้องไม่มีทางได้ user role=student ที่ student_id เป็น null"""
    from tests.test_students import _make_student_with_account

    # ไล่ทุกทางที่สร้าง/แก้บัญชีได้
    client.post(
        "/auth/register",
        json={"username": "try_student", "password": "pw123456", "role": "student"},
        headers=_admin_headers(tokens),
    )
    _make_student_with_account(client, student_id="770100104")
    promoted = client.post(
        "/auth/register",
        json={"username": "try_promote", "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    ).json()
    client.put(
        f"/auth/users/{promoted['id']}",
        json={"role": "student"},
        headers=_admin_headers(tokens),
    )

    everyone = client.get(
        "/auth/users", params={"limit": 200}, headers=_admin_headers(tokens)
    ).json()["items"]
    unlinked = [
        u for u in everyone if u["role"] == "student" and u["student_id"] is None
        # บัญชี "student" ของ conftest ถูกยัดผ่าน session ตรง ๆ ไม่ได้ผ่าน API
        and u["username"] != "student"
    ]
    assert unlinked == []


# ---- D2: edit / delete, admin-only, no self-delete ----

def test_staff_cannot_manage_users(client, tokens):
    # default client is staff
    assert client.put("/auth/users/1", json={"role": "admin"}).status_code == 403
    assert client.delete("/auth/users/1").status_code == 403


def test_admin_cannot_delete_self(client, tokens):
    admin_id = _admin_id(client, tokens)
    response = client.delete(f"/auth/users/{admin_id}", headers=_admin_headers(tokens))
    assert response.status_code == 400


def test_admin_can_change_role_and_reset_password(client, tokens):
    client.post(
        "/auth/register",
        json={"username": "promote_me", "password": "oldpass1", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    users = client.get("/auth/users", headers=_admin_headers(tokens)).json()["items"]
    uid = next(u["id"] for u in users if u["username"] == "promote_me")

    response = client.put(
        f"/auth/users/{uid}",
        json={"role": "admin", "password": "newpass1"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 200
    assert response.json()["role"] == "admin"
    # old password no longer works, new one does
    assert client.post("/auth/login", data={"username": "promote_me", "password": "oldpass1"}).status_code == 401
    assert client.post("/auth/login", data={"username": "promote_me", "password": "newpass1"}).status_code == 200


def test_update_cannot_relink_a_student_account(client, tokens):
    """ปิดทางเปลี่ยน "นิสิตที่ผูกบัญชี" ผ่านหน้าจัดการผู้ใช้ — ผูกได้ที่เดียวคือตอนสร้างนิสิต"""
    from tests.test_students import _make_student_with_account

    _make_student_with_account(client, student_id="770110101")
    other = make_student(client, student_id="770110102").json()
    account = client.get(
        "/auth/users", params={"search": "770110101"}, headers=_admin_headers(tokens)
    ).json()["items"][0]

    response = client.put(
        f"/auth/users/{account['id']}",
        json={"student_id": other["id"]},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 422, "student_id ไม่ใช่ฟิลด์ที่แก้ได้อีกแล้ว"

    # การผูกเดิมต้องไม่ถูกแตะ
    after = client.get(
        "/auth/users", params={"search": "770110101"}, headers=_admin_headers(tokens)
    ).json()["items"][0]
    assert after["student_id"] == account["student_id"]


def test_update_cannot_promote_a_staff_account_to_student(client, tokens):
    created = client.post(
        "/auth/register",
        json={"username": "wannabe_student", "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    ).json()

    response = client.put(
        f"/auth/users/{created['id']}",
        json={"role": "student"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400
    assert response.json()["detail"] == _STUDENT_FORM_MESSAGE


def test_update_can_still_reset_a_student_password_without_touching_the_link(client, tokens):
    """บัญชีนิสิตที่มีอยู่ต้องรีเซ็ตรหัสผ่านได้ และการผูกต้องอยู่ครบเหมือนเดิม"""
    from tests.test_students import _make_student_with_account

    _make_student_with_account(client, student_id="770110103")
    account = client.get(
        "/auth/users", params={"search": "770110103"}, headers=_admin_headers(tokens)
    ).json()["items"][0]

    response = client.put(
        f"/auth/users/{account['id']}",
        json={"password": "brand-new-pw"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 200
    assert response.json()["student_id"] == account["student_id"]
    assert response.json()["role"] == "student"

    assert client.post(
        "/auth/login", data={"username": "770110103", "password": "brand-new-pw"}
    ).status_code == 200


def test_users_list_paginates_without_hitting_the_limit_cap(client, tokens):
    """หน้าจัดการผู้ใช้ต้องแบ่งหน้าได้ ไม่ใช่ขอทั้งหมดทีเดียวจนชนเพดาน limit"""
    for i in range(5):
        client.post(
            "/auth/register",
            json={"username": f"paged{i}", "password": "pw123456", "role": "staff"},
            headers=_admin_headers(tokens),
        )

    first_page = client.get(
        "/auth/users", params={"skip": 0, "limit": 2}, headers=_admin_headers(tokens)
    ).json()
    second_page = client.get(
        "/auth/users", params={"skip": 2, "limit": 2}, headers=_admin_headers(tokens)
    ).json()

    # total คือจำนวนทั้งหมด ไม่ใช่จำนวนในหน้านี้ — แถบ "1-2 จาก N" ต้องอาศัยค่านี้
    assert first_page["total"] == second_page["total"] >= 7
    assert len(first_page["items"]) == 2
    assert len(second_page["items"]) == 2
    first_ids = [u["id"] for u in first_page["items"]]
    second_ids = [u["id"] for u in second_page["items"]]
    assert set(first_ids).isdisjoint(second_ids), "หน้าถัดไปต้องไม่ซ้ำกับหน้าก่อน"
    # เรียงตาม id คงที่ แถวจึงไม่ย้ายที่ระหว่างเปลี่ยนหน้า
    assert first_ids + second_ids == sorted(first_ids + second_ids)


def test_users_limit_above_cap_is_rejected(client, tokens):
    """frontend เคยส่ง limit=500 แล้วได้ 422 — ยืนยันว่าเพดานยังอยู่ที่ 200"""
    response = client.get(
        "/auth/users", params={"limit": 500}, headers=_admin_headers(tokens)
    )
    assert response.status_code == 422


def test_admin_can_delete_other_user(client, tokens):
    client.post(
        "/auth/register",
        json={"username": "deleteme", "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    users = client.get("/auth/users", headers=_admin_headers(tokens)).json()["items"]
    uid = next(u["id"] for u in users if u["username"] == "deleteme")

    response = client.delete(f"/auth/users/{uid}", headers=_admin_headers(tokens))
    assert response.status_code == 204
    users_after = client.get("/auth/users", headers=_admin_headers(tokens)).json()["items"]
    assert all(u["username"] != "deleteme" for u in users_after)
