from tests.test_activities import make_activity
from tests.test_students import make_student


def test_create_participation(client):
    student = make_student(client, student_id="6502001").json()
    activity = make_activity(client, name="กิจกรรมร่วม").json()

    payload = {
        "student_id": student["id"],
        "activity_id": activity["id"],
        "hours_earned": 3.0,
        "evidence_status": "pending",
    }
    response = client.post("/participations", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["student_id"] == student["id"]
    assert body["activity_id"] == activity["id"]


def test_create_participation_with_invalid_student_rejected(client):
    activity = make_activity(client).json()
    payload = {"student_id": 9999, "activity_id": activity["id"]}
    response = client.post("/participations", json=payload)
    assert response.status_code == 400


def test_create_participation_with_invalid_activity_rejected(client):
    student = make_student(client, student_id="6502002").json()
    payload = {"student_id": student["id"], "activity_id": 9999}
    response = client.post("/participations", json=payload)
    assert response.status_code == 400


def test_filter_participations_by_student_and_status(client):
    student = make_student(client, student_id="6502003").json()
    activity_a = make_activity(client, name="กิจกรรม A").json()
    activity_b = make_activity(client, name="กิจกรรม B").json()

    client.post(
        "/participations",
        json={"student_id": student["id"], "activity_id": activity_a["id"], "evidence_status": "approved"},
    )
    client.post(
        "/participations",
        json={"student_id": student["id"], "activity_id": activity_b["id"], "evidence_status": "pending"},
    )

    response = client.get("/participations", params={"student_id": student["id"], "evidence_status": "approved"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["activity_id"] == activity_a["id"]


def test_update_and_delete_participation(client):
    student = make_student(client, student_id="6502004").json()
    activity = make_activity(client, name="กิจกรรม C").json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    update_response = client.put(
        f"/participations/{created['id']}", json={"evidence_status": "approved", "hours_earned": 5.5}
    )
    assert update_response.status_code == 200
    body = update_response.json()
    assert body["evidence_status"] == "approved"
    assert body["hours_earned"] == 5.5

    delete_response = client.delete(f"/participations/{created['id']}")
    assert delete_response.status_code == 204

    get_response = client.get(f"/participations/{created['id']}")
    assert get_response.status_code == 404
