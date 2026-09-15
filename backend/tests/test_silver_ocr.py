"""Phase 13 — Silver layer OCR foundation tests.

OCR is always mocked (a fake engine) — never call the real EasyOCR model in
tests. Verifies the pipeline persists a complete `silver_evidence_ocr` row.
"""

from datetime import datetime

from app.config import settings
from app.models import (
    Activity,
    DuplicateReason,
    EvidenceStatus,
    MatchKind,
    OcrDecision,
    Participation,
    RawFile,
    Student,
    StudentStatus,
)
from app.silver import (
    DuplicateMatch,
    find_duplicate,
    process_participation_evidence,
    text_similarity,
    text_vetoes_near_match,
)

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


def _add_raw(session, storage, participation_id, checksum="a" * 64, content_type="image/png", phash=None):
    key = f"evidence/test/p={participation_id}/{checksum[:8]}.png"
    storage.upload_object("bronze", key, PNG, content_type)
    rf = RawFile(
        bucket="bronze",
        object_key=key,
        original_filename="evidence.png",
        content_type=content_type,
        size_bytes=len(PNG),
        checksum=checksum,
        phash=phash,
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


# ---------------- เฟส 1.2: บันทึกใบต้นทาง + เหตุผลลงแถว OCR ----------------


def test_flagged_row_records_duplicate_of_and_reason(session, storage):
    activity = _activity(session)
    first = _participation(session, _student(session, "88601").id, activity.id)
    _add_raw(session, storage, first.id, checksum=SAME)
    later = _participation(session, _student(session, "88602").id, activity.id)
    _add_raw(session, storage, later.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.9), storage, later.id)
    session.expire_all()
    stored = session.get(type(row), row.id)

    assert stored.decision == OcrDecision.flagged
    assert stored.duplicate_of_participation_id == first.id
    assert stored.duplicate_reason == DuplicateReason.cross_student


def test_rejected_match_is_recorded_on_the_row(session, storage):
    activity = _activity(session)
    rejected = _participation(session, _student(session, "88611").id, activity.id,
                              status=EvidenceStatus.rejected)
    _add_raw(session, storage, rejected.id, checksum=SAME)
    p = _participation(session, _student(session, "88612").id, activity.id)
    _add_raw(session, storage, p.id, checksum=SAME)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.9), storage, p.id)

    assert row.duplicate_of_participation_id == rejected.id
    assert row.duplicate_reason == DuplicateReason.matches_rejected


def test_non_duplicate_row_leaves_duplicate_fields_empty(session, storage):
    p = _participation(session, _student(session).id, _activity(session).id)
    _add_raw(session, storage, p.id, checksum="solo" + "0" * 60)

    row = process_participation_evidence(session, FakeOcr(text="x", confidence=0.9), storage, p.id)

    assert row.is_duplicate is False
    assert row.duplicate_of_participation_id is None
    assert row.duplicate_reason is None


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


# ---------------- เฟส 3A.2: ภาพเกือบเหมือน (pHash 256 บิต) + text veto ----------------

# ข้อความ OCR ของเกียรติบัตรใบเดียวกัน (อ่านซ้ำหลังบีบอัด เพี้ยนไม่กี่ตัว) และของใบคนละเรื่อง
CERT_TEXT = (
    "มหาวิทยาลัยทักษิณ เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า นางสาวกรวรรณ ยาง๊ะ "
    "ได้เข้าร่วมกิจกรรม ตลาดนัดผู้ประกอบการรุ่นเยาว์ ครั้งที่ 5/2569 เลขที่อ้างอิง TSU-180-62162-025853"
)
CERT_TEXT_REREAD = (
    "มหาวิทยาลัยทักษิณ เกียรติบัตรฉบับนี้ให้ไว้เพื่อแสดงว่า นางสาวกรวรรณ ยางะ "
    "ได้เข้ารวมกิจกรรม ตลาดนัดผู้ประกอบการรุนเยาว์ ครั้งที่ 5/2569 เลขที่อ้างอิง TSU-180-62162-O25853"
)
UNRELATED_TEXT = (
    "ใบรับรองการฝึกงานภาคฤดูร้อน บริษัทตัวอย่างการค้า จำกัด ขอรับรองว่า นายภูวดล สมหวัง "
    "ปฏิบัติงานแผนกบัญชีและการเงิน ระยะเวลาสองเดือน ปีการศึกษา 2568"
)
BASE_PHASH = "0" * 64


def _phash(bits_flipped: int) -> str:
    """pHash 256 บิตที่ห่างจาก BASE_PHASH เท่ากับ [bits_flipped] บิตพอดี"""
    return format((1 << bits_flipped) - 1, "064x")


def _flagged_by(session, storage, *, first_text, second_text, distance, first_status=EvidenceStatus.pending,
                same_student=False, process_first=True):
    """ใบแรก (มาก่อน) + ใบที่สองที่ checksum ต่างแต่ pHash ห่าง [distance] บิต — คืน (first, second, row)"""
    student_a = _student(session, "88701")
    student_b = student_a if same_student else _student(session, "88702")
    first = _participation(session, student_a.id, _activity(session, "ค่ายอาสา").id, status=first_status)
    first_raw = _add_raw(session, storage, first.id, checksum="n1" + "0" * 62, phash=BASE_PHASH)
    if process_first:
        process_participation_evidence(session, FakeOcr(text=first_text, confidence=0.9), storage, first.id)
    second = _participation(session, student_b.id, _activity(session, "อบรมดิจิทัล").id)
    second_raw = _add_raw(session, storage, second.id, checksum="n2" + "0" * 62, phash=_phash(distance))
    row = process_participation_evidence(session, FakeOcr(text=second_text, confidence=0.9), storage, second.id)
    return (first, first_raw), (second, second_raw), row


def test_texts_used_by_the_veto_tests_behave_as_measured():
    """กันเทสข้างล่างผ่านเพราะข้อความทดสอบบังเอิญ — ใบเดียวกันคล้ายสูง ใบคนละเรื่องต่ำ"""
    assert text_similarity(CERT_TEXT, CERT_TEXT_REREAD) >= 0.9
    assert text_similarity(CERT_TEXT, UNRELATED_TEXT) < settings.ocr_text_veto_max_similarity


def test_near_copy_of_other_students_certificate_is_flagged_near(session, storage):
    (first, first_raw), (_, second_raw), row = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=CERT_TEXT_REREAD, distance=10
    )

    assert row.decision == OcrDecision.flagged and row.is_duplicate is True
    assert row.duplicate_reason == DuplicateReason.cross_student
    assert row.duplicate_of_participation_id == first.id
    assert row.match_kind == MatchKind.near
    assert find_duplicate(session, second_raw, CERT_TEXT_REREAD) == DuplicateMatch(
        DuplicateReason.cross_student, first.id, first_raw.id, MatchKind.near, 10
    )


def test_phash_beyond_threshold_is_not_a_duplicate(session, storage):
    _, _, row = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=CERT_TEXT_REREAD,
        distance=settings.ocr_phash_near_bits + 1,
    )

    assert row.is_duplicate is False and row.match_kind is None
    assert row.decision == OcrDecision.needs_review


def test_similar_image_but_clearly_different_readable_text_is_vetoed(session, storage):
    """เทมเพลตเดียวกันคนละคน: ภาพคล้าย แต่ข้อความอ่านออกทั้งคู่และต่างกันชัด → ไม่ flag"""
    _, (_, second_raw), row = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=UNRELATED_TEXT, distance=4
    )

    assert row.is_duplicate is False and row.duplicate_reason is None and row.match_kind is None
    assert find_duplicate(session, second_raw, UNRELATED_TEXT) is None


def test_no_veto_when_this_file_is_unreadable(session, storage):
    _, _, row = _flagged_by(session, storage, first_text=CERT_TEXT, second_text="", distance=4)

    assert row.decision == OcrDecision.flagged and row.match_kind == MatchKind.near


def test_no_veto_when_the_earlier_file_was_never_ocrd(session, storage):
    """ใบต้นทางไม่มีผล OCR เลย (เช่นใบที่แนบเป็นอนุมัติโดยไม่ผ่าน OCR) → ไม่มีข้อความให้ veto คง flag"""
    _, _, row = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=UNRELATED_TEXT, distance=4, process_first=False
    )

    assert row.decision == OcrDecision.flagged and row.match_kind == MatchKind.near


def test_near_match_keeps_reason_rules_same_student_and_rejected(session, storage):
    _, _, reuse = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=CERT_TEXT_REREAD, distance=6, same_student=True
    )
    assert (reuse.duplicate_reason, reuse.match_kind) == (DuplicateReason.same_student_reuse, MatchKind.near)


def test_near_match_against_rejected_proof(session, storage):
    _, _, row = _flagged_by(
        session, storage, first_text=CERT_TEXT, second_text=CERT_TEXT_REREAD, distance=6,
        first_status=EvidenceStatus.rejected,
    )
    assert (row.duplicate_reason, row.match_kind) == (DuplicateReason.matches_rejected, MatchKind.near)


def test_exact_checksum_comes_first_and_is_marked_exact(session, storage):
    """ไฟล์เดียวกันเป๊ะกับใบหนึ่ง และภาพใกล้กว่ากับอีกใบ → ใช้ checksum (exact) เสมอ"""
    activity = _activity(session)
    exact_owner = _participation(session, _student(session, "88801").id, activity.id)
    exact_raw = _add_raw(session, storage, exact_owner.id, checksum=SAME, phash=_phash(12))
    near_owner = _participation(session, _student(session, "88802").id, activity.id)
    _add_raw(session, storage, near_owner.id, checksum="x1" + "0" * 62, phash=BASE_PHASH)
    p = _participation(session, _student(session, "88803").id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum=SAME, phash=BASE_PHASH)

    row = process_participation_evidence(session, FakeOcr(text=CERT_TEXT, confidence=0.9), storage, p.id)

    assert row.match_kind == MatchKind.exact
    assert row.duplicate_of_participation_id == exact_owner.id
    assert find_duplicate(session, raw, CERT_TEXT) == DuplicateMatch(
        DuplicateReason.cross_student, exact_owner.id, exact_raw.id
    )


def test_near_candidates_pick_reason_first_then_nearest(session, storage):
    """rejected ใกล้สุด · คนเดิมใกล้รองลงมา · คนอื่นสองใบ (12, 8) → เลือกคนอื่นที่ห่าง 8"""
    me = _student(session, "88901")
    rejected = _participation(session, _student(session, "88902").id, _activity(session, "ก").id,
                              status=EvidenceStatus.rejected)
    _add_raw(session, storage, rejected.id, checksum="r1" + "0" * 62, phash=_phash(2))
    mine = _participation(session, me.id, _activity(session, "ข").id)
    _add_raw(session, storage, mine.id, checksum="r2" + "0" * 62, phash=_phash(3))
    far_other = _participation(session, _student(session, "88903").id, _activity(session, "ค").id)
    _add_raw(session, storage, far_other.id, checksum="r3" + "0" * 62, phash=_phash(12))
    near_other = _participation(session, _student(session, "88904").id, _activity(session, "ง").id)
    near_other_raw = _add_raw(session, storage, near_other.id, checksum="r4" + "0" * 62, phash=_phash(8))
    p = _participation(session, me.id, _activity(session, "จ").id)
    raw = _add_raw(session, storage, p.id, checksum="r5" + "0" * 62, phash=BASE_PHASH)

    match = find_duplicate(session, raw, "")

    assert match == DuplicateMatch(DuplicateReason.cross_student, near_other.id, near_other_raw.id, MatchKind.near, 8)


def test_file_without_phash_skips_the_near_check(session, storage):
    """PDF / ถอดภาพไม่ได้ / ไฟล์ก่อนเฟส 3A ไม่มี pHash → ไม่มีชั้น near (พฤติกรรมเดิม)"""
    activity = _activity(session)
    other = _participation(session, _student(session, "89001").id, activity.id)
    _add_raw(session, storage, other.id, checksum="w1" + "0" * 62, phash=BASE_PHASH)
    p = _participation(session, _student(session, "89002").id, activity.id)
    raw = _add_raw(session, storage, p.id, checksum="w2" + "0" * 62, phash=None)

    assert find_duplicate(session, raw, "") is None


def test_thresholds_come_from_config(session, storage, monkeypatch):
    monkeypatch.setattr(settings, "ocr_phash_near_bits", 4)
    _, (_, raw_far), _ = _flagged_by(session, storage, first_text=CERT_TEXT, second_text=CERT_TEXT, distance=10)
    assert find_duplicate(session, raw_far, CERT_TEXT) is None, "10 บิตเกิน threshold ที่ตั้งเป็น 4"

    monkeypatch.setattr(settings, "ocr_phash_near_bits", 16)
    monkeypatch.setattr(settings, "ocr_text_veto_max_similarity", 0.0)  # ปิด veto
    assert text_vetoes_near_match(CERT_TEXT, UNRELATED_TEXT) is False
    monkeypatch.setattr(settings, "ocr_text_veto_max_similarity", 0.5)
    monkeypatch.setattr(settings, "ocr_text_veto_min_chars", 10_000)  # ไม่มีใบไหน "อ่านออก" → ไม่ veto
    assert text_vetoes_near_match(CERT_TEXT, UNRELATED_TEXT) is False
