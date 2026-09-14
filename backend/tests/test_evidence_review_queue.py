"""คิวตรวจหลักฐาน — ตัวกรอง has_evidence / ocr_decision และชื่อนิสิตในรายการ"""

from datetime import datetime

from sqlmodel import select

from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
    StudentStatus,
    User,
)


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).one().id


def _world(session):
    staff_id = _staff_id(session)
    activity = Activity(
        name="ค่ายอาสา", activity_type="จิตอาสา", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9), location="ห้อง", hours=4,
        created_by=staff_id, approval_status=ApprovalStatus.approved,
    )
    session.add(activity)
    students = [
        Student(
            student_id=f"6900000{i}", full_name=f"นิสิตคนที่ {i}", faculty="ทดสอบ",
            major="ทดสอบ", year_level=1, status=StudentStatus.active,
        )
        for i in range(4)
    ]
    session.add_all(students)
    session.commit()
    participations = [
        Participation(student_id=s.id, activity_id=activity.id, evidence_status=EvidenceStatus.pending)
        for s in students
    ]
    session.add_all(participations)
    session.commit()
    return activity, students, participations


def _add_file(session, participation, checksum):
    raw_file = RawFile(
        bucket="bronze", object_key=f"k/{checksum}", original_filename="e.png",
        content_type="image/png", size_bytes=1, checksum=checksum,
        source_system="student_upload", participation_id=participation.id,
    )
    session.add(raw_file)
    session.commit()
    return raw_file


def _add_ocr(session, participation, raw_file, decision):
    session.add(
        SilverEvidenceOcr(
            raw_file_id=raw_file.id, participation_id=participation.id, decision=decision,
            is_duplicate=decision == OcrDecision.flagged,
        )
    )
    session.commit()


def _ids(response):
    assert response.status_code == 200, response.text
    return {item["id"] for item in response.json()["items"]}


def test_has_evidence_filter(client, session):
    _, _, (with_file, _, without_file, _) = _world(session)
    _add_file(session, with_file, "a" * 64)

    assert _ids(client.get("/participations", params={"has_evidence": "true"})) == {with_file.id}
    no_file = _ids(client.get("/participations", params={"has_evidence": "false"}))
    assert with_file.id not in no_file and without_file.id in no_file
    body = client.get("/participations", params={"has_evidence": "true"}).json()
    assert body["total"] == 1


def test_ocr_decision_filter_uses_latest_result_only(client, session):
    _, _, (reread, flagged, auto, _) = _world(session)
    for p, checksum in ((reread, "a"), (flagged, "b"), (auto, "c")):
        _add_file(session, p, checksum * 64)
    raw = {r.participation_id: r for r in session.exec(select(RawFile)).all()}
    # ผลแรกเป็น flagged แล้วสั่งอ่านใหม่ได้ needs_review → ต้องนับเป็น needs_review อย่างเดียว
    _add_ocr(session, reread, raw[reread.id], OcrDecision.flagged)
    _add_ocr(session, reread, raw[reread.id], OcrDecision.needs_review)
    _add_ocr(session, flagged, raw[flagged.id], OcrDecision.flagged)
    _add_ocr(session, auto, raw[auto.id], OcrDecision.auto_approved)

    assert _ids(client.get("/participations", params={"ocr_decision": "flagged"})) == {flagged.id}
    assert _ids(client.get("/participations", params={"ocr_decision": "needs_review"})) == {reread.id}
    assert _ids(
        client.get("/participations", params={"ocr_decision": "auto_approved", "has_evidence": "true"})
    ) == {auto.id}


def test_reads_carry_student_name_and_code(client, session):
    _, students, (first, *_) = _world(session)
    items = client.get("/participations").json()["items"]
    row = next(item for item in items if item["id"] == first.id)
    assert row["student_name"] == students[0].full_name
    assert row["student_code"] == students[0].student_id

    single = client.get(f"/participations/{first.id}").json()
    assert single["student_name"] == students[0].full_name


def test_staff_scope_still_applies_with_filters(client, session, tokens):
    _, _, (p, *_) = _world(session)
    _add_file(session, p, "d" * 64)
    other_staff = User(username="staff2", hashed_password="x", role="staff")
    session.add(other_staff)
    session.commit()
    # ผู้ดูแล (admin) เห็นทุกกิจกรรม เจ้าหน้าที่เจ้าของกิจกรรมก็เห็น
    admin = {"Authorization": f"Bearer {tokens['admin']}"}
    assert p.id in _ids(client.get("/participations", params={"has_evidence": "true"}, headers=admin))
    assert p.id in _ids(client.get("/participations", params={"has_evidence": "true"}))
