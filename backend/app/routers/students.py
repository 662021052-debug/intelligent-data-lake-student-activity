from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, func, select

from app.auth import get_current_user, require_admin
from app.database import get_session
from app.models import (
    Activity,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentCreate,
    StudentRead,
    StudentStatus,
    StudentUpdate,
    User,
    UserRole,
)
from app.schemas import HourCategorySummary, HourSubcategorySummary, Page

router = APIRouter(prefix="/students", tags=["students"], dependencies=[Depends(get_current_user)])


@router.get("", response_model=Page[StudentRead])
def list_students(
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=200),
    faculty: Optional[str] = None,
    status: Optional[StudentStatus] = None,
    search: Optional[str] = Query(None, description="ค้นหาจากชื่อหรือรหัสนิสิต"),
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    query = select(Student)
    count_query = select(func.count()).select_from(Student)

    if current_user.role == UserRole.student:
        if current_user.student_id is None:
            return Page(items=[], total=0, skip=skip, limit=limit)
        query = query.where(Student.id == current_user.student_id)
        count_query = count_query.where(Student.id == current_user.student_id)

    if faculty:
        query = query.where(Student.faculty == faculty)
        count_query = count_query.where(Student.faculty == faculty)
    if status:
        query = query.where(Student.status == status)
        count_query = count_query.where(Student.status == status)
    if search:
        pattern = f"%{search}%"
        condition = Student.full_name.ilike(pattern) | Student.student_id.ilike(pattern)
        query = query.where(condition)
        count_query = count_query.where(condition)

    total = session.exec(count_query).one()
    # เรียงตามรหัสนิสิตเสมอ (รหัสขึ้นต้นด้วยปีที่เข้าศึกษา จึงจัดกลุ่มตามชั้นปีให้เอง)
    # ถ้าไม่ใส่ ORDER BY ฐานข้อมูลจะคืนลำดับตามใจ — แถวที่ถูก UPDATE (เช่น เปลี่ยนสถานะ)
    # จะย้ายที่และไปแทรกอยู่กับชั้นปีอื่น
    query = query.order_by(Student.student_id, Student.id)
    items = session.exec(query.offset(skip).limit(limit)).all()
    return Page(items=items, total=total, skip=skip, limit=limit)


def _build_hours_summary(session: Session, student_id: int) -> list[HourCategorySummary]:
    """Roll up a single student's approved activity hours per hour-category/subcategory."""
    categories = session.exec(select(HourCategory)).all()
    subcategories = session.exec(select(HourSubcategory)).all()
    subs_by_category: dict[int, list[HourSubcategory]] = {}
    for sub in subcategories:
        subs_by_category.setdefault(sub.category_id, []).append(sub)

    rows = session.exec(
        select(Activity.subcategory_id, func.sum(Participation.hours_earned))
        .join(Activity, Activity.id == Participation.activity_id)
        .where(
            Participation.student_id == student_id,
            Participation.evidence_status == EvidenceStatus.approved,
            Activity.subcategory_id.is_not(None),
        )
        .group_by(Activity.subcategory_id)
    ).all()
    earned_by_subcategory = {sub_id: hours or 0.0 for sub_id, hours in rows}

    result = []
    for category in categories:
        sub_results = []
        category_earned = 0.0
        for sub in subs_by_category.get(category.id, []):
            earned = earned_by_subcategory.get(sub.id, 0.0)
            category_earned += earned
            sub_results.append(
                HourSubcategorySummary(
                    id=sub.id,
                    name=sub.name,
                    required_hours=sub.required_hours,
                    earned_hours=earned,
                    completed=earned >= sub.required_hours,
                )
            )
        result.append(
            HourCategorySummary(
                id=category.id,
                name=category.name,
                required_hours=category.required_hours,
                earned_hours=category_earned,
                completed=category_earned >= category.required_hours,
                subcategories=sub_results,
            )
        )
    return result


@router.get("/me/hours-summary", response_model=list[HourCategorySummary])
def my_hours_summary(
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    if current_user.role != UserRole.student:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    if current_user.student_id is None:
        raise HTTPException(status_code=403, detail="This account is not linked to a student record")

    return _build_hours_summary(session, current_user.student_id)


@router.get("/{student_id}/hours-summary", response_model=list[HourCategorySummary])
def student_hours_summary(
    student_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    """staff/admin view of a single student's accumulated hours.

    - student: may only read their own summary (others -> 403)
    - staff: may read only students who joined one of their own activities (others -> 403)
    - admin: any student
    """
    if current_user.role == UserRole.student and current_user.student_id != student_id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")

    if not session.get(Student, student_id):
        raise HTTPException(status_code=404, detail="Student not found")

    if current_user.role == UserRole.staff:
        joined_owned = session.exec(
            select(Participation.id)
            .join(Activity, Activity.id == Participation.activity_id)
            .where(
                Participation.student_id == student_id,
                Activity.created_by == current_user.id,
            )
            .limit(1)
        ).first()
        if joined_owned is None:
            raise HTTPException(status_code=403, detail="Insufficient permissions")

    return _build_hours_summary(session, student_id)


@router.get("/{student_id}", response_model=StudentRead)
def get_student(
    student_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    if current_user.role == UserRole.student and current_user.student_id != student_id:
        raise HTTPException(status_code=403, detail="Insufficient permissions")
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")
    return student


@router.post("", response_model=StudentRead, status_code=201, dependencies=[Depends(require_admin)])
def create_student(payload: StudentCreate, session: Session = Depends(get_session)):
    existing = session.exec(select(Student).where(Student.student_id == payload.student_id)).first()
    if existing:
        raise HTTPException(status_code=400, detail="student_id already exists")
    student = Student.model_validate(payload)
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


@router.put("/{student_id}", response_model=StudentRead, dependencies=[Depends(require_admin)])
def update_student(student_id: int, payload: StudentUpdate, session: Session = Depends(get_session)):
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    data = payload.model_dump(exclude_unset=True)
    if "student_id" in data and data["student_id"] != student.student_id:
        existing = session.exec(
            select(Student).where(Student.student_id == data["student_id"])
        ).first()
        if existing:
            raise HTTPException(status_code=400, detail="student_id already exists")

    for key, value in data.items():
        setattr(student, key, value)
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


@router.delete("/{student_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_student(student_id: int, session: Session = Depends(get_session)):
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    related = session.exec(select(Participation).where(Participation.student_id == student_id)).all()
    for row in related:
        session.delete(row)

    session.delete(student)
    session.commit()
    return None
