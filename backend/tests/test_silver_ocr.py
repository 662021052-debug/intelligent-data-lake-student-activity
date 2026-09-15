"""Phase 13 — Silver layer OCR foundation tests.

OCR is always mocked (a fake engine) — never call the real EasyOCR model in
tests. Verifies the pipeline persists a complete `silver_evidence_ocr` row.
"""

from datetime import datetime

from app.models import (
    Activity,
    DuplicateReason,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    Student,
    StudentStatus,
)
from app.silver import DuplicateMatch, find_duplicate, process_participation_evidence

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


# ---------------- เฟส 1.1: เทียบกับทุกใบที่ใช้งาน + แยกประเภทซ้ำ ----------------

SAME = "same" + "0" * 60


def test_two_pending_students_same_file_flags_only_the_later_one(session, storage):
    activity = _activity(session)
    first = _participation(session, _student(session, "88101").id, activity.id)
    first_raw = _add_raw(session, storage, first.id, checksum=SAME)
    later = _participation(session, _student(session, "88102").id, activity.id)
    later_raw = _add_raw(session, storage, later.id, checksum=SAME)

    ocr = FakeOcr(text="ใบเดียวกัน", confidence=0.9)
    first_row = process_participation_evidence(session, ocr, storage, first.id)
    later_row = process_participation_evidence(session, ocr, storage, later.id)

    assert first_row.decision == OcrDecision.needs_review and first_row.is_duplicate is False
    assert later_row.decision == OcrDecision.flagged and later_row.is_duplicate is True
    assert find_duplicate(session, later_raw) == DuplicateMatch(
        DuplicateReason.cross_student, first.id, first_raw.id
    )
    assert find_duplicate(session, first_raw) is None, "ใบแรกต้องไม่โดน ไม่ว่าจะอ่านใหม่กี่รอบ"
    # อ่านใหม่ใบแรกหลังใบหลังถูก flag แล้ว ผลต้องเหมือนเดิม
    assert process_participation_evidence(session, ocr, storage, first.id).is_duplicate is False


def test_same_student_reusing_file_for_another_activity(session, storage):
    student = _student(session)
    camp = _participation(session, student.id, _activity(session, "ค่ายอาสา").id,
                          status=EvidenceStatus.approved)
    camp_raw = _add_raw(session, storage, camp.id, checksum=SAME)
    talk = _participation(session, student.id, _activity(session, "อบรมดิจิทัล").id)
    talk_raw = _add_raw(session, storage, talk.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.9), storage, talk.id)

    assert row.decision == OcrDecision.flagged
    assert find_duplicate(session, talk_raw) == DuplicateMatch(
        DuplicateReason.same_student_reuse, camp.id, camp_raw.id
    )


def test_reuploading_the_same_file_to_the_same_participation_is_not_flagged(session, storage):
    p = _participation(session, _student(session).id, _activity(session).id)
    _add_raw(session, storage, p.id, checksum=SAME)
    again = _add_raw(session, storage, p.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.9), storage, p.id)

    assert find_duplicate(session, again) is None
    assert row.is_duplicate is False and row.decision == OcrDecision.needs_review


def test_file_matching_only_a_rejected_proof_is_matches_rejected(session, storage):
    activity = _activity(session)
    rejected = _participation(session, _student(session, "88201").id, activity.id,
                              status=EvidenceStatus.rejected)
    rejected_raw = _add_raw(session, storage, rejected.id, checksum=SAME)
    p = _participation(session, _student(session, "88202").id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.95), storage, p.id)

    assert find_duplicate(session, raw) == DuplicateMatch(
        DuplicateReason.matches_rejected, rejected.id, rejected_raw.id
    )
    assert row.decision == OcrDecision.flagged and row.is_duplicate is True


def test_active_match_wins_over_rejected_match(session, storage):
    """ตรงทั้งใบที่เคยถูกปฏิเสธ (มาก่อน) และใบที่ยังใช้งาน → เหตุผลของใบที่ใช้งานชนะ"""
    activity = _activity(session)
    rejected = _participation(session, _student(session, "88211").id, activity.id,
                              status=EvidenceStatus.rejected)
    _add_raw(session, storage, rejected.id, checksum=SAME)          # id น้อยสุด
    friend = _participation(session, _student(session, "88212").id, activity.id)
    friend_raw = _add_raw(session, storage, friend.id, checksum=SAME)
    p = _participation(session, _student(session, "88213").id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum=SAME)

    assert find_duplicate(session, raw) == DuplicateMatch(
        DuplicateReason.cross_student, friend.id, friend_raw.id
    )


def test_same_student_reuse_wins_over_rejected_match(session, storage):
    activity = _activity(session, "ค่ายอาสา")
    other_rejected = _participation(session, _student(session, "88221").id, activity.id,
                                    status=EvidenceStatus.rejected)
    _add_raw(session, storage, other_rejected.id, checksum=SAME)
    me = _student(session, "88222")
    mine = _participation(session, me.id, activity.id, status=EvidenceStatus.approved)
    mine_raw = _add_raw(session, storage, mine.id, checksum=SAME)
    again = _participation(session, me.id, _activity(session, "อบรมดิจิทัล").id)
    raw = _add_raw(session, storage, again.id, checksum=SAME)

    assert find_duplicate(session, raw) == DuplicateMatch(
        DuplicateReason.same_student_reuse, mine.id, mine_raw.id
    )


def test_unique_file_is_not_a_duplicate(session, storage):
    activity = _activity(session)
    other = _participation(session, _student(session, "88301").id, activity.id)
    _add_raw(session, storage, other.id, checksum="u1" + "0" * 62)
    p = _participation(session, _student(session, "88302").id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum="u2" + "0" * 62)

    assert find_duplicate(session, raw) is None


def test_cross_student_wins_over_same_student_reuse(session, storage):
    me = _student(session, "88401")
    mine = _participation(session, me.id, _activity(session, "ค่ายอาสา").id)
    _add_raw(session, storage, mine.id, checksum=SAME)             # ใบแรกสุดเป็นของตัวเอง
    friend = _participation(session, _student(session, "88402").id, _activity(session, "ค่ายอาสา").id)
    friend_raw = _add_raw(session, storage, friend.id, checksum=SAME)
    now = _participation(session, me.id, _activity(session, "อบรมดิจิทัล").id)
    now_raw = _add_raw(session, storage, now.id, checksum=SAME)

    match = find_duplicate(session, now_raw)

    assert match == DuplicateMatch(DuplicateReason.cross_student, friend.id, friend_raw.id)


def test_demo_shape_approved_original_then_friend_pending_is_cross_student(session, storage):
    """รูปแบบของ seed demo 4 กลุ่มเดิม: ใบเจ้าของอนุมัติแล้ว (id น้อยกว่า) → เพื่อนส่งไฟล์เดียวกัน"""
    activity = _activity(session)
    owner = _participation(session, _student(session, "88501").id, activity.id,
                           status=EvidenceStatus.approved)
    owner_raw = _add_raw(session, storage, owner.id, checksum=SAME)
    borrower = _participation(session, _student(session, "88502").id, activity.id)
    borrower_raw = _add_raw(session, storage, borrower.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.95), storage, borrower.id)

    assert row.decision == OcrDecision.flagged and row.is_duplicate is True
    assert find_duplicate(session, borrower_raw) == DuplicateMatch(
        DuplicateReason.cross_student, owner.id, owner_raw.id
    )
