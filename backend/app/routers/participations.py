from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, func, select

from app.auth import get_current_user, require_writer
from app.database import get_session
from app.models import (
    Activity,
    ApprovalStatus,
    EvidenceStatus,
    Participation,
    ParticipationCreate,
    ParticipationRead,
    ParticipationUpdate,
    Student,
    User,
    UserRole,
)
from app.schemas import Page, ParticipationRegister

router = APIRouter(
    prefix="/participations", tags=["participations"], dependencies=[Depends(get_current_user)]
)


def _owned_activity_ids(current_user: User):
    return select(Activity.id).where(Activity.created_by == current_user.id)


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

    total = session.exec(count_query).one()
    items = session.exec(query.offset(skip).limit(limit)).all()
    return Page(items=items, total=total, skip=skip, limit=limit)


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
    return participation


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
    if activity.approval_status != ApprovalStatus.approved:
        raise HTTPException(status_code=400, detail="กิจกรรมนี้ยังไม่เปิดรับสมัคร")
    if activity.start_at <= datetime.utcnow():
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
    return participation


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
    return participation


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
    student_id = data.get("student_id", participation.student_id)
    activity_id = data.get("activity_id", participation.activity_id)
    if "student_id" in data or "activity_id" in data:
        _ensure_student_and_activity_exist(session, student_id, activity_id)
        if "activity_id" in data:
            target_activity = _get_activity_or_404(session, activity_id)
            _ensure_staff_owns_activity(current_user, target_activity)

    for key, value in data.items():
        setattr(participation, key, value)
    session.add(participation)
    session.commit()
    session.refresh(participation)
    return participation


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
