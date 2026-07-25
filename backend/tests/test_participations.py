from tests.test_activities import make_activity
from tests.test_students import make_student


def test_create_participation(client):
    student = make_student(client, student_id="6502001").json()
    activity = make_activity(client, name="กิจกรรมร่วม").json()

    payload = {"student_id": student["id"], "activity_id": activity["id"]}
    response = client.post("/participations", json=payload)
    assert response.status_code == 201
    body = response.json()
    assert body["student_id"] == student["id"]
    assert body["activity_id"] == activity["id"]
    assert body["hours_earned"] == 0  # A2: system-controlled, starts at 0


def test_create_participation_rejects_injected_hours(client):
    # A2: a caller may not seed hours_earned / evidence_status
    student = make_student(client, student_id="6502009").json()
    activity = make_activity(client, name="กิจกรรมกันยัด").json()
    response = client.post(
        "/participations",
        json={"student_id": student["id"], "activity_id": activity["id"], "hours_earned": 99},
    )
    assert response.status_code == 422


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


def test_filter_participations_by_student_and_status(client, add_evidence):
    student = make_student(client, student_id="6502003").json()
    activity_a = make_activity(client, name="กิจกรรม A").json()
    activity_b = make_activity(client, name="กิจกรรม B").json()

    p_a = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity_a["id"]}
    ).json()
    client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity_b["id"]}
    )
    add_evidence(p_a["id"])
    client.put(f"/participations/{p_a['id']}", json={"evidence_status": "approved"})

    response = client.get("/participations", params={"student_id": student["id"], "evidence_status": "approved"})
    assert response.status_code == 200
    body = response.json()
    assert body["total"] == 1
    assert body["items"][0]["activity_id"] == activity_a["id"]


def test_update_and_delete_participation(client, add_evidence):
    student = make_student(client, student_id="6502004").json()
    activity = make_activity(client, name="กิจกรรม C", hours=5).json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    add_evidence(created["id"])
    update_response = client.put(
        f"/participations/{created['id']}", json={"evidence_status": "approved"}
    )
    assert update_response.status_code == 200
    body = update_response.json()
    assert body["evidence_status"] == "approved"
    assert body["hours_earned"] == 5  # A2: derived from activity.hours

    delete_response = client.delete(f"/participations/{created['id']}")
    assert delete_response.status_code == 204

    get_response = client.get(f"/participations/{created['id']}")
    assert get_response.status_code == 404


def test_cannot_approve_without_evidence(client):
    # A3: approving a participation with no Bronze evidence is rejected
    student = make_student(client, student_id="6502005").json()
    activity = make_activity(client, name="กิจกรรมไม่มีหลักฐาน").json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    response = client.put(f"/participations/{created['id']}", json={"evidence_status": "approved"})
    assert response.status_code == 400
    # still not approved, still 0 hours
    assert client.get(f"/participations/{created['id']}").json()["evidence_status"] == "pending"


def test_approve_then_reject_zeroes_hours(client, add_evidence):
    student = make_student(client, student_id="6502006").json()
    activity = make_activity(client, name="กิจกรรมอนุมัติแล้วถอน", hours=4).json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()
    add_evidence(created["id"])

    approved = client.put(f"/participations/{created['id']}", json={"evidence_status": "approved"})
    assert approved.json()["hours_earned"] == 4
    rejected = client.put(f"/participations/{created['id']}", json={"evidence_status": "rejected"})
    assert rejected.json()["hours_earned"] == 0  # E4


def test_cannot_repoint_student_or_activity(client, add_evidence):
    # A4: student_id / activity_id are locked on an existing participation
    student = make_student(client, student_id="6502007").json()
    activity = make_activity(client, name="กิจกรรมล็อกความสัมพันธ์").json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()

    assert client.put(f"/participations/{created['id']}", json={"student_id": 9999}).status_code == 422
    assert client.put(f"/participations/{created['id']}", json={"activity_id": 9999}).status_code == 422


def test_participation_read_includes_activity_name(client):
    # E1: read carries the activity name so the UI never shows "#id"
    student = make_student(client, student_id="6502008").json()
    activity = make_activity(client, name="ชื่อกิจกรรมโชว์ผล").json()
    created = client.post(
        "/participations", json={"student_id": student["id"], "activity_id": activity["id"]}
    ).json()
    assert created["activity_name"] == "ชื่อกิจกรรมโชว์ผล"
