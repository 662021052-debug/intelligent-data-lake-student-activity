"""Group D — admin user management (create linked to student, edit/delete)."""
from tests.test_students import make_student


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _admin_id(client, tokens):
    users = client.get("/auth/users", headers=_admin_headers(tokens)).json()["items"]
    return next(u["id"] for u in users if u["username"] == "admin")


# ---- D1: student accounts must be linked to a student ----

def test_create_student_user_without_student_id_rejected(client, tokens):
    response = client.post(
        "/auth/register",
        json={"username": "loner", "password": "pw123456", "role": "student"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400


def test_create_student_user_with_invalid_student_id_rejected(client, tokens):
    response = client.post(
        "/auth/register",
        json={"username": "ghost", "password": "pw123456", "role": "student", "student_id": 99999},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 400


def test_create_linked_student_user_can_see_own_data(client, tokens):
    student = make_student(client, student_id="7701001").json()
    created = client.post(
        "/auth/register",
        json={
            "username": "linked_new",
            "password": "pw123456",
            "role": "student",
            "student_id": student["id"],
        },
        headers=_admin_headers(tokens),
    )
    assert created.status_code == 201
    assert created.json()["student_id"] == student["id"]

    login = client.post("/auth/login", data={"username": "linked_new", "password": "pw123456"})
    headers = {"Authorization": f"Bearer {login.json()['access_token']}"}
    listing = client.get("/students", headers=headers).json()
    assert listing["total"] == 1
    assert listing["items"][0]["id"] == student["id"]


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


def test_admin_can_relink_student_user_to_another_student(client, tokens):
    """หน้าจัดการผู้ใช้ต้องเปลี่ยน "นิสิตที่ผูกบัญชี" ได้จริง"""
    first = make_student(client, student_id="7701101").json()
    second = make_student(client, student_id="7701102").json()
    created = client.post(
        "/auth/register",
        json={
            "username": "relink_me",
            "password": "pw123456",
            "role": "student",
            "student_id": first["id"],
        },
        headers=_admin_headers(tokens),
    ).json()

    response = client.put(
        f"/auth/users/{created['id']}",
        json={"role": "student", "student_id": second["id"]},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 200
    assert response.json()["student_id"] == second["id"]


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
