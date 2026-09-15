"""Evidence Kind เฟส 1 — ประเภทหลักฐาน: certificate auto ได้ · photo/other → needs_review เสมอ

OCR ยืนยันได้แค่ "งานจัดจริง" จากข้อความบนใบ ยืนยันตัวตนคนในภาพถ่ายไม่ได้ ภาพถ่ายจึงต้องให้คนตรวจ
แต่ OCR + dedup (checksum / pHash) ยังต้องทำงานกับภาพถ่ายเหมือนเดิม

OCR เป็นตัวปลอมเสมอ (ไม่เรียก EasyOCR จริง)
"""
from datetime import datetime

import pytest
from sqlmodel import select

from app.main import app
from app.models import (
    Activity,
    ApprovalStatus,
    DuplicateReason,
    EvidenceKind,
    EvidenceStatus,
    MatchKind,
    OcrDecision,
    Participation,
    RawFile,
    Student,
    StudentStatus,
    User,
)
from app.ocr import get_ocr
from app.silver import auto_approval_allowed, process_participation_evidence

PNG = b"\x89PNG\r\n\x1a\nfake"
STUDENT_NAME = "นายสมชาย ใจดี"
ACTIVITY_NAME = "ค่ายอาสาพัฒนาชนบท"
# ข้อความที่ตรงนิสิต + กิจกรรม + ปี (2026 = พ.ศ. 2569) → match สูง
MATCHING_TEXT = f"เกียรติบัตร {STUDENT_NAME} เข้าร่วม {ACTIVITY_NAME} วันที่ 1 สิงหาคม 2569"


class FakeOcr:
    def __init__(self, text=MATCHING_TEXT, confidence=0.95):
        self.text, self.confidence, self.calls = text, confidence, 0

    def run_ocr(self, image_bytes: bytes):
        self.calls += 1
        return (self.text, self.confidence)


def _staff_id(session):
    return session.exec(select(User).where(User.username == "staff")).first().id


def _participation(session, code="86001", activity_name=ACTIVITY_NAME):
    student = Student(
        student_id=code, full_name=STUDENT_NAME, faculty="วิศวกรรมศาสตร์",
        major="คอมพิวเตอร์", year_level=2, status=StudentStatus.active,
    )
    activity = Activity(
        name=activity_name, activity_type="จิตอาสา", is_required=False, max_participants=50,
        start_at=datetime(2026, 8, 1, 9, 0, 0), location="ห้อง", hours=4,
        created_by=_staff_id(session), approval_status=ApprovalStatus.approved,
    )
    session.add(student)
    session.add(activity)
    session.commit()
    p = Participation(student_id=student.id, activity_id=activity.id,
                      evidence_status=EvidenceStatus.pending, hours_earned=0)
    session.add(p)
    session.commit()
    session.refresh(p)
    return p


def _add_raw(session, storage, participation_id, *, kind, checksum=None, phash=None):
    checksum = checksum or f"kind{participation_id}".ljust(64, "0")
    key = f"evidence/test/p={participation_id}/{checksum[:8]}.png"
    storage.upload_object("bronze", key, PNG, "image/png")
    raw = RawFile(
        bucket="bronze", object_key=key, original_filename="e.png", content_type="image/png",
        size_bytes=len(PNG), checksum=checksum, phash=phash, evidence_kind=kind,
        source_system="student_upload", participation_id=participation_id,
    )
    session.add(raw)
    session.commit()
    session.refresh(raw)
    return raw


# ------------------------------ ตัดสินใน silver ------------------------------


@pytest.mark.parametrize("kind", [EvidenceKind.photo, EvidenceKind.other])
def test_photo_or_other_with_perfect_score_still_needs_review(session, storage, kind):
    p = _participation(session)
    _add_raw(session, storage, p.id, kind=kind)
    ocr = FakeOcr()

    row = process_participation_evidence(session, ocr, storage, p.id)

    assert ocr.calls == 1, "ยังรัน OCR ให้คนตรวจอ้างอิง"
    assert row.extracted_text == MATCHING_TEXT
    assert row.ocr_confidence >= 0.9 and row.match_score >= 0.7, "คะแนนผ่านเกณฑ์ auto ทุกข้อ"
    assert row.decision == OcrDecision.needs_review
    updated = session.get(Participation, p.id)
    assert updated.evidence_status == EvidenceStatus.pending and updated.hours_earned == 0


def test_certificate_with_perfect_score_is_auto_approved_as_before(session, storage):
    p = _participation(session)
    _add_raw(session, storage, p.id, kind=EvidenceKind.certificate)

    row = process_participation_evidence(session, FakeOcr(), storage, p.id)

    assert row.decision == OcrDecision.auto_approved
    updated = session.get(Participation, p.id)
    assert updated.evidence_status == EvidenceStatus.approved and updated.hours_earned == 4


def test_legacy_file_without_kind_behaves_like_certificate(session, storage):
    p = _participation(session)
    raw = _add_raw(session, storage, p.id, kind=None)

    row = process_participation_evidence(session, FakeOcr(), storage, p.id)

    assert auto_approval_allowed(raw) is True
    assert row.decision == OcrDecision.auto_approved


def test_photo_that_is_an_exact_duplicate_is_still_flagged(session, storage):
    """dedup ต้องยังจับภาพถ่ายที่แชร์กัน — flagged มาก่อน needs_review"""
    first = _participation(session, code="86101")
    _add_raw(session, storage, first.id, kind=EvidenceKind.photo, checksum="share" + "0" * 59)
    second = _participation(session, code="86102", activity_name="อบรมดิจิทัล")
    _add_raw(session, storage, second.id, kind=EvidenceKind.photo, checksum="share" + "0" * 59)

    row = process_participation_evidence(session, FakeOcr(), storage, second.id)

    assert row.decision == OcrDecision.flagged
    assert row.match_kind == MatchKind.exact and row.duplicate_reason == DuplicateReason.cross_student


def test_photo_that_is_a_near_duplicate_is_still_flagged_near(session, storage):
    first = _participation(session, code="86201")
    _add_raw(session, storage, first.id, kind=EvidenceKind.photo, phash="0" * 64)  # ไม่เคย OCR → ไม่มี veto
    second = _participation(session, code="86202", activity_name="อบรมดิจิทัล")
    _add_raw(session, storage, second.id, kind=EvidenceKind.photo, phash=format((1 << 6) - 1, "064x"))

    row = process_participation_evidence(session, FakeOcr(), storage, second.id)

    assert (row.decision, row.match_kind) == (OcrDecision.flagged, MatchKind.near)


def test_reprocessing_a_photo_never_auto_approves(client, session, storage, tokens):
    """ทางอ้อม: สั่งประมวลผลใหม่ผ่าน API ด้วยคะแนนเต็มก็ยังไม่ auto"""
    p = _participation(session)
    _add_raw(session, storage, p.id, kind=EvidenceKind.photo)
    app.dependency_overrides[get_ocr] = lambda: FakeOcr()
    headers = {"Authorization": f"Bearer {tokens['admin']}"}

    for _ in range(2):
        body = client.post(f"/participations/{p.id}/evidence/process", headers=headers).json()
        assert body["decision"] == "needs_review"
        assert body["evidence_kind"] == "photo"
    assert session.get(Participation, p.id).evidence_status == EvidenceStatus.pending


def test_latest_file_kind_decides(session, storage):
    """ส่งภาพถ่ายก่อนแล้วอัปโหลดเกียรติบัตรทับ → ใช้ประเภทของไฟล์ล่าสุด"""
    p = _participation(session)
    _add_raw(session, storage, p.id, kind=EvidenceKind.photo, checksum="old" + "0" * 61)
    _add_raw(session, storage, p.id, kind=EvidenceKind.certificate, checksum="new" + "0" * 61)

    row = process_participation_evidence(session, FakeOcr(), storage, p.id)

    assert row.decision == OcrDecision.auto_approved


# ------------------------------ อัปโหลด API ------------------------------


def _upload(client, tokens, participation_id, data=None):
    return client.post(
        f"/participations/{participation_id}/evidence",
        files={"file": ("proof.png", PNG, "image/png")},
        data=data or {},
        headers={"Authorization": f"Bearer {tokens['admin']}"},
    )


def _latest_raw(session, participation_id):
    session.expire_all()
    return session.exec(
        select(RawFile).where(RawFile.participation_id == participation_id).order_by(RawFile.id.desc())
    ).first()


@pytest.mark.parametrize("kind", ["certificate", "photo", "other"])
def test_upload_stores_the_chosen_kind(client, session, tokens, kind):
    p = _participation(session)

    response = _upload(client, tokens, p.id, {"evidence_kind": kind})

    assert response.status_code == 201, response.text
    assert _latest_raw(session, p.id).evidence_kind == EvidenceKind(kind)


def test_upload_without_kind_is_rejected(client, session, tokens):
    """เฟส 2: หน้าอัปโหลดมีตัวเลือกแล้ว — นิสิตต้องเลือกเอง ไม่ปล่อยค่าเริ่ม certificate เงียบ ๆ

    (ถ้าปล่อย default ภาพถ่ายที่ไม่ได้เลือกประเภทจะหลุดเข้าเส้นทาง auto ได้)
    """
    p = _participation(session)

    response = _upload(client, tokens, p.id)

    assert response.status_code == 422
    assert "evidence_kind" in response.text
    assert _latest_raw(session, p.id) is None, "ไม่ระบุประเภทต้องไม่มีไฟล์ถูกบันทึก"


def test_upload_rejects_an_unknown_kind(client, session, tokens):
    p = _participation(session)

    response = _upload(client, tokens, p.id, {"evidence_kind": "selfie"})

    assert response.status_code == 422
    assert _latest_raw(session, p.id) is None, "ค่าผิดต้องไม่มีไฟล์ถูกบันทึก"


def test_participation_reads_carry_latest_evidence_kind_for_the_queue(client, session, storage, tokens):
    """คิวตรวจ (GET /participations) และรายละเอียด บอกประเภทของไฟล์ล่าสุด · legacy null → certificate
    · ยังไม่ส่งไฟล์ → null"""
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    photo_p = _participation(session, code="86401")
    _add_raw(session, storage, photo_p.id, kind=EvidenceKind.certificate, checksum="k1" + "0" * 62)
    _add_raw(session, storage, photo_p.id, kind=EvidenceKind.photo, checksum="k2" + "0" * 62)  # ล่าสุด
    legacy_p = _participation(session, code="86402", activity_name="อบรมดิจิทัล")
    _add_raw(session, storage, legacy_p.id, kind=None)
    empty_p = _participation(session, code="86403", activity_name="กีฬาสัมพันธ์")

    listed = {
        r["id"]: r["evidence_kind"]
        for r in client.get("/participations", params={"limit": 50}, headers=headers).json()["items"]
    }
    detail = client.get(f"/participations/{photo_p.id}", headers=headers).json()

    assert listed[photo_p.id] == "photo" and detail["evidence_kind"] == "photo"
    assert listed[legacy_p.id] == "certificate"
    assert listed[empty_p.id] is None


def test_ocr_result_exposes_kind_and_legacy_reads_as_certificate(client, session, storage, tokens):
    headers = {"Authorization": f"Bearer {tokens['admin']}"}
    photo_p = _participation(session, code="86301")
    _add_raw(session, storage, photo_p.id, kind=EvidenceKind.photo)
    legacy_p = _participation(session, code="86302", activity_name="อบรมดิจิทัล")
    _add_raw(session, storage, legacy_p.id, kind=None)
    for p in (photo_p, legacy_p):
        process_participation_evidence(session, FakeOcr(text="x", confidence=0.5), storage, p.id)

    assert client.get(f"/participations/{photo_p.id}/ocr", headers=headers).json()["evidence_kind"] == "photo"
    assert client.get(f"/participations/{legacy_p.id}/ocr", headers=headers).json()["evidence_kind"] == "certificate"
