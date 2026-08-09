from datetime import datetime
from typing import Optional

import logging

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select

from app.auth import get_current_user, require_admin, require_writer
from app.models import (
    Activity,
    ActivityCreate,
    ActivityRead,
    ActivityUpdate,
    ApprovalStatus,
    Participation,
    ParticipationRead,
    User,
    UserRole,
)
from app.database import get_session
from app.timeutil import TZ_TH, today_th
from app.routers.participations import (
    _activity_names,
    _latest_evidence_map,
    _latest_ocr_map,
    _to_read as _participation_to_read,
)
from app.checkin import checkin_window, qr_payload
from app.schemas import ActivityCheckinQr, Page

router = APIRouter(prefix="/activities", tags=["activities"], dependencies=[Depends(get_current_user)])

logger = logging.getLogger(__name__)

BACKDATED_DETAIL = "ไม่สามารถตั้งวันเวลากิจกรรมเป็นอดีตได้"


def _validate_not_backdated(start_at: datetime) -> None:
    """กันตั้งกิจกรรมย้อนหลัง — วันจัดกิจกรรมต้องเป็นวันนี้หรืออนาคตเท่านั้น

    เทียบระดับ "วัน" ไม่ใช่ระดับวินาที เพื่อให้เจ้าหน้าที่ยังบันทึกกิจกรรมของ
    เช้าวันนี้ได้ตอนบ่าย และให้ตรงกับ date picker ฝั่ง UI ที่ล็อก `firstDate`
    ไว้แค่ระดับวันเหมือนกัน — ไม่งั้นผู้ใช้จะเลือกวันได้แต่กดบันทึกไม่ผ่าน

    ค่าที่ไม่มีโซนเวลาถือเป็นเวลาไทย เพราะ start_at ของกิจกรรมมาจากที่ผู้ใช้กรอก
    (ต่างจาก timestamp ที่ระบบเขียนเองซึ่งเป็น UTC) ถ้าไปตีความเป็น UTC วันจะ
    เพี้ยนไปหนึ่งวันในช่วงหัวค่ำ
    """
    start_th = start_at.astimezone(TZ_TH) if start_at.tzinfo else start_at.replace(tzinfo=TZ_TH)
    if start_th.date() < datetime.now(TZ_TH).date():
        raise HTTPException(status_code=400, detail=BACKDATED_DETAIL)


def _ensure_visible(activity: Activity, current_user: User) -> None:
    """Raise 403 if `current_user` isn't allowed to see/manage this activity."""
    if current_user.role == UserRole.student:
        # กิจกรรมที่ถูกซ่อน = ถูก "ลบ" ในสายตานิสิต แม้ประวัติการเข้าร่วมจะยังอยู่
        if activity.approval_status != ApprovalStatus.approved or activity.is_hidden:
            raise HTTPException(status_code=403, detail="Insufficient permissions")
    elif current_user.role == UserRole.staff:
        if activity.created_by != current_user.id:
            raise HTTPException(status_code=403, detail="Insufficient permissions")


def _participant_counts(session: Session, activity_ids: list[int]) -> dict[int, int]:
    if not activity_ids:
        return {}
    rows = session.exec(
        select(Participation.activity_id, func.count())
        .where(Participation.activity_id.in_(activity_ids))
        .group_by(Participation.activity_id)
    ).all()
    return dict(rows)


def _to_read(activity: Activity, participant_count: int = 0) -> ActivityRead:
    return ActivityRead(**activity.model_dump(), participant_count=participant_count)


def _to_read_single(session: Session, activity: Activity) -> ActivityRead:
    count = _participant_counts(session, [activity.id]).get(activity.id, 0)
    return _to_read(activity, count)


@router.get("", response_model=Page[ActivityRead])
def list_activities(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=200),
    activity_type: Optional[str] = None,
    subcategory_id: Optional[int] = None,
    is_required: Optional[bool] = None,
    search: Optional[str] = Query(None, description="ค้นหาจากชื่อกิจกรรม"),
    upcoming: bool = Query(
        False,
        description="เอาเฉพาะกิจกรรมที่ยังไม่ผ่านวันจัด และเรียงจากวันที่ใกล้ที่สุดก่อน",
    ),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    query = select(Activity)
    count_query = select(func.count()).select_from(Activity)

    if current_user.role == UserRole.student:
        query = query.where(Activity.approval_status == ApprovalStatus.approved)
        count_query = count_query.where(Activity.approval_status == ApprovalStatus.approved)
        # กิจกรรมที่ซ่อนไว้ต้องหายไปจากฝั่งนิสิตทั้งหมด (staff/admin ยังเห็นพร้อม badge)
        query = query.where(Activity.is_hidden == False)  # noqa: E712
        count_query = count_query.where(Activity.is_hidden == False)  # noqa: E712
    elif current_user.role == UserRole.staff:
        query = query.where(Activity.created_by == current_user.id)
        count_query = count_query.where(Activity.created_by == current_user.id)

    if activity_type:
        query = query.where(Activity.activity_type == activity_type)
        count_query = count_query.where(Activity.activity_type == activity_type)
    if subcategory_id is not None:
        query = query.where(Activity.subcategory_id == subcategory_id)
        count_query = count_query.where(Activity.subcategory_id == subcategory_id)
    if is_required is not None:
        query = query.where(Activity.is_required == is_required)
        count_query = count_query.where(Activity.is_required == is_required)
    if search:
        pattern = f"%{search}%"
        query = query.where(Activity.name.ilike(pattern))
        count_query = count_query.where(Activity.name.ilike(pattern))
    if upcoming:
        # ตัดที่วัน ไม่ใช่ที่นาที — กิจกรรมของเช้าวันนี้ยังนับว่า "ยังไม่ผ่าน" ให้ตรงกับ
        # กฎกันย้อนหลังตอนสร้าง/แก้ไข ที่เทียบระดับวันเหมือนกัน
        today_start = datetime.combine(today_th(), datetime.min.time())
        query = query.where(Activity.start_at >= today_start)
        count_query = count_query.where(Activity.start_at >= today_start)

    total = session.exec(count_query).one()
    if upcoming:
        # รายการ "ที่กำลังจะถึง" ต้องเอาอันที่ใกล้ที่สุดขึ้นก่อน ไม่งั้นนิสิตต้องเลื่อน
        # ผ่านกิจกรรมของอีกหลายเดือนข้างหน้ากว่าจะเจออันที่สมัครทัน
        query = query.order_by(Activity.start_at.asc(), Activity.id.asc())
    else:
        # ลำดับคงที่ ไม่ให้แถวที่เพิ่งแก้ (เช่น อนุมัติกิจกรรม) ย้ายตำแหน่งในรายการ
        query = query.order_by(Activity.start_at.desc(), Activity.id.desc())
    activities = session.exec(query.offset(skip).limit(limit)).all()
    counts = _participant_counts(session, [a.id for a in activities])
    items = [_to_read(a, counts.get(a.id, 0)) for a in activities]
    return Page(items=items, total=total, skip=skip, limit=limit)


@router.get("/{activity_id}", response_model=ActivityRead)
def get_activity(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    _ensure_visible(activity, current_user)
    return _to_read_single(session, activity)


@router.post("", response_model=ActivityRead, status_code=201)
def create_activity(
    payload: ActivityCreate,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    _validate_not_backdated(payload.start_at)
    activity = Activity.model_validate(payload)
    activity.created_by = current_user.id
    if current_user.role == UserRole.admin:
        activity.approval_status = ApprovalStatus.approved
        activity.approved_by = current_user.id
        activity.approved_at = datetime.utcnow()
    else:
        activity.approval_status = ApprovalStatus.pending
        activity.approved_by = None
        activity.approved_at = None
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return _to_read(activity, 0)


@router.put("/{activity_id}", response_model=ActivityRead)
def update_activity(
    activity_id: int,
    payload: ActivityUpdate,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    data = payload.model_dump(exclude_unset=True)
    new_start: Optional[datetime] = data.get("start_at")
    # ตรวจเฉพาะตอน "ย้ายวัน" จริง ๆ — ฟอร์มแก้ไขส่งทุกฟิลด์กลับมาเสมอรวมทั้ง
    # start_at เดิม ถ้าตรวจทุกครั้งกิจกรรมที่จัดไปแล้วจะแก้ชื่อ/สถานที่ไม่ได้เลย
    # ทั้งที่กติกาห้ามแค่การเปลี่ยนวันไปเป็นอดีต
    if new_start is not None and new_start.replace(microsecond=0) != activity.start_at.replace(
        microsecond=0
    ):
        _validate_not_backdated(new_start)

    for key, value in data.items():
        setattr(activity, key, value)

    if current_user.role == UserRole.staff:
        # any edit by the owning staff needs re-approval
        activity.approval_status = ApprovalStatus.pending
        activity.approved_by = None
        activity.approved_at = None

    session.add(activity)
    session.commit()
    session.refresh(activity)
    return _to_read_single(session, activity)


@router.patch("/{activity_id}/approve", response_model=ActivityRead, dependencies=[Depends(require_admin)])
def approve_activity(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_admin),
):
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")

    activity.approval_status = ApprovalStatus.approved
    activity.approved_by = current_user.id
    activity.approved_at = datetime.utcnow()
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return _to_read_single(session, activity)


@router.get("/{activity_id}/participations", response_model=list[ParticipationRead])
def list_activity_participations(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    parts = session.exec(
        select(Participation).where(Participation.activity_id == activity_id)
    ).all()
    # Build full reads so has_evidence / has_ocr / ocr_* are populated (returning
    # raw ORM rows would leave them at their defaults).
    evidence = _latest_evidence_map(session, [p.id for p in parts])
    names = _activity_names(session, [p.activity_id for p in parts])
    ocr = _latest_ocr_map(session, [p.id for p in parts])
    return [
        _participation_to_read(p, evidence.get(p.id), names.get(p.activity_id), ocr.get(p.id))
        for p in parts
    ]


@router.get("/{activity_id}/checkin-qr", response_model=ActivityCheckinQr)
def get_checkin_qr(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    """token/payload สำหรับให้เจ้าหน้าที่เจ้าของกิจกรรม (หรือ admin) เอาไปสร้าง QR
    แสดงที่หน้างาน — นิสิตเรียกไม่ได้ ไม่งั้นก็สแกนเองจากที่บ้านได้"""
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    opens_at, closes_at = checkin_window(activity)
    return ActivityCheckinQr(
        activity_id=activity.id,
        activity_name=activity.name,
        token=activity.checkin_token,
        qr_payload=qr_payload(activity),
        start_at=activity.start_at,
        checkin_opens_at=opens_at,
        checkin_closes_at=closes_at,
    )


@router.delete("/{activity_id}", status_code=204)
def delete_activity(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    """ลบกิจกรรม — แต่ถ้ามีคนเข้าร่วมไปแล้วจะ "ซ่อน" แทนการลบจริง

    ลบกิจกรรมที่มีผู้เข้าร่วมทิ้งจะลากชั่วโมงที่นิสิตได้ไปแล้วหายตามไปด้วย
    (`gold_student_hours` คำนวณสดจาก participation) ซึ่งกู้คืนไม่ได้ กรณีนั้นจึงแค่
    ตั้ง `is_hidden` แทน: นิสิตไม่เห็นและสมัครใหม่ไม่ได้ แต่ประวัติ/ชั่วโมง/หลักฐานเดิม
    อยู่ครบ และ staff/admin ยังเห็นพร้อม badge "ซ่อนอยู่" กด "เลิกซ่อน" กลับมาได้

    กิจกรรมที่ยังไม่มีใครเข้าร่วมเลยไม่มีอะไรให้เสีย จึงลบทิ้งได้จริง (หลักฐานทั้งสาย
    Bronze → Silver ผูกกับ participation ทั้งหมด ไม่มี participation ก็ไม่มีอะไรค้าง)
    """
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    has_participants = session.exec(
        select(Participation).where(Participation.activity_id == activity_id)
    ).first()
    if has_participants:
        activity.is_hidden = True
        session.add(activity)
        session.commit()
        return None

    session.delete(activity)
    try:
        session.commit()
    except IntegrityError:
        # ยังมีตารางอื่นชี้มาที่กิจกรรมนี้อยู่ — ตอบให้ผู้ใช้อ่านรู้เรื่อง ดีกว่า
        # ปล่อย 500 ดิบ ซึ่ง CORS ไม่ได้แนบหัวข้อไปด้วยจนหน้าเว็บเข้าใจผิดว่า
        # "เชื่อมต่อเซิร์ฟเวอร์ไม่ได้"
        session.rollback()
        logger.exception("ลบกิจกรรม %s ไม่สำเร็จ: ยังมีข้อมูลอื่นอ้างถึงอยู่", activity_id)
        raise HTTPException(
            status_code=400,
            detail="ลบกิจกรรมไม่ได้ เพราะยังมีข้อมูลอื่นอ้างถึงอยู่ กรุณาติดต่อผู้ดูแลระบบ",
        )

    return None


@router.patch("/{activity_id}/unhide", response_model=ActivityRead)
def unhide_activity(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    """เลิกซ่อนกิจกรรมที่เคยกด "ลบ" ไปตอนมีผู้เข้าร่วมแล้ว — กู้กลับมาให้นิสิตเห็นได้

    สถานะอนุมัติเดิมไม่ถูกแตะ: กิจกรรมที่อนุมัติแล้วกลับมาแสดงทันที ส่วนที่ยังรออนุมัติ
    ก็ยังรอต่อเหมือนก่อนถูกซ่อน
    """
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    activity.is_hidden = False
    session.add(activity)
    session.commit()
    session.refresh(activity)
    return _to_read_single(session, activity)
