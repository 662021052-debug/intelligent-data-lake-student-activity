"""Phase 14 — OCR validation pipeline + auto-approval (via /evidence/process).

OCR is injected as a fake through the get_ocr dependency override — the real
model is never called.
"""

from datetime import datetime

from sqlmodel import select

from app.main import app
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
from app.ocr import get_ocr

PNG = b"\x89PNG\r\n\x1a\nfake"


class FakeOcr:
    def __init__(self, text="", confidence=0.0):
        self.text = text
        self.confidence = confidence

    def run_ocr(self, image_bytes: bytes):
        return (self.text, self.confidence)


def _override_ocr(text, confidence):
    app.dependency_overrides[get_ocr] = lambda: FakeOcr(text, confidence)


def _admin_headers(tokens):
    return {"Authorization": f"Bearer {tokens['admin']}"}


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _admin_id(session):
    return session.exec(select(User).where(User.username == "admin")).first().id


def _student(session, code="77001", name="นายสมชาย ใจดี"):
    s = Student(
        student_id=code, full_name=name, faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    session.add(s)
    session.commit()
    session.refresh(s)
    return s


def _activity(session, owner, name="ค่ายอาสาพัฒนาชนบท", hours=4):
    a = Activity(
        name=name, activity_type="จิตอาสา", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=hours,
        created_by=owner, approval_status=ApprovalStatus.approved,
    )
    session.add(a)
    session.commit()
    session.refresh(a)
    return a


def _participation(session, student_id, activity_id, status=EvidenceStatus.pending):
    p = Participation(student_id=student_id, activity_id=activity_id,
                      evidence_status=status, hours_earned=0)
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _add_raw(session, storage, participation_id, checksum):
    key = f"evidence/test/p={participation_id}/{checksum[:8]}.png"
    storage.upload_object("bronze", key, PNG, "image/png")
    rf = RawFile(
        bucket="bronze", object_key=key, original_filename="e.png",
        content_type="image/png", size_bytes=len(PNG), checksum=checksum,
        source_system="student_upload", participation_id=participation_id,
    )
    session.add(rf)
    session.commit()
    session.refresh(rf)
    return rf


def _matching_text(student, activity):
    buddhist_year = activity.start_at.year + 543
    return f"เกียรติบัตร {student.full_name} เข้าร่วม {activity.name} วันที่ 1 ส.ค. {buddhist_year}"


# --------------------------- auto-approval ---------------------------
def test_matching_evidence_is_auto_approved(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="a1" + "0" * 62)

    _override_ocr(_matching_text(student, activity), 0.95)
    resp = client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["decision"] == "auto_approved"
    assert body["match_score"] >= 0.7
    assert body["ocr_confidence"] == 0.95

    updated = session.get(Participation, p.id)
    assert updated.evidence_status == EvidenceStatus.approved
    assert updated.hours_earned == activity.hours  # A2: hours from the activity


def test_low_confidence_stays_needs_review(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="a2" + "0" * 62)

    # text matches, but OCR confidence is below the auto threshold (0.6)
    _override_ocr(_matching_text(student, activity), 0.4)
    resp = client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))

    assert resp.status_code == 200
    assert resp.json()["decision"] == "needs_review"
    updated = session.get(Participation, p.id)
    assert updated.evidence_status == EvidenceStatus.pending
    assert updated.hours_earned == 0


def test_non_matching_evidence_needs_review(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="a3" + "0" * 62)

    _override_ocr("ข้อความอื่นที่ไม่เกี่ยวข้องเลย", 0.95)
    resp = client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))

    assert resp.status_code == 200
    body = resp.json()
    assert body["decision"] == "needs_review"
    assert body["match_score"] < 0.7
    updated = session.get(Participation, p.id)
    assert updated.evidence_status == EvidenceStatus.pending


def test_duplicate_file_is_flagged_not_approved(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))

    approved = _participation(session, student.id, activity.id, status=EvidenceStatus.approved)
    _add_raw(session, storage, approved.id, checksum="dup" + "0" * 61)

    target = _participation(session, student.id, activity.id)
    _add_raw(session, storage, target.id, checksum="dup" + "0" * 61)

    _override_ocr(_matching_text(student, activity), 0.99)  # would otherwise auto-approve
    resp = client.post(
        f"/participations/{target.id}/evidence/process", headers=_admin_headers(tokens)
    )

    assert resp.status_code == 200
    body = resp.json()
    assert body["decision"] == "flagged"
    assert body["is_duplicate"] is True
    # คนเดิมคนละการเข้าร่วม (ลงกิจกรรมเดิมซ้ำ) → same_student_reuse ชี้ใบที่อนุมัติแล้ว
    assert body["duplicate_reason"] == "same_student_reuse"
    assert body["duplicate_of_participation_id"] == approved.id
    updated = session.get(Participation, target.id)
    assert updated.evidence_status == EvidenceStatus.pending  # never auto-approved

    fetched = client.get(f"/participations/{target.id}/ocr", headers=_admin_headers(tokens)).json()
    assert fetched["duplicate_reason"] == "same_student_reuse"
    assert fetched["duplicate_of_participation_id"] == approved.id


def test_ocr_row_from_before_duplicate_columns_reads_as_null(client, session, storage, tokens):
    """แถว OCR เดิม (ก่อนเฟส 1.2) ไม่มีใบต้นทาง/เหตุผล — API ต้องคืน null ไม่ล้ม"""
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum="old" + "0" * 61)
    session.add(SilverEvidenceOcr(
        raw_file_id=raw.id, participation_id=p.id, extracted_text="ใบเก่า",
        ocr_confidence=0.7, match_score=0.6, decision=OcrDecision.flagged, is_duplicate=True,
    ))
    session.commit()

    resp = client.get(f"/participations/{p.id}/ocr", headers=_admin_headers(tokens))

    assert resp.status_code == 200, resp.text
    body = resp.json()
    assert body["is_duplicate"] is True
    assert body["duplicate_of_participation_id"] is None
    assert body["duplicate_reason"] is None


# --------------------------- access control ---------------------------
def test_staff_owner_can_process(client, session, storage):
    student = _student(session)
    activity = _activity(session, _staff_id(session))  # owned by default staff client
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="b1" + "0" * 62)

    _override_ocr(_matching_text(student, activity), 0.95)
    resp = client.post(f"/participations/{p.id}/evidence/process")  # default client = staff
    assert resp.status_code == 200
    assert resp.json()["decision"] == "auto_approved"


def test_staff_not_owner_cannot_process(client, session, storage):
    student = _student(session)
    activity = _activity(session, _admin_id(session))  # owned by admin, not the staff client
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="b2" + "0" * 62)

    _override_ocr(_matching_text(student, activity), 0.95)
    resp = client.post(f"/participations/{p.id}/evidence/process")
    assert resp.status_code == 403


def test_student_cannot_process(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="b3" + "0" * 62)

    student_headers = {"Authorization": f"Bearer {tokens['student']}"}
    resp = client.post(f"/participations/{p.id}/evidence/process", headers=student_headers)
    assert resp.status_code == 403


def test_process_without_evidence_returns_400(client, session, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)  # no raw_file

    resp = client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))
    assert resp.status_code == 400


# --------------------------- OCR result read ---------------------------
def test_get_ocr_result_after_processing(client, session, storage, tokens):
    student = _student(session)
    activity = _activity(session, _staff_id(session))
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="c1" + "0" * 62)

    # before processing -> 404
    assert client.get(f"/participations/{p.id}/ocr", headers=_admin_headers(tokens)).status_code == 404

    _override_ocr(_matching_text(student, activity), 0.95)
    client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))

    got = client.get(f"/participations/{p.id}/ocr", headers=_admin_headers(tokens))
    assert got.status_code == 200
    assert got.json()["decision"] == "auto_approved"


def test_participation_reads_fold_in_ocr_summary(client, session, storage, tokens):
    """After processing, both the participation detail and the activity
    participants list carry has_ocr / ocr_decision without an extra request."""
    student = _student(session)
    activity = _activity(session, _staff_id(session))  # owned by default staff client
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="e1" + "0" * 62)

    _override_ocr(_matching_text(student, activity), 0.95)
    client.post(f"/participations/{p.id}/evidence/process", headers=_admin_headers(tokens))

    detail = client.get(f"/participations/{p.id}", headers=_admin_headers(tokens)).json()
    assert detail["has_ocr"] is True
    assert detail["ocr_decision"] == "auto_approved"
    assert detail["ocr_match_score"] >= 0.7

    # activity participants list (default client = staff owner) — folded, no N+1
    listing = client.get(f"/activities/{activity.id}/participations").json()
    row = next(r for r in listing if r["id"] == p.id)
    assert row["has_ocr"] is True
    assert row["ocr_decision"] == "auto_approved"
    assert row["has_evidence"] is True  # also fixes the previously-unpopulated flag
    assert row["ocr_duplicate_reason"] is None


# --------------------- เฟส 1.3: บริบทของใบต้นทางเมื่อไฟล์ซ้ำ ---------------------
def _duplicate_pair(session, storage, original_owner, target_owner, checksum):
    """ใบต้นทางอนุมัติแล้ว (กิจกรรมของ original_owner) + เพื่อนส่งไฟล์เดียวกัน (กิจกรรมของ target_owner)"""
    owner = _student(session, code="77101", name="นางสาวต้นฉบับ ตัวจริง")
    original_activity = _activity(session, original_owner, name="ตลาดนัดผู้ประกอบการ")
    original = _participation(session, owner.id, original_activity.id, status=EvidenceStatus.approved)
    _add_raw(session, storage, original.id, checksum)
    borrower = _student(session, code="77102", name="นายยืมใบ เพื่อน")
    target_activity = _activity(session, target_owner, name="ค่ายอาสา")
    target = _participation(session, borrower.id, target_activity.id)
    _add_raw(session, storage, target.id, checksum)
    return original, target


def test_ocr_read_carries_original_context_for_admin(client, session, storage, tokens):
    original, target = _duplicate_pair(
        session, storage, _admin_id(session), _staff_id(session), "ctx1" + "0" * 60
    )
    _override_ocr("ใบของคนอื่น", 0.9)

    body = client.post(
        f"/participations/{target.id}/evidence/process", headers=_admin_headers(tokens)
    ).json()

    assert body["decision"] == "flagged"
    assert body["duplicate_reason"] == "cross_student"
    assert body["duplicate_of_participation_id"] == original.id
    assert body["duplicate_of_student_name"] == "นางสาวต้นฉบับ ตัวจริง"
    assert body["duplicate_of_student_code"] == "77101"
    assert body["duplicate_of_activity_name"] == "ตลาดนัดผู้ประกอบการ"
    assert body["duplicate_of_evidence_status"] == "approved"
    assert body["duplicate_of_viewable"] is True
    fetched = client.get(f"/participations/{target.id}/ocr", headers=_admin_headers(tokens)).json()
    assert fetched["duplicate_of_student_name"] == "นางสาวต้นฉบับ ตัวจริง"


def test_staff_sees_who_but_cannot_open_original_outside_own_activity(client, session, storage, tokens):
    """ต้นทางอยู่ในกิจกรรมของ admin: staff ที่ตรวจใบของตัวเองต้องรู้ว่าซ้ำกับใคร แต่ไม่มีลิงก์เปิด"""
    original, target = _duplicate_pair(
        session, storage, _admin_id(session), _staff_id(session), "ctx2" + "0" * 60
    )
    _override_ocr("ใบของคนอื่น", 0.9)
    client.post(f"/participations/{target.id}/evidence/process", headers=_admin_headers(tokens))

    body = client.get(f"/participations/{target.id}/ocr").json()  # default client = staff เจ้าของ target

    assert body["duplicate_of_student_name"] == "นางสาวต้นฉบับ ตัวจริง"
    assert body["duplicate_of_activity_name"] == "ตลาดนัดผู้ประกอบการ"
    assert body["duplicate_of_viewable"] is False
    assert client.get(f"/participations/{original.id}/ocr").status_code == 403


def test_staff_owning_both_activities_can_open_original(client, session, storage, tokens):
    _, target = _duplicate_pair(
        session, storage, _staff_id(session), _staff_id(session), "ctx3" + "0" * 60
    )
    _override_ocr("ใบของคนอื่น", 0.9)

    body = client.post(f"/participations/{target.id}/evidence/process").json()  # staff เจ้าของ

    assert body["duplicate_of_viewable"] is True


def test_student_role_gets_no_other_students_context(session, storage):
    """นิสิตเรียก GET .../ocr ของใบตัวเองได้ — ต้องไม่เห็นชื่อ/รหัสของนิสิตคนอื่น"""
    from app.models import UserRole
    from app.routers.participations import _ocr_read
    from app.silver import process_participation_evidence

    original, target = _duplicate_pair(
        session, storage, _staff_id(session), _staff_id(session), "ctx4" + "0" * 60
    )
    row = process_participation_evidence(session, FakeOcr("ใบของคนอื่น", 0.9), storage, target.id)

    read = _ocr_read(session, row, User(username="s", hashed_password="x", role=UserRole.student))

    assert read.duplicate_reason == "cross_student"
    assert read.duplicate_of_participation_id == original.id
    assert read.duplicate_of_student_name is None
    assert read.duplicate_of_student_code is None
    assert read.duplicate_of_activity_name is None
    assert read.duplicate_of_viewable is False


def test_participation_reads_carry_duplicate_reason_for_the_queue(client, session, storage, tokens):
    _, target = _duplicate_pair(
        session, storage, _staff_id(session), _staff_id(session), "ctx5" + "0" * 60
    )
    _override_ocr("ใบของคนอื่น", 0.9)
    client.post(f"/participations/{target.id}/evidence/process", headers=_admin_headers(tokens))

    detail = client.get(f"/participations/{target.id}", headers=_admin_headers(tokens)).json()
    queue = client.get(
        "/participations", params={"ocr_decision": "flagged", "has_evidence": "true"},
        headers=_admin_headers(tokens),
    ).json()["items"]

    assert detail["ocr_decision"] == "flagged"
    assert detail["ocr_duplicate_reason"] == "cross_student"
    assert [r["ocr_duplicate_reason"] for r in queue if r["id"] == target.id] == ["cross_student"]
