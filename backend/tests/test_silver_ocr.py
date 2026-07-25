"""Phase 13 — Silver layer OCR foundation tests.

OCR is always mocked (a fake engine) — never call the real EasyOCR model in
tests. Verifies the pipeline persists a complete `silver_evidence_ocr` row.
"""

from datetime import datetime

from app.models import (
    Activity,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    Student,
    StudentStatus,
)
from app.silver import process_participation_evidence

PNG = b"\x89PNG\r\n\x1a\nfake-bytes"


class FakeOcr:
    """Deterministic stand-in for the OCR engine."""

    def __init__(self, text="", confidence=0.0, fail=False):
        self.text = text
        self.confidence = confidence
        self.fail = fail
        self.calls = 0

    def run_ocr(self, image_bytes: bytes):
        self.calls += 1
        if self.fail:
            raise RuntimeError("OCR should not have been called")
        return (self.text, self.confidence)


def _student(session, code="88001"):
    s = Student(
        student_id=code,
        full_name="นายสมชาย ใจดี",
        faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์",
        year_level=2,
        status=StudentStatus.active,
    )
    session.add(s)
    session.commit()
    session.refresh(s)
    return s


def _activity(session, name="ค่ายอาสา"):
    a = Activity(
        name=name,
        activity_type="จิตอาสา",
        is_required=False,
        max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0),
        location="ห้อง",
        hours=4,
    )
    session.add(a)
    session.commit()
    session.refresh(a)
    return a


def _participation(session, student_id, activity_id, status=EvidenceStatus.pending):
    p = Participation(
        student_id=student_id,
        activity_id=activity_id,
        evidence_status=status,
        hours_earned=0,
    )
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _add_raw(session, storage, participation_id, checksum="a" * 64, content_type="image/png"):
    key = f"evidence/test/p={participation_id}/{checksum[:8]}.png"
    storage.upload_object("bronze", key, PNG, content_type)
    rf = RawFile(
        bucket="bronze",
        object_key=key,
        original_filename="evidence.png",
        content_type=content_type,
        size_bytes=len(PNG),
        checksum=checksum,
        source_system="student_upload",
        participation_id=participation_id,
    )
    session.add(rf)
    session.commit()
    session.refresh(rf)
    return rf


def test_process_creates_silver_row_with_all_fields(session, storage):
    student = _student(session)
    activity = _activity(session)
    p = _participation(session, student.id, activity.id)
    rf = _add_raw(session, storage, p.id, checksum="1" * 64)

    # Text that does NOT mention the student/activity -> low match -> needs_review
    # (auto-approval on matching text is covered in test_silver_pipeline.py).
    ocr = FakeOcr(text="เอกสารทั่วไป ไม่มีข้อมูลที่ตรงกับกิจกรรม", confidence=0.92)
    row = process_participation_evidence(session, ocr, storage, p.id)

    assert ocr.calls == 1
    assert row is not None
    assert row.raw_file_id == rf.id
    assert row.participation_id == p.id
    assert row.extracted_text == "เอกสารทั่วไป ไม่มีข้อมูลที่ตรงกับกิจกรรม"
    assert row.ocr_confidence == 0.92
    assert row.match_score < 0.7             # unrelated text -> no match
    assert row.decision == OcrDecision.needs_review
    assert row.is_duplicate is False
    assert isinstance(row.processed_at, datetime)


def test_process_without_evidence_returns_none(session, storage):
    student = _student(session)
    activity = _activity(session)
    p = _participation(session, student.id, activity.id)  # no raw_file

    ocr = FakeOcr(text="x", confidence=0.9)
    assert process_participation_evidence(session, ocr, storage, p.id) is None
    assert ocr.calls == 0


def test_non_image_skips_ocr(session, storage):
    student = _student(session)
    activity = _activity(session)
    p = _participation(session, student.id, activity.id)
    _add_raw(session, storage, p.id, checksum="2" * 64, content_type="application/pdf")

    ocr = FakeOcr(fail=True)  # would raise if called
    row = process_participation_evidence(session, ocr, storage, p.id)

    assert ocr.calls == 0                    # PDFs are not OCR'd in this phase
    assert row.extracted_text == ""
    assert row.ocr_confidence == 0.0
    assert row.decision == OcrDecision.needs_review


def test_duplicate_checksum_is_flagged(session, storage):
    student = _student(session)
    activity = _activity(session)

    # An earlier APPROVED participation already owns this exact file (checksum).
    approved = _participation(session, student.id, activity.id, status=EvidenceStatus.approved)
    _add_raw(session, storage, approved.id, checksum="dup" + "0" * 61)

    # A new participation uploads the same file.
    other = _participation(session, student.id, activity.id)
    _add_raw(session, storage, other.id, checksum="dup" + "0" * 61)

    ocr = FakeOcr(text="ก็อปมา", confidence=0.95)
    row = process_participation_evidence(session, ocr, storage, other.id)

    assert row.is_duplicate is True
    assert row.decision == OcrDecision.flagged
