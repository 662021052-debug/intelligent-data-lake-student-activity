"""Silver layer — clean/verify Bronze evidence with OCR.

Phase 13 builds the foundation: take the latest Bronze file for a participation,
run OCR, detect duplicates by checksum, and persist one `silver_evidence_ocr`
row. The match-scoring and auto-approval decision are added in Phase 14 — for now
every non-duplicate result is left as `needs_review` (human-in-the-loop).
"""
from __future__ import annotations

import logging
import re
from dataclasses import dataclass
from datetime import datetime
from difflib import SequenceMatcher
from typing import Optional

from sqlmodel import Session, select

from app.approval import apply_approval
from app.config import settings
from app.models import (
    Activity,
    DuplicateReason,
    EvidenceKind,
    EvidenceStatus,
    MatchKind,
    OcrDecision,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
)
from app.ocr import OcrEngine
from app.pdf import extract_text_layer, render_pdf_pages
from app.phash import phash_distance
from app.storage import ObjectStorage

logger = logging.getLogger("uvicorn.error")


def _latest_raw_file(session: Session, participation_id: int) -> Optional[RawFile]:
    """The most recent Bronze file for a participation (Bronze is append-only)."""
    return session.exec(
        select(RawFile)
        .where(RawFile.participation_id == participation_id)
        .order_by(RawFile.id.desc())
    ).first()


@dataclass(frozen=True)
class DuplicateMatch:
    """ไฟล์นี้ซ้ำกับใบไหน ซ้ำแบบไหน และตรงกันแบบเป๊ะหรือแค่คล้าย"""

    reason: DuplicateReason
    participation_id: int
    raw_file_id: int
    match_kind: MatchKind = MatchKind.exact
    distance: Optional[int] = None  # Hamming distance ของ pHash (เฉพาะ near)


# ลำดับความสำคัญของเหตุผล — ใบที่ใช้งานมาก่อนเพราะเสี่ยงได้ชั่วโมงซ้ำจริง
_REASON_RANK = {
    DuplicateReason.cross_student: 0,
    DuplicateReason.same_student_reuse: 1,
    DuplicateReason.matches_rejected: 2,
}


def _reason_for(status: EvidenceStatus, other_student_id: int, current_student_id: int) -> DuplicateReason:
    if status == EvidenceStatus.rejected:
        return DuplicateReason.matches_rejected
    if other_student_id != current_student_id:
        return DuplicateReason.cross_student
    return DuplicateReason.same_student_reuse


def find_duplicate(
    session: Session, raw_file: RawFile, text: Optional[str] = None
) -> Optional[DuplicateMatch]:
    """หาใบที่ "มาก่อน" ซึ่งเป็นไฟล์เดียวกัน (เป๊ะ) หรือภาพเกือบเหมือน (คล้าย) กับ [raw_file]

    กติกาที่ใช้ทั้งสองชั้น:

    * เทียบกับทุกใบในระบบ ไม่ใช่แค่ใบที่อนุมัติแล้ว — สองคนส่งไฟล์เดียวกันตอนยัง
      pending ทั้งคู่ก็ต้องจับได้
    * นับเฉพาะไฟล์ที่ id น้อยกว่า: ใบหลังโดน flag ใบแรกไม่โดน และสั่งอ่านใหม่กี่รอบ
      ผลก็เหมือนเดิม (deterministic)
    * ไฟล์ในการเข้าร่วมเดียวกัน = อัปโหลดซ้ำของตัวเอง ไม่ใช่ทุจริต → ไม่นับ
    * ลำดับเหตุผลเมื่อตรงหลายใบ:

      1. ``cross_student`` — ใบที่ยังใช้งาน (pending/approved) ของนิสิตคนอื่น
      2. ``same_student_reuse`` — ใบที่ยังใช้งานของคนเดิมคนละการเข้าร่วม (กิจกรรมอื่น
         หรือลงกิจกรรมเดิมซ้ำ ซึ่งจะได้ชั่วโมงสองรอบ)
      3. ``matches_rejected`` — ไม่ซ้ำใบที่ใช้งานเลย แต่ตรงกับใบที่เคยถูกปฏิเสธ

    ชั้นที่ 1 ``exact`` — checksum เดียวกัน (เฟส 1) มาก่อนเสมอ ค้นด้วย index ของ checksum
    ชั้นที่ 2 ``near`` — ถ้าชั้นแรกไม่เจอ ดู pHash (ดู :func:`_near_duplicate`) โดยใช้ [text]
    ข้อความ OCR ของไฟล์นี้ประกอบการ veto
    """
    if raw_file.participation_id is None:
        return None
    current = session.get(Participation, raw_file.participation_id)
    if current is None:
        return None
    return _exact_duplicate(session, raw_file, current) or _near_duplicate(
        session, raw_file, current, text
    )


def _exact_duplicate(
    session: Session, raw_file: RawFile, current: Participation
) -> Optional[DuplicateMatch]:
    earlier = session.exec(
        select(RawFile.id, Participation.id, Participation.student_id, Participation.evidence_status)
        .join(Participation, Participation.id == RawFile.participation_id)
        .where(
            RawFile.checksum == raw_file.checksum,
            RawFile.id < raw_file.id,
            RawFile.participation_id != current.id,
        )
        .order_by(RawFile.id)
    ).all()
    matches = [
        (_REASON_RANK[reason], other_raw_file_id, DuplicateMatch(reason, other_participation_id, other_raw_file_id))
        for other_raw_file_id, other_participation_id, other_student_id, status in earlier
        for reason in (_reason_for(status, other_student_id, current.student_id),)
    ]
    return min(matches)[-1] if matches else None


def _near_duplicate(
    session: Session, raw_file: RawFile, current: Participation, text: Optional[str]
) -> Optional[DuplicateMatch]:
    """ภาพเกือบเหมือน: pHash ห่าง ≤ ``settings.ocr_phash_near_bits`` และข้อความไม่ veto

    * ไฟล์ที่ไม่มี pHash (PDF / ถอดภาพไม่ได้ / เข้ามาก่อนเฟส 3A) ข้ามชั้นนี้ไป
    * text veto (:func:`text_vetoes_near_match`): ใบเกียรติบัตรเทมเพลตเดียวกันของคนละคน
      หน้าตาคล้ายกันได้ ถ้าข้อความ OCR สองใบต่างกันชัดและอ่านออกทั้งคู่ → ไม่นับว่าซ้ำ
    * เลือกตามลำดับเหตุผล แล้วใกล้สุด แล้วใบแรกสุด

    performance: Hamming distance ใช้ index ธรรมดาไม่ได้ จึงดึงไฟล์ภาพที่มาก่อนและมี pHash
    ทั้งหมดมาเทียบในหน่วยความจำ — O(จำนวนไฟล์ภาพในระบบ) ต่อการประมวลผลหนึ่งครั้ง
    """
    if not raw_file.phash:
        return None
    candidates = session.exec(
        select(
            RawFile.id,
            RawFile.phash,
            Participation.id,
            Participation.student_id,
            Participation.evidence_status,
        )
        .join(Participation, Participation.id == RawFile.participation_id)
        .where(
            RawFile.phash.is_not(None),
            RawFile.id < raw_file.id,
            RawFile.participation_id != current.id,
        )
        .order_by(RawFile.id)
    ).all()

    matches = []
    for other_raw_file_id, other_phash, other_participation_id, other_student_id, status in candidates:
        distance = phash_distance(raw_file.phash, other_phash)
        if distance > settings.ocr_phash_near_bits:
            continue
        if text_vetoes_near_match(text, _latest_ocr_text(session, other_raw_file_id)):
            continue
        reason = _reason_for(status, other_student_id, current.student_id)
        match = DuplicateMatch(
            reason, other_participation_id, other_raw_file_id, MatchKind.near, distance
        )
        matches.append((_REASON_RANK[reason], distance, other_raw_file_id, match))
    return min(matches)[-1] if matches else None


def _latest_ocr_text(session: Session, raw_file_id: int) -> Optional[str]:
    """ข้อความ OCR ล่าสุดของไฟล์ — None ถ้าไฟล์นั้นยังไม่เคยผ่าน OCR"""
    return session.exec(
        select(SilverEvidenceOcr.extracted_text)
        .where(SilverEvidenceOcr.raw_file_id == raw_file_id)
        .order_by(SilverEvidenceOcr.id.desc())
    ).first()


def text_similarity(a: Optional[str], b: Optional[str]) -> float:
    """ความคล้ายของข้อความ OCR ทั้งใบ (0–1) หลังตัดช่องว่าง/ตัวพิมพ์

    ใช้ ratio ของทั้งก้อน ไม่ใช่ partial ratio — partial ให้ 1.0 ทันทีเมื่อข้อความสั้นอยู่ใน
    ข้อความยาว ซึ่งทำให้ veto อ่อนเกินไป (ใบที่อ่านได้ครึ่งเดียวจะดูเหมือนทุกใบ)
    """
    return SequenceMatcher(None, _norm(a or ""), _norm(b or "")).ratio()


def text_vetoes_near_match(mine: Optional[str], theirs: Optional[str]) -> bool:
    """True = ข้อความสองใบต่างกันชัดและอ่านออกทั้งคู่ → ภาพคล้ายนี้ไม่ใช่ใบซ้ำ

    ใบใดอ่านไม่ออก/ว่าง/ยังไม่เคย OCR → ไม่ veto (คง flag ไว้) กัน false negative จาก OCR แย่
    """
    min_chars = settings.ocr_text_veto_min_chars
    if len(_norm(mine or "")) < min_chars or len(_norm(theirs or "")) < min_chars:
        return False
    return text_similarity(mine, theirs) < settings.ocr_text_veto_max_similarity


def _extract_text(ocr: OcrEngine, storage: ObjectStorage, raw_file: RawFile) -> tuple[str, float]:
    """OCR ไฟล์หลักฐานใน Bronze — ภาพส่งเข้า OCR ตรง ๆ · PDF render ทีละหน้าเป็นภาพก่อน (เฟส 3B)

    อ่านไฟล์ / render / OCR ล้มตรงไหนก็คืน ("", 0.0) → needs_review ไม่ให้ pipeline ล้ม
    """
    is_image = raw_file.content_type.startswith("image/")
    is_pdf = raw_file.content_type == "application/pdf"
    if not (is_image or is_pdf):
        return ("", 0.0)
    try:
        data = storage.get_object_bytes(raw_file.bucket, raw_file.object_key)
        return ocr.run_ocr(data) if is_image else _ocr_pdf(ocr, data)
    except Exception:  # noqa: BLE001 - OCR/storage/PDF failure must not crash the pipeline
        return ("", 0.0)


def _ocr_pdf(ocr: OcrEngine, data: bytes) -> tuple[str, float]:
    """ข้อความของ PDF ไม่เกิน ``settings.ocr_pdf_max_pages`` หน้าแรก — text layer ก่อน แล้วค่อย OCR

    1. มี text layer พอ (≥ ``ocr_pdf_text_layer_min_chars``) → ใช้ข้อความนั้นตรง ๆ ไม่เรียก OCR
       ความมั่นใจ = ``ocr_pdf_text_layer_confidence`` (อ่านจากไฟล์ ไม่ได้เดา)
    2. ไม่มี/น้อยเกิน (PDF สแกนภาพล้วน หรือมีแค่เลขหน้า) → render ทีละหน้าเป็นภาพแล้ว OCR
       ข้อความรวมทุกหน้าที่อ่านได้ · ความมั่นใจเฉลี่ยเฉพาะหน้าที่อ่านได้ — หน้าว่าง (เช่นหน้าหลัง
       ของเกียรติบัตร) ไม่ดึงค่าเฉลี่ยลงเป็น 0

    pHash ของ PDF ยังมาจากภาพ render หน้าแรกเสมอ (app.phash) ไม่ขึ้นกับเส้นทางนี้
    """
    layer = extract_text_layer(data, max_pages=settings.ocr_pdf_max_pages)
    if len(_norm(layer)) >= settings.ocr_pdf_text_layer_min_chars:
        return (layer, settings.ocr_pdf_text_layer_confidence)

    pages = render_pdf_pages(
        data,
        max_pages=settings.ocr_pdf_max_pages,
        dpi=settings.ocr_pdf_dpi,
        max_side_px=settings.ocr_pdf_max_side_px,
    )
    texts: list[str] = []
    confidences: list[float] = []
    for page_png in pages:
        text, confidence = ocr.run_ocr(page_png)
        if text.strip():
            texts.append(text)
            confidences.append(confidence)
    if not texts:
        return ("", 0.0)
    return ("\n".join(texts), sum(confidences) / len(confidences))


# --------------------------- match scoring ---------------------------
# match_score weights: how much each signal contributes to the 0-1 score.
_W_NAME = 0.4
_W_ACTIVITY = 0.4
_W_DATE = 0.2

_NAME_PREFIXES = ("นางสาว", "เด็กชาย", "เด็กหญิง", "นาย", "นาง")

# OCR ภาษาไทยมักอ่านเพี้ยนไม่กี่ตัว (เช่น โภชนาการ -> โกชนาการ) การเทียบแบบ substring
# ตรง ๆ จะได้ 0 ทันที ซึ่งรุนแรงเกินไปโดยเฉพาะ "ชื่อกิจกรรม" ที่ภาษาไทยเขียนติดกัน
# ไม่มีช่องว่างให้ตัดเป็นคำ — ผิดตัวเดียวก็หล่นทั้งก้อน จึงเทียบแบบคล้ายกัน (fuzzy) แทน
#
# ต่ำกว่าเกณฑ์นี้ถือว่า "คนละคำ" ไม่ใช่แค่พิมพ์เพี้ยน — กันไม่ให้ข้อความสุ่ม ๆ
# ได้คะแนนติดมือไปฟรี ๆ (0.8 ≈ ยอมให้ผิดได้ราว 1-2 ตัวในคำยาว 10-20 ตัวอักษร)
_FUZZY_FLOOR = 0.8


def _norm(text: str) -> str:
    """Whitespace-insensitive, case-folded form for substring matching."""
    return re.sub(r"\s+", "", text or "").lower()


def _best_partial_ratio(needle: str, haystack: str) -> float:
    """ความคล้ายสูงสุดของ [needle] กับ "ท่อน" ใด ๆ ที่ยาวเท่ากันใน [haystack] (0-1)

    ใช้แทน ``needle in haystack`` เพื่อให้ทน OCR อ่านเพี้ยนไม่กี่ตัว
    """
    if not needle or not haystack:
        return 0.0
    if needle in haystack:
        return 1.0
    if len(haystack) <= len(needle):
        return SequenceMatcher(None, needle, haystack).ratio()

    best = 0.0
    window = len(needle)
    for start in range(len(haystack) - window + 1):
        ratio = SequenceMatcher(None, needle, haystack[start : start + window]).ratio()
        if ratio > best:
            best = ratio
            if best == 1.0:
                break
    return best


def _fuzzy_hit(needle: str, haystack: str) -> float:
    """คะแนนความตรงกัน 0-1 โดยตัดค่าที่ต่ำกว่าเกณฑ์ทิ้งเป็น 0"""
    ratio = _best_partial_ratio(_norm(needle), haystack)
    return ratio if ratio >= _FUZZY_FLOOR else 0.0


def _name_tokens(full_name: str) -> list[str]:
    """Significant name tokens, with Thai honorific prefixes stripped."""
    tokens: list[str] = []
    for raw in (full_name or "").split():
        token = raw
        for prefix in _NAME_PREFIXES:
            if token.startswith(prefix) and len(token) > len(prefix):
                token = token[len(prefix):]
                break
        if len(token) >= 2:
            tokens.append(token)
    return tokens


def _fraction_found(tokens: list[str], norm_text: str) -> float:
    """สัดส่วนของ token ที่เจอในข้อความ — แต่ละ token ให้คะแนนตามความคล้าย (fuzzy)"""
    if not tokens:
        return 0.0
    total = sum(_fuzzy_hit(t, norm_text) for t in tokens if _norm(t))
    return total / len(tokens)


def _activity_score(activity_name: str, norm_text: str) -> float:
    """ชื่อกิจกรรมไทยเขียนติดกัน จึงเทียบทั้งก้อนแบบ fuzzy ก่อน แล้วค่อยลองแยกคำ"""
    whole = _fuzzy_hit(activity_name, norm_text)
    if whole > 0:
        return whole
    tokens = [t for t in (activity_name or "").split() if len(t) >= 3]
    return _fraction_found(tokens, norm_text)


def _date_score(start_at: Optional[datetime], text: str) -> float:
    """1.0 if the activity's year (Gregorian or Buddhist) appears in the text."""
    if start_at is None:
        return 0.0
    years = {str(start_at.year), str(start_at.year + 543)}
    return 1.0 if any(y in (text or "") for y in years) else 0.0


def compute_match_score(
    text: str, student: Optional[Student], activity: Optional[Activity]
) -> float:
    """Score (0-1) how well the OCR text matches the expected student/activity."""
    norm = _norm(text)
    name = _fraction_found(_name_tokens(student.full_name) if student else [], norm)
    activity_name = activity.name if activity else ""
    act = _activity_score(activity_name, norm)
    date = _date_score(activity.start_at if activity else None, text)
    return round(_W_NAME * name + _W_ACTIVITY * act + _W_DATE * date, 4)


# ประเภทหลักฐานที่ OCR อนุมัติอัตโนมัติได้ — OCR ยืนยันได้แค่ "งานจัดจริง" จากข้อความบนใบ
# ยืนยันตัวตนคนในภาพถ่ายหน้าแบนเนอร์ไม่ได้ ภาพถ่าย/อื่น ๆ จึงต้องให้คนตรวจเสมอ
AUTO_APPROVABLE_KINDS = (EvidenceKind.certificate,)


def auto_approval_allowed(raw_file: RawFile) -> bool:
    """ไฟล์นี้เข้าเส้นทาง auto_approved ได้ไหม (ตามประเภทหลักฐาน)

    null = ไฟล์ก่อนมีฟิลด์ประเภท → ถือเป็น certificate คงพฤติกรรมเดิม
    """
    return (raw_file.evidence_kind or EvidenceKind.certificate) in AUTO_APPROVABLE_KINDS


def process_participation_evidence(
    session: Session,
    ocr: OcrEngine,
    storage: ObjectStorage,
    participation_id: int,
) -> Optional[SilverEvidenceOcr]:
    """Run the Silver OCR step for a participation's latest evidence file.

    Decision (human-in-the-loop):
    * duplicate file (same checksum as an earlier, still-active proof — see
      :func:`find_duplicate`) -> ``flagged``, never auto-approved.
    * evidence is a certificate (see :func:`auto_approval_allowed` — photos/other
      always go to review, even with a perfect score) AND OCR confident AND text
      matches the student/activity well AND the
      participation is still pending -> ``auto_approved``: the system approves it
      and derives hours from ``activity.hours`` (same rules A2/A3 as a human
      reviewer — approval still requires evidence, hours never come from OCR).
    * otherwise -> ``needs_review`` (stays pending for staff).

    Returns the persisted `SilverEvidenceOcr` row, or None if there is no
    evidence file to process.
    """
    raw_file = _latest_raw_file(session, participation_id)
    if raw_file is None:
        return None

    participation = session.get(Participation, participation_id)
    student = session.get(Student, participation.student_id) if participation else None
    activity = session.get(Activity, participation.activity_id) if participation else None

    text, confidence = _extract_text(ocr, storage, raw_file)
    duplicate = find_duplicate(session, raw_file, text)
    match_score = compute_match_score(text, student, activity)

    decision = OcrDecision.needs_review
    if duplicate is not None:
        decision = OcrDecision.flagged
    elif (
        participation is not None
        # ภาพถ่าย/อื่น ๆ ไม่มีทางถึง auto_approved — OCR/dedup ยังรันครบ แต่คำตัดสินเป็น needs_review
        and auto_approval_allowed(raw_file)
        and participation.evidence_status == EvidenceStatus.pending
        and confidence >= settings.ocr_auto_confidence
        and match_score >= settings.ocr_auto_match
    ):
        decision = OcrDecision.auto_approved
        # Reuse the existing approval rules: evidence exists (raw_file), and hours
        # are taken from the activity — never from the OCR output.
        if activity is not None:
            apply_approval(session, participation, activity)
        else:
            participation.evidence_status = EvidenceStatus.approved
            participation.hours_earned = 0
        session.add(participation)

    row = SilverEvidenceOcr(
        raw_file_id=raw_file.id,
        participation_id=participation_id,
        extracted_text=text,
        ocr_confidence=confidence,
        match_score=match_score,
        decision=decision,
        is_duplicate=duplicate is not None,
        duplicate_of_participation_id=duplicate.participation_id if duplicate else None,
        duplicate_reason=duplicate.reason if duplicate else None,
        match_kind=duplicate.match_kind if duplicate else None,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


def process_evidence_in_background(participation_id: int) -> None:
    """Fire-and-forget OCR processing after an upload.

    Runs in its own DB session (the request's session is already closed by the
    time a background task runs) and swallows all errors — OCR is an assist and
    must never break the upload path.
    """
    from app.database import engine
    from app.ocr import get_ocr
    from app.storage import get_storage

    try:
        with Session(engine) as session:
            process_participation_evidence(session, get_ocr(), get_storage(), participation_id)
    except Exception as exc:  # noqa: BLE001 - best effort
        logger.warning(
            "OCR background processing failed for participation %s: %s", participation_id, exc
        )
