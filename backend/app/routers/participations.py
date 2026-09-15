import hashlib
import io
import re
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, Query, UploadFile
from fastapi.responses import StreamingResponse
from sqlmodel import Session, func, select

from app import silver
from app.approval import apply_approval, clear_approval
from app.auth import get_current_user, require_writer
from app.config import settings
from app.database import get_session
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    OcrDecision,
    Participation,
    ParticipationCreate,
    ParticipationRead,
    ParticipationUpdate,
    RawFile,
    SilverEvidenceOcr,
    SilverEvidenceOcrRead,
    Student,
    User,
    UserRole,
)
from app.checkin import checkin_window, normalize_token
from app.timeutil import now_th_naive
from app.ocr import OcrEngine, get_ocr
from app.models import EvidenceKind
from app.phash import compute_phash
from app.schemas import Page, ParticipationCheckin, ParticipationRegister
from app.storage import ObjectStorage, get_storage

router = APIRouter(
    prefix="/participations", tags=["participations"], dependencies=[Depends(get_current_user)]
)

ALLOWED_EVIDENCE_CONTENT_TYPES = {"image/jpeg", "image/png", "application/pdf"}
MAX_EVIDENCE_BYTES = 10 * 1024 * 1024  # 10 MB


def _owned_activity_ids(current_user: User):
    return select(Activity.id).where(Activity.created_by == current_user.id)


def _latest_evidence_map(session: Session, participation_ids: list[int]) -> dict[int, datetime]:
    """Map participation_id -> most recent evidence upload time (Bronze ingest time)."""
    if not participation_ids:
        return {}
    rows = session.exec(
        select(RawFile.participation_id, func.max(RawFile.ingested_at))
        .where(RawFile.participation_id.in_(participation_ids))
        .group_by(RawFile.participation_id)
    ).all()
    return {pid: uploaded_at for pid, uploaded_at in rows if pid is not None}


def _latest_evidence_kind_map(session: Session, participation_ids: list[int]) -> dict[int, "EvidenceKind"]:
    """Map participation_id -> ประเภทของไฟล์หลักฐานล่าสุด (null = ไฟล์ก่อนมีประเภท ถือเป็น certificate)

    คิวตรวจแสดงป้าย "ภาพถ่าย — ต้องตรวจด้วยตา" ได้โดยไม่ต้องยิงทีละแถว
    """
    if not participation_ids:
        return {}
    rows = session.exec(
        select(RawFile.participation_id, RawFile.evidence_kind)
        .where(RawFile.participation_id.in_(participation_ids))
        .order_by(RawFile.participation_id, RawFile.id.desc())
    ).all()
    kinds: dict[int, EvidenceKind] = {}
    for pid, kind in rows:
        if pid is not None and pid not in kinds:
            kinds[pid] = kind or EvidenceKind.certificate
    return kinds


def _activity_names(session: Session, activity_ids: list[int]) -> dict[int, str]:
    """Map activity_id -> name (so ParticipationRead can show a real name, not #id)."""
    ids = {aid for aid in activity_ids if aid is not None}
    if not ids:
        return {}
    rows = session.exec(select(Activity.id, Activity.name).where(Activity.id.in_(ids))).all()
    return {aid: name for aid, name in rows}


def _student_labels(session: Session, student_ids: list[int]) -> dict[int, tuple[str, str]]:
    """Map student.id -> (full_name, รหัสนิสิต) — คิวตรวจหลักฐานต้องบอกว่าเป็นของใคร
    โดยไม่ต้องโหลดนิสิตทั้งระบบ (2,000+ คน) มาทำตารางแปลง id เอง"""
    ids = {sid for sid in student_ids if sid is not None}
    if not ids:
        return {}
    rows = session.exec(
        select(Student.id, Student.full_name, Student.student_id).where(Student.id.in_(ids))
    ).all()
    return {sid: (name, code) for sid, name, code in rows}


def _latest_ocr_map(
    session: Session, participation_ids: list[int]
) -> dict[int, SilverEvidenceOcr]:
    """Map participation_id -> its most recent OCR (Silver) result."""
    ids = [pid for pid in participation_ids if pid is not None]
    if not ids:
        return {}
    rows = session.exec(
        select(SilverEvidenceOcr).where(SilverEvidenceOcr.participation_id.in_(ids))
    ).all()
    latest: dict[int, SilverEvidenceOcr] = {}
    for row in rows:
        current = latest.get(row.participation_id)
        if current is None or row.id > current.id:
            latest[row.participation_id] = row
    return latest


def _to_read(
    participation: Participation,
    uploaded_at: Optional[datetime],
    activity_name: Optional[str],
    ocr: Optional[SilverEvidenceOcr] = None,
    student: Optional[tuple[str, str]] = None,
    evidence_kind: Optional[EvidenceKind] = None,
) -> ParticipationRead:
    return ParticipationRead(
        **participation.model_dump(),
        activity_name=activity_name,
        evidence_kind=evidence_kind,
        student_name=student[0] if student else None,
        student_code=student[1] if student else None,
        has_evidence=uploaded_at is not None,
        evidence_uploaded_at=uploaded_at,
        has_ocr=ocr is not None,
        ocr_decision=ocr.decision if ocr else None,
        ocr_match_score=ocr.match_score if ocr else None,
        ocr_confidence=ocr.ocr_confidence if ocr else None,
        ocr_duplicate_reason=ocr.duplicate_reason if ocr else None,
        ocr_match_kind=ocr.match_kind if ocr else None,
    )


def _read_with_evidence(session: Session, participation: Participation) -> ParticipationRead:
    uploaded_at = _latest_evidence_map(session, [participation.id]).get(participation.id)
    activity_name = _activity_names(session, [participation.activity_id]).get(
        participation.activity_id
    )
    ocr = _latest_ocr_map(session, [participation.id]).get(participation.id)
    student = _student_labels(session, [participation.student_id]).get(participation.student_id)
    kind = _latest_evidence_kind_map(session, [participation.id]).get(participation.id)
    return _to_read(participation, uploaded_at, activity_name, ocr, student, evidence_kind=kind)


def _get_activity_or_404(session: Session, activity_id: int) -> Activity:
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=400, detail="activity_id does not exist")
    return activity


def _ensure_staff_owns_activity(current_user: User, activity: Activity) -> None:
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")


@router.get("", response_model=Page[ParticipationRead])
def list_participations(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=200),
    student_id: Optional[int] = None,
    activity_id: Optional[int] = None,
    evidence_status: Optional[EvidenceStatus] = None,
    has_evidence: Optional[bool] = Query(None, description="true = เฉพาะรายการที่ส่งไฟล์หลักฐานแล้ว"),
    ocr_decision: Optional[OcrDecision] = Query(None, description="ผล OCR ล่าสุดของรายการ"),
    search: Optional[str] = Query(None, description="ค้นหาจากชื่อ/รหัสนิสิต หรือชื่อกิจกรรม"),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    query = select(Participation)
    count_query = select(func.count()).select_from(Participation)

    if current_user.role == UserRole.student:
        if current_user.student_id is None:
            return Page(items=[], total=0, skip=skip, limit=limit)
        query = query.where(Participation.student_id == current_user.student_id)
        count_query = count_query.where(Participation.student_id == current_user.student_id)
    elif current_user.role == UserRole.staff:
        owned = _owned_activity_ids(current_user)
        query = query.where(Participation.activity_id.in_(owned))
        count_query = count_query.where(Participation.activity_id.in_(owned))
        if student_id is not None:
            query = query.where(Participation.student_id == student_id)
            count_query = count_query.where(Participation.student_id == student_id)
    elif student_id is not None:
        query = query.where(Participation.student_id == student_id)
        count_query = count_query.where(Participation.student_id == student_id)

    if activity_id is not None:
        query = query.where(Participation.activity_id == activity_id)
        count_query = count_query.where(Participation.activity_id == activity_id)
    if evidence_status:
        query = query.where(Participation.evidence_status == evidence_status)
        count_query = count_query.where(Participation.evidence_status == evidence_status)
    if has_evidence is not None:
        # คิวตรวจหลักฐาน: การเข้าร่วมที่ยังไม่ส่งไฟล์ไม่มีอะไรให้ตรวจ จึงกรองออกที่ backend
        with_file = Participation.id.in_(
            select(RawFile.participation_id).where(RawFile.participation_id.is_not(None))
        )
        condition = with_file if has_evidence else ~with_file
        query = query.where(condition)
        count_query = count_query.where(condition)
    if ocr_decision:
        # เทียบกับผล OCR "ล่าสุด" ของแต่ละรายการเท่านั้น — สั่งอ่านใหม่แล้วผลเดิมต้องไม่ติดมา
        latest_ids = select(func.max(SilverEvidenceOcr.id)).group_by(SilverEvidenceOcr.participation_id)
        matched = select(SilverEvidenceOcr.participation_id).where(
            SilverEvidenceOcr.id.in_(latest_ids), SilverEvidenceOcr.decision == ocr_decision
        )
        query = query.where(Participation.id.in_(matched))
        count_query = count_query.where(Participation.id.in_(matched))
    if search:
        # ตารางนี้แสดงชื่อนิสิตกับชื่อกิจกรรม จึงต้องค้นได้ทั้งสองอย่าง
        # ใช้ subquery แทน join เพื่อไม่ให้แถวซ้ำและไม่กระทบ count
        pattern = f"%{search}%"
        matched_students = select(Student.id).where(
            Student.full_name.ilike(pattern) | Student.student_id.ilike(pattern)
        )
        matched_activities = select(Activity.id).where(Activity.name.ilike(pattern))
        condition = Participation.student_id.in_(matched_students) | Participation.activity_id.in_(
            matched_activities
        )
        query = query.where(condition)
        count_query = count_query.where(condition)

    total = session.exec(count_query).one()
    # ลำดับคงที่ ไม่ให้แถวที่เพิ่งแก้ (เช่น อนุมัติหลักฐาน) ย้ายตำแหน่งในรายการ
    query = query.order_by(Participation.id)
    items = session.exec(query.offset(skip).limit(limit)).all()
    evidence = _latest_evidence_map(session, [p.id for p in items])
    names = _activity_names(session, [p.activity_id for p in items])
    ocr = _latest_ocr_map(session, [p.id for p in items])
    students = _student_labels(session, [p.student_id for p in items])
    kinds = _latest_evidence_kind_map(session, [p.id for p in items])
    reads = [
        _to_read(
            p, evidence.get(p.id), names.get(p.activity_id), ocr.get(p.id), students.get(p.student_id),
            evidence_kind=kinds.get(p.id),
        )
        for p in items
    ]
    return Page(items=reads, total=total, skip=skip, limit=limit)


@router.get("/{participation_id}", response_model=ParticipationRead)
def get_participation(
    participation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")
    if current_user.role == UserRole.student and participation.student_id != current_user.student_id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.role == UserRole.staff:
        activity = session.get(Activity, participation.activity_id)
        _ensure_staff_owns_activity(current_user, activity)
    return _read_with_evidence(session, participation)


def _ensure_student_and_activity_exist(session: Session, student_id: int, activity_id: int) -> None:
    if not session.get(Student, student_id):
        raise HTTPException(status_code=400, detail="student_id does not exist")
    if not session.get(Activity, activity_id):
        raise HTTPException(status_code=400, detail="activity_id does not exist")


@router.post("/register", response_model=ParticipationRead, status_code=201)
def register_self(
    payload: ParticipationRegister,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.student:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.student_id is None:
        raise HTTPException(status_code=403, detail="This account is not linked to a student record")

    activity = session.get(Activity, payload.activity_id)
    if not activity:
        raise HTTPException(status_code=400, detail="activity_id does not exist")
    if activity.approval_status != ApprovalStatus.approved or activity.is_hidden:
        # กิจกรรมที่ถูกซ่อน = ถูกยกเลิกในสายตานิสิต จึงสมัครใหม่ไม่ได้ (คนที่สมัคร
        # ไปแล้วยังเก็บประวัติ/ชั่วโมงไว้เหมือนเดิม)
        raise HTTPException(status_code=400, detail="กิจกรรมนี้ยังไม่เปิดรับสมัคร")
    # start_at เป็นเวลาไทยแบบไม่มีโซน (ดู app/timeutil.py) ต้องเทียบกับเวลาไทย
    # เดิมเทียบกับ utcnow() ซึ่งช้ากว่า 7 ชม. จึงสมัครได้ทั้งที่กิจกรรมเริ่มไปแล้ว
    if activity.start_at <= now_th_naive():
        raise HTTPException(status_code=400, detail="กิจกรรมนี้ปิดรับสมัครแล้ว")

    existing = session.exec(
        select(Participation).where(
            Participation.student_id == current_user.student_id,
            Participation.activity_id == payload.activity_id,
        )
    ).first()
    if existing:
        raise HTTPException(status_code=400, detail="คุณสมัครกิจกรรมนี้ไปแล้ว")

    participant_count = session.exec(
        select(func.count())
        .select_from(Participation)
        .where(Participation.activity_id == payload.activity_id)
    ).one()
    if participant_count >= activity.max_participants:
        raise HTTPException(status_code=400, detail="กิจกรรมนี้เต็มแล้ว")

    participation = Participation(
        student_id=current_user.student_id,
        activity_id=payload.activity_id,
        evidence_status=EvidenceStatus.pending,
        hours_earned=0,
    )
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return _read_with_evidence(session, participation)


@router.post("/checkin", response_model=ParticipationRead)
def checkin_with_qr(
    payload: ParticipationCheckin,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """นิสิตสแกน QR ของกิจกรรมที่หน้างาน → บันทึก `check_in_time` ทันที.

    เช็กอิน = "มาร่วมงาน" เท่านั้น ไม่ให้ชั่วโมง (กฎ D2): `hours_earned` ยังเป็น 0
    และ `evidence_status` ยังเป็น pending — ชั่วโมงยังต้องส่งหลักฐาน + เจ้าหน้าที่
    อนุมัติตามกฎ A3 เดิม
    """
    # ตัวตนมาจาก JWT อย่างเดียว → สแกนแทนกันไม่ได้ ต่อให้ได้ token เดียวกันมา
    if current_user.role != UserRole.student:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.student_id is None:
        raise HTTPException(status_code=403, detail="This account is not linked to a student record")

    token = normalize_token(payload.token)
    activity = (
        session.exec(select(Activity).where(Activity.checkin_token == token)).first()
        if token
        else None
    )
    if not activity:
        raise HTTPException(status_code=400, detail="QR ไม่ถูกต้อง")
    if activity.approval_status != ApprovalStatus.approved or activity.is_hidden:
        raise HTTPException(status_code=400, detail="กิจกรรมนี้ยังไม่เปิดให้เช็กอิน")

    # หน้าต่างเช็กอินคิดจาก start_at ซึ่งเป็นเวลาไทยแบบไม่มีโซน → เทียบกับเวลาไทย
    # (เดิมเทียบกับ utcnow() หน้าต่างจึงเปิด/ปิดช้าไป 7 ชม.) ส่วน check_in_time ที่บันทึก
    # ยังเป็น UTC ตามแบบ timestamp ของระบบ — หน้าเว็บแปลงด้วย serverTimeToLocal
    now = datetime.utcnow()
    now_th = now_th_naive()
    opens_at, closes_at = checkin_window(activity)
    if now_th < opens_at:
        raise HTTPException(status_code=400, detail="ยังไม่ถึงเวลาเช็กอิน")
    if now_th > closes_at:
        raise HTTPException(status_code=400, detail="เลยเวลาเช็กอินแล้ว")

    participation = session.exec(
        select(Participation).where(
            Participation.student_id == current_user.student_id,
            Participation.activity_id == activity.id,
        )
    ).first()

    if participation:
        if participation.check_in_time is not None:
            raise HTTPException(status_code=400, detail="คุณเช็กอินกิจกรรมนี้แล้ว")
    else:
        # walk-up: เดินมาหน้างานเลยโดยไม่ได้สมัครล่วงหน้า → สร้าง participation ให้
        participant_count = session.exec(
            select(func.count())
            .select_from(Participation)
            .where(Participation.activity_id == activity.id)
        ).one()
        if participant_count >= activity.max_participants:
            raise HTTPException(status_code=400, detail="กิจกรรมนี้เต็มแล้ว")
        participation = Participation(
            student_id=current_user.student_id,
            activity_id=activity.id,
            evidence_status=EvidenceStatus.pending,
            hours_earned=0,
        )

    participation.check_in_time = now
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return _read_with_evidence(session, participation)


@router.post("", response_model=ParticipationRead, status_code=201)
def create_participation(
    payload: ParticipationCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    _ensure_student_and_activity_exist(session, payload.student_id, payload.activity_id)
    activity = _get_activity_or_404(session, payload.activity_id)
    _ensure_staff_owns_activity(current_user, activity)

    participation = Participation.model_validate(payload)
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return _read_with_evidence(session, participation)


@router.put("/{participation_id}", response_model=ParticipationRead)
def update_participation(
    participation_id: int,
    payload: ParticipationUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    current_activity = _get_activity_or_404(session, participation.activity_id)
    _ensure_staff_owns_activity(current_user, current_activity)

    data = payload.model_dump(exclude_unset=True)

    if "evidence_status" in data:
        new_status = data["evidence_status"]
        if new_status == EvidenceStatus.approved:
            # A3: cannot approve without evidence in the Bronze layer.
            has_evidence = (
                session.exec(
                    select(RawFile.id)
                    .where(RawFile.participation_id == participation.id)
                    .limit(1)
                ).first()
                is not None
            )
            if not has_evidence:
                raise HTTPException(
                    status_code=400, detail="อนุมัติไม่ได้: ยังไม่มีหลักฐานการเข้าร่วม"
                )
            # A2: hours are derived from the activity, never typed in by a reviewer.
            apply_approval(session, participation, current_activity)
        else:
            # pending / rejected -> no hours counted (E4)
            clear_approval(participation, new_status)

    if "check_in_time" in data:
        participation.check_in_time = data["check_in_time"]

    session.add(participation)
    session.commit()
    session.refresh(participation)
    return _read_with_evidence(session, participation)


@router.delete("/{participation_id}", status_code=204)
def delete_participation(
    participation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    if current_user.role == UserRole.student:
        if participation.student_id != current_user.student_id:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
        if participation.check_in_time is not None or participation.evidence_status == EvidenceStatus.approved:
            raise HTTPException(
                status_code=400, detail="ไม่สามารถยกเลิกได้ เนื่องจากเช็กอินหรืออนุมัติแล้ว"
            )
    else:
        activity = _get_activity_or_404(session, participation.activity_id)
        _ensure_staff_owns_activity(current_user, activity)

    session.delete(participation)
    session.commit()
    return None


def _sanitize_filename(name: str) -> str:
    """Keep a readable basename for the object key; strip any path components."""
    base = name.replace("\\", "/").split("/")[-1].strip() or "upload"
    return re.sub(r"[^A-Za-z0-9._\-฀-๿]", "_", base)[:120]


def _ensure_can_manage_evidence(session: Session, participation: Participation, current_user: User):
    """Owning student, the staff who owns the activity, or admin may access evidence."""
    if current_user.role == UserRole.student:
        if participation.student_id != current_user.student_id:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
    elif current_user.role == UserRole.staff:
        activity = session.get(Activity, participation.activity_id)
        _ensure_staff_owns_activity(current_user, activity)


@router.post("/{participation_id}/evidence", response_model=ParticipationRead, status_code=201)
def upload_evidence(
    participation_id: int,
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    # บังคับเลือก (หน้าอัปโหลดมีตัวเลือกแล้ว) — ไม่ส่งมา หรือค่านอก 3 ค่า → 422 ไม่มีค่าเริ่มเงียบ ๆ
    # ถ้าปล่อย default = certificate ภาพถ่ายที่นิสิตไม่ได้เลือกประเภทจะหลุดเข้าเส้นทาง auto ได้
    evidence_kind: EvidenceKind = Form(
        ...,
        description="certificate = เกียรติบัตร/ใบรับรอง · photo = ภาพถ่ายกิจกรรม · other = อื่น ๆ "
        "(photo/other ไม่อนุมัติอัตโนมัติ ต้องให้เจ้าหน้าที่ตรวจ)",
    ),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    storage: ObjectStorage = Depends(get_storage),
):
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    # Upload is a student action; a student may only submit for their own participation.
    # Admins may also upload (e.g. on a student's behalf); staff cannot.
    if current_user.role == UserRole.student:
        if participation.student_id != current_user.student_id:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
    elif current_user.role != UserRole.admin:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    if participation.evidence_status == EvidenceStatus.approved:
        raise HTTPException(
            status_code=400, detail="อนุมัติแล้ว ไม่สามารถอัปโหลดหลักฐานทับได้"
        )

    if file.content_type not in ALLOWED_EVIDENCE_CONTENT_TYPES:
        raise HTTPException(
            status_code=400,
            detail="รองรับเฉพาะไฟล์ภาพ (JPEG/PNG) หรือ PDF เท่านั้น",
        )

    # Determine size without loading an oversized file fully into memory.
    file.file.seek(0, io.SEEK_END)
    size_bytes = file.file.tell()
    file.file.seek(0)
    if size_bytes > MAX_EVIDENCE_BYTES:
        raise HTTPException(status_code=413, detail="ไฟล์ใหญ่เกิน 10 MB")
    if size_bytes == 0:
        raise HTTPException(status_code=400, detail="ไฟล์ว่างเปล่า")

    data = file.file.read()
    checksum = hashlib.sha256(data).hexdigest()
    # ชั้นที่สองของการกันไฟล์ซ้ำ (ภาพเกือบเหมือน) — ภาพเท่านั้น ถอดไม่ได้ก็เป็น None ไม่ล้ม
    phash = compute_phash(data, file.content_type)

    now = datetime.utcnow()
    original_filename = file.filename or "upload"
    object_key = (
        f"evidence/year={now:%Y}/month={now:%m}"
        f"/activity_id={participation.activity_id}"
        f"/participation_id={participation.id}"
        f"/{uuid.uuid4().hex}_{_sanitize_filename(original_filename)}"
    )
    bucket = settings.minio_bucket_bronze

    # Bronze is immutable: always write a NEW object; never overwrite an existing one.
    storage.ensure_bucket(bucket)
    storage.upload_object(bucket, object_key, data, file.content_type)

    raw_file = RawFile(
        bucket=bucket,
        object_key=object_key,
        original_filename=original_filename,
        content_type=file.content_type,
        size_bytes=size_bytes,
        checksum=checksum,
        phash=phash,
        evidence_kind=evidence_kind,
        source_system="student_upload",
        uploaded_by=current_user.id,
        ingested_at=now,
        participation_id=participation.id,
    )
    session.add(raw_file)

    # New evidence (re)enters the review queue.
    participation.evidence_status = EvidenceStatus.pending
    session.add(participation)
    session.commit()
    session.refresh(participation)

    # Kick off OCR (Silver layer) without blocking the upload response.
    background_tasks.add_task(silver.process_evidence_in_background, participation.id)
    return _read_with_evidence(session, participation)


def _ocr_read(
    session: Session, row: SilverEvidenceOcr, current_user: User
) -> SilverEvidenceOcrRead:
    """ผล OCR + บริบทของใบต้นทางเมื่อไฟล์ซ้ำ (ชื่อ/รหัสนิสิต · กิจกรรม · สถานะ)

    เจ้าหน้าที่ต้องเห็นว่าซ้ำกับใครถึงจะตัดสินใจได้ แม้ใบต้นทางอยู่ในกิจกรรมที่ตัวเองไม่ได้
    เป็นเจ้าของ — แต่เปิดหน้าตรวจของใบนั้นได้เฉพาะเมื่อมีสิทธิ์ ([duplicate_of_viewable])
    role student ไม่ได้บริบทนี้ เพราะเป็นข้อมูลของนิสิตคนอื่น
    """
    read = SilverEvidenceOcrRead(**row.model_dump())
    raw_file = session.get(RawFile, row.raw_file_id)
    read.evidence_kind = (raw_file.evidence_kind if raw_file else None) or EvidenceKind.certificate
    original_id = row.duplicate_of_participation_id
    if original_id is None or current_user.role == UserRole.student:
        return read
    original = session.get(Participation, original_id)
    if original is None:
        return read

    student = session.get(Student, original.student_id)
    activity = session.get(Activity, original.activity_id)
    read.duplicate_of_student_name = student.full_name if student else None
    read.duplicate_of_student_code = student.student_id if student else None
    read.duplicate_of_activity_name = activity.name if activity else None
    read.duplicate_of_evidence_status = original.evidence_status
    read.duplicate_of_viewable = current_user.role == UserRole.admin or (
        activity is not None and activity.created_by == current_user.id
    )
    return read


@router.post("/{participation_id}/evidence/process", response_model=SilverEvidenceOcrRead)
def process_evidence(
    participation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    ocr: OcrEngine = Depends(get_ocr),
    storage: ObjectStorage = Depends(get_storage),
):
    """Run (or re-run) the Silver OCR pipeline for a participation's evidence.

    Reviewer action: only the staff who owns the activity, or an admin, may
    trigger it — students cannot auto-approve their own evidence.
    """
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    if current_user.role == UserRole.student:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.role == UserRole.staff:
        activity = session.get(Activity, participation.activity_id)
        _ensure_staff_owns_activity(current_user, activity)

    row = silver.process_participation_evidence(session, ocr, storage, participation_id)
    if row is None:
        raise HTTPException(status_code=400, detail="ยังไม่มีหลักฐานให้ประมวลผล")
    return _ocr_read(session, row, current_user)


@router.get("/{participation_id}/ocr", response_model=SilverEvidenceOcrRead)
def get_ocr_result(
    participation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """Latest OCR/Silver result for a participation (for the staff review UI)."""
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    _ensure_can_manage_evidence(session, participation, current_user)

    row = session.exec(
        select(SilverEvidenceOcr)
        .where(SilverEvidenceOcr.participation_id == participation_id)
        .order_by(SilverEvidenceOcr.id.desc())
    ).first()
    if not row:
        raise HTTPException(status_code=404, detail="ยังไม่มีผลการประมวลผล OCR")
    return _ocr_read(session, row, current_user)


@router.get("/{participation_id}/evidence")
def get_evidence(
    participation_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
    storage: ObjectStorage = Depends(get_storage),
):
    participation = session.get(Participation, participation_id)
    if not participation:
        raise HTTPException(status_code=404, detail="Participation not found")

    _ensure_can_manage_evidence(session, participation, current_user)

    raw_file = session.exec(
        select(RawFile)
        .where(RawFile.participation_id == participation_id)
        .order_by(RawFile.ingested_at.desc(), RawFile.id.desc())
    ).first()
    if not raw_file:
        raise HTTPException(status_code=404, detail="ยังไม่มีหลักฐานสำหรับการเข้าร่วมนี้")

    try:
        data = storage.get_object_bytes(raw_file.bucket, raw_file.object_key)
    except FileNotFoundError:
        raise HTTPException(status_code=404, detail="ไม่พบไฟล์ในที่จัดเก็บ")

    # The bucket is never public; the backend brokers access after the checks above.
    headers = {
        "Content-Disposition": f'inline; filename="{_sanitize_filename(raw_file.original_filename)}"'
    }
    return StreamingResponse(
        io.BytesIO(data), media_type=raw_file.content_type, headers=headers
    )
