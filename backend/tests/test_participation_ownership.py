from tests.test_students import make_student


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _register_staff(client, tokens, username):
    client.post(
        "/auth/register",
        json={"username": username, "password": "pw123456", "role": "staff"},
        headers=_admin_headers(tokens),
    )
    login_response = client.post("/auth/login", data={"username": username, "password": "pw123456"})
    return {"Authorization": f"Bearer {login_response.json()['access_token']}"}


def _make_activity(client, name="กิจกรรมของ owner", headers=None):
    payload = {
        "name": name,
        "activity_type": "วิชาการ",
        "hour_category": "เลือกเสรี",
        "is_required": False,
        "max_participants": 50,
        "start_at": "2026-08-01T09:00:00",
        "location": "ห้อง SC101",
    }
    return client.post("/activities", json=payload, headers=headers).json()


def test_staff_can_review_evidence_for_own_activity(client):
    # default `client` fixture is authenticated as staff, and owns the activity it creates
    student = make_student(client, student_id="7001001").json()
    activity = _make_activity(client)
    participation = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    response = client.put(
        f"/participations/{participation['id']}",
        json={"evidence_status": "approved", "hours_earned": 4},
    )
    assert response.status_code == 200
    assert response.json()["evidence_status"] == "approved"


def test_staff_cannot_review_evidence_for_others_activity(client, tokens):
    student = make_student(client, student_id="7001002").json()
    activity = _make_activity(client)  # owned by default staff
    participation = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    other_staff_headers = _register_staff(client, tokens, "reviewer2")
    response = client.put(
        f"/participations/{participation['id']}",
        json={"evidence_status": "approved"},
        headers=other_staff_headers,
    )
    assert response.status_code == 403


def test_staff_cannot_create_participation_for_others_activity(client, tokens):
    student = make_student(client, student_id="7001003").json()
    activity = _make_activity(client)  # owned by default staff
    other_staff_headers = _register_staff(client, tokens, "creator2")

    response = client.post(
        "/participations",
        json={"student_id": student["id"], "activity_id": activity["id"]},
        headers=other_staff_headers,
    )
    assert response.status_code == 403


def test_staff_cannot_delete_participation_for_others_activity(client, tokens):
    student = make_student(client, student_id="7001004").json()
    activity = _make_activity(client)
    participation = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    other_staff_headers = _register_staff(client, tokens, "deleter2")
    response = client.delete(f"/participations/{participation['id']}", headers=other_staff_headers)
    assert response.status_code == 403


def test_staff_list_participations_scoped_to_own_activities(client, tokens):
    student = make_student(client, student_id="7001005").json()
    own_activity = _make_activity(client, name="กิจกรรมของ staff เอง")
    client.post("/participations", json={"student_id": student["id"], "activity_id": own_activity["id"]})

    other_staff_headers = _register_staff(client, tokens, "lister2")
    other_activity = _make_activity(client, name="กิจกรรมของ staff คนอื่น", headers=other_staff_headers)
    client.post(
        "/participations",
        json={"student_id": student["id"], "activity_id": other_activity["id"]},
        headers=other_staff_headers,
    )

    response = client.get("/participations")  # default client = original staff
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["activity_id"] == own_activity["id"]


def test_admin_can_review_any_participation(client, tokens):
    student = make_student(client, student_id="7001006").json()
    activity = _make_activity(client)
    participation = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    response = client.put(
        f"/participations/{participation['id']}",
        json={"evidence_status": "approved"},
        headers=_admin_headers(tokens),
    )
    assert response.status_code == 200


def test_activity_participations_endpoint_scoped_by_ownership(client, tokens):
    student = make_student(client, student_id="7001007").json()
    activity = _make_activity(client)
    client.post("/participations", json={"student_id": student["id"], "activity_id": activity["id"]})

    own_response = client.get(f"/activities/{activity['id']}/participations")
    assert own_response.status_code == 200
    assert len(own_response.json()) == 1

    other_staff_headers = _register_staff(client, tokens, "viewer2")
    other_response = client.get(
        f"/activities/{activity['id']}/participations", headers=other_staff_headers
    )
    assert other_response.status_code == 403

    admin_response = client.get(
        f"/activities/{activity['id']}/participations", headers=_admin_headers(tokens)
    )
    assert admin_response.status_code == 200
    assert len(admin_response.json()) == 1
