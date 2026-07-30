from fastapi.testclient import TestClient

from app.main import app

STUDENT_PAYLOAD = {
    "student_id": "AUTH001",
    "full_name": "ทดสอบ สิทธิ์",
    "faculty": "วิศวกรรมศาสตร์",
    "major": "วิศวกรรมคอมพิวเตอร์",
    "year_level": 1,
    "status": "active",
}


def test_login_success_returns_jwt(client):
    response = client.post("/auth/login", data={"username": "staff", "password": "staff123"})
    assert response.status_code == 200
    body = response.json()
    assert body["token_type"] == "bearer"
    assert len(body["access_token"]) > 20


def test_login_wrong_password_rejected(client):
    response = client.post("/auth/login", data={"username": "staff", "password": "wrong"})
    assert response.status_code == 401


def test_register_requires_admin_role(client):
    # default `client` fixture is authenticated as staff, not admin
    response = client.post(
        "/auth/register", json={"username": "newuser", "password": "pw123456", "role": "staff"}
    )
    assert response.status_code == 403


def test_register_as_admin_succeeds(client, tokens):
    response = client.post(
        "/auth/register",
        json={"username": "newuser2", "password": "pw123456", "role": "staff"},
        headers={"Authorization": f"Bearer {tokens['admin']}"},
    )
    assert response.status_code == 201
    assert response.json()["username"] == "newuser2"


def test_register_duplicate_username_rejected(client, tokens):
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    client.post(
        "/auth/register", json={"username": "dupe", "password": "pw123456", "role": "staff"}, headers=headers
    )
    response = client.post(
        "/auth/register", json={"username": "dupe", "password": "pw123456", "role": "staff"}, headers=headers
    )
    assert response.status_code == 400


def test_student_can_read_but_not_write(client, tokens):
    headers = {"Authorization": f"Bearer {tokens['student']}"}

    read_response = client.get("/students", headers=headers)
    assert read_response.status_code == 200

    write_response = client.post("/students", json=STUDENT_PAYLOAD, headers=headers)
    assert write_response.status_code == 403


def test_admin_can_write_students(client, tokens):
    # student master data is admin-only (staff coverage is in tests/test_students.py)
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    response = client.post("/students", json=STUDENT_PAYLOAD, headers=headers)
    assert response.status_code == 201


def test_unauthenticated_request_rejected(client):
    anon_client = TestClient(app)
    response = anon_client.get("/students")
    assert response.status_code == 401


def test_unauthenticated_write_rejected(client):
    anon_client = TestClient(app)
    response = anon_client.post("/students", json=STUDENT_PAYLOAD)
    assert response.status_code == 401


def test_list_users_requires_admin(client):
    # default `client` fixture is authenticated as staff, not admin
    response = client.get("/auth/users")
    assert response.status_code == 403


def test_list_users_as_admin_succeeds(client, tokens):
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    response = client.get("/auth/users", headers=headers)
    assert response.status_code == 200
    body = response.json()
    assert body["total"] >= 3
    usernames = {u["username"] for u in body["items"]}
    assert {"admin", "staff", "student"} <= usernames


def test_search_users_by_username(client, tokens):
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    body = client.get("/auth/users", params={"search": "adm"}, headers=headers).json()
    assert [u["username"] for u in body["items"]] == ["admin"]
    assert body["total"] == 1  # total ต้องนับเฉพาะผลที่ค้นเจอ ไม่ใช่ผู้ใช้ทั้งหมด

    assert client.get(
        "/auth/users", params={"search": "ไม่มีผู้ใช้ชื่อนี้"}, headers=headers
    ).json()["total"] == 0
