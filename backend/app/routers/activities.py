from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
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
from app.schemas import Page

router = APIRouter(prefix="/activities", tags=["activities"], dependencies=[Depends(get_current_user)])


def _ensure_visible(activity: Activity, current_user: User) -> None:
    """Raise 403 if `current_user` isn't allowed to see/manage this activity."""
    if current_user.role == UserRole.student:
        if activity.approval_status != ApprovalStatus.approved:
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
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    query = select(Activity)
    count_query = select(func.count()).select_from(Activity)

    if current_user.role == UserRole.student:
        query = query.where(Activity.approval_status == ApprovalStatus.approved)
        count_query = count_query.where(Activity.approval_status == ApprovalStatus.approved)
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

    total = session.exec(count_query).one()
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

    return session.exec(
        select(Participation).where(Participation.activity_id == activity_id)
    ).all()


@router.delete("/{activity_id}", status_code=204)
def delete_activity(
    activity_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(require_writer),
):
    activity = session.get(Activity, activity_id)
    if not activity:
        raise HTTPException(status_code=404, detail="Activity not found")
    if current_user.role == UserRole.staff and activity.created_by != current_user.id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    related = session.exec(select(Participation).where(Participation.activity_id == activity_id)).all()
    for row in related:
        session.delete(row)

    session.delete(activity)
    session.commit()
    return None
