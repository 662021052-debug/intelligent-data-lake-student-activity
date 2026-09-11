"""Silver layer — clean/verify Bronze evidence with OCR.

Phase 13 builds the foundation: take the latest Bronze file for a participation,
run OCR, detect duplicates by checksum, and persist one `silver_evidence_ocr`
row. The match-scoring and auto-approval decision are added in Phase 14 — for now
every non-duplicate result is left as `needs_review` (human-in-the-loop).
"""
from __future__ import annotations

import logging
import re
from datetime import datetime
from difflib import SequenceMatcher
from typing import Optional

from sqlmodel import Session, select

from app.approval import apply_approval
from app.config import settings
from app.models import (
    Activity,
    EvidenceStatus,
    OcrDecision,
    Participation,
    RawFile,
    SilverEvidenceOcr,
    Student,
)
from app.ocr import OcrEngine
from app.storage import ObjectStorage

logger = logging.getLogger("uvicorn.error")


def _latest_raw_file(session: Session, participation_id: int) -> Optional[RawFile]:
    """The most recent Bronze file for a participation (Bronze is append-only)."""
    return session.exec(
        select(RawFile)
        .where(RawFile.participation_id == participation_id)
        .order_by(RawFile.id.desc())
    ).first()


def _is_duplicate(session: Session, raw_file: RawFile) -> bool:
    """True if this exact file (same checksum) already belongs to an APPROVED
    participation — a sign the student reused someone else's / an earlier proof."""
    others = session.exec(
        select(RawFile).where(
            RawFile.checksum == raw_file.checksum,
            RawFile.id != raw_file.id,
        )
    ).all()
    for other in others:
        if other.participation_id is None:
            continue
        participation = session.get(Participation, other.participation_id)
        if participation and participation.evidence_status == EvidenceStatus.approved:
            return True
    return False


def _extract_text(ocr: OcrEngine, storage: ObjectStorage, raw_file: RawFile) -> tuple[str, float]:
    """Run OCR on an image Bronze file. Non-images (e.g. PDF) are not OCR'd here
    and fall through to needs_review."""
    if not raw_file.content_type.startswith("image/"):
        return ("", 0.0)
    try:
        image_bytes = storage.get_object_bytes(raw_file.bucket, raw_file.object_key)
        return ocr.run_ocr(image_bytes)
    except Exception:  # noqa: BLE001 - OCR/storage failure must not crash the pipeline
        return ("", 0.0)


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


def process_participation_evidence(
    session: Session,
    ocr: OcrEngine,
    storage: ObjectStorage,
    participation_id: int,
) -> Optional[SilverEvidenceOcr]:
    """Run the Silver OCR step for a participation's latest evidence file.

    Decision (human-in-the-loop):
    * duplicate file (checksum of an already-approved proof) -> ``flagged``,
      never auto-approved.
    * OCR confident AND text matches the student/activity well AND the
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
    duplicate = _is_duplicate(session, raw_file)
    match_score = compute_match_score(text, student, activity)

    decision = OcrDecision.needs_review
    if duplicate:
        decision = OcrDecision.flagged
    elif (
        participation is not None
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
        is_duplicate=duplicate,
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
