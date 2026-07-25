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
