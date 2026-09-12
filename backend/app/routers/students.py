from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, func, select

from app.auth import get_current_user, hash_password, require_admin
from app.criteria import cohort_from_student_id, resolve_criteria_set_id
from app.database import get_session
from app.models import (
    Activity,
    EvidenceStatus,
    HourCategory,
    HourSubcategory,
    Participation,
    Student,
    StudentCreateWithAccount,
    StudentRead,
    StudentStatus,
    StudentUpdate,
    StudentWithAccountRead,
    User,
    UserRole,
)
from app.schemas import HourCategorySummary, HourSubcategorySummary, Page

router = APIRouter(prefix="/students", tags=["students"], dependencies=[Depends(get_current_user)])


def _fill_criteria_fields(session: Session, student: Student) -> None:
    """เติม cohort + ชุดเกณฑ์จากรหัสนิสิต ถ้ายังไม่ได้ระบุมา

    ผู้ดูแลจึงกรอกแค่รหัสนิสิต แล้วระบบรู้เองว่านิสิตคนนี้ใช้เกณฑ์ชุดไหน
    (ระบุ cohort/criteria_set_id มาเองก็ได้ ค่าที่ส่งมาชนะเสมอ)
    """
    if student.cohort is None:
        student.cohort = cohort_from_student_id(student.student_id)
    if student.criteria_set_id is None:
        student.criteria_set_id = resolve_criteria_set_id(
            session,
            student.student_id,
            student.program_type,
            student.cohort,
        )


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


def _build_criteria_summary(session: Session, student_id: int) -> list[HourCategorySummary]:
    """ชั่วโมงของนิสิตที่ผูกชุดเกณฑ์แล้ว — อ่านจาก gold_student_hours ตัวเดียวกับแดชบอร์ด

    หน้าของนิสิต แดชบอร์ด และอีเมลกลุ่มเสี่ยงจึงตัดสิน "ครบ/ไม่ครบ" ตรงกันเสมอ รูปคำตอบ
    คงเดิม (หมวด → หมวดย่อย) ให้แอปใช้ได้ทันที: หมวด = Talent/PLO และหมวดย่อย = รายการที่
    ตรวจความครบ · รายการที่ไม่มี Talent (เช่น หน่วยของชุด legacy) เป็นหมวดของตัวเองโดยไม่มีหมวดย่อย

    ชั่วโมงของหมวดนับเฉพาะส่วนที่เข้าเกณฑ์ (ตัดส่วนเกินรายรายการ) — หมวดจะไม่ขึ้นว่าได้ครบเป้า
    ทั้งที่ยังมีรายการในหมวดนั้นขาดอยู่
    """
    rows = session.execute(
        text(
            "SELECT category_key, category_name, required_hours, earned_hours, completed, "
            "talent_key, talent_name, talent_order "
            "FROM gold_student_hours WHERE student_key = :sid ORDER BY category_key"
        ),
        {"sid": student_id},
    ).all()

    groups: dict[tuple, dict] = {}
    for item_key, name, required, earned, completed, talent_key, talent_name, talent_order in rows:
        item = HourSubcategorySummary(
            id=item_key,
            name=name,
            required_hours=float(required),
            earned_hours=float(earned or 0),
            completed=bool(completed),
        )
        key = ("talent", talent_key) if talent_key is not None else ("item", item_key)
        group = groups.setdefault(
            key,
            {
                "id": talent_key if talent_key is not None else item_key,
                "name": talent_name if talent_key is not None else name,
                "order": (0, talent_order or 0, item_key) if talent_key is not None else (1, 0, item_key),
                "is_talent": talent_key is not None,
                "items": [],
            },
        )
        group["items"].append(item)

    result = []
    for group in sorted(groups.values(), key=lambda g: g["order"]):
        items = group["items"]
        result.append(
            HourCategorySummary(
                id=group["id"],
                name=group["name"],
                required_hours=sum(i.required_hours for i in items),
                earned_hours=sum(min(i.earned_hours, i.required_hours) for i in items),
                completed=all(i.completed for i in items),
                subcategories=items if group["is_talent"] else [],
            )
        )
    return result


def _build_hours_summary(session: Session, student_id: int) -> list[HourCategorySummary]:
    """Roll up a single student's approved activity hours per hour-category/subcategory."""
    student = session.get(Student, student_id)
    if student is not None and student.criteria_set_id is not None:
        return _build_criteria_summary(session, student_id)

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


@router.post(
    "",
    response_model=StudentWithAccountRead,
    status_code=201,
    dependencies=[Depends(require_admin)],
)
def create_student(payload: StudentCreateWithAccount, session: Session = Depends(get_session)):
    """สร้างข้อมูลนิสิต และ (ถ้า create_user) บัญชีเข้าใช้งานที่ผูกกันไว้เลย

    ทั้งสองอย่างอยู่ในทรานแซกชันเดียว — ถ้าชื่อผู้ใช้ซ้ำ ต้องไม่เหลือข้อมูลนิสิต
    ค้างไว้ให้ผู้ดูแลตามลบเอง จึงตรวจความซ้ำ "ทั้งคู่ก่อน" แล้วค่อยเขียนลงฐาน

    username/password เว้นว่างได้ — ดีฟอลต์เป็น "รหัสนิสิต" ทั้งคู่ ตรงกับ
    convention ที่ seed.py ใช้ นิสิตใหม่จึงล็อกอินได้ทันทีโดยไม่ต้องจำอะไรเพิ่ม
    """
    existing = session.exec(select(Student).where(Student.student_id == payload.student_id)).first()
    if existing:
        raise HTTPException(status_code=400, detail="รหัสนิสิตนี้มีอยู่ในระบบแล้ว")

    username: Optional[str] = None
    password: Optional[str] = None
    if payload.create_user:
        # เว้นว่าง (หรือมีแต่ช่องว่าง) = ใช้รหัสนิสิตแทน
        username = (payload.username or "").strip() or payload.student_id
        password = payload.password or payload.student_id

        # ตรวจชื่อผู้ใช้ซ้ำก่อนเขียนอะไรลงฐาน ไม่ใช่ปล่อยให้ล้มตอน insert
        taken = session.exec(select(User).where(User.username == username)).first()
        if taken:
            raise HTTPException(
                status_code=400,
                detail=f"มีบัญชีผู้ใช้ชื่อ {username} อยู่แล้ว",
            )

    student = Student.model_validate(payload)
    _fill_criteria_fields(session, student)
    session.add(student)
    try:
        if payload.create_user:
            # flush เพื่อให้ได้ student.id มาผูกกับบัญชี โดยยังไม่ commit
            session.flush()
            session.add(
                User(
                    username=username,
                    hashed_password=hash_password(password),
                    role=UserRole.student,
                    student_id=student.id,
                )
            )
        session.commit()
    except IntegrityError:
        # ชนกับคำขออื่นที่สร้างชื่อซ้ำพร้อมกัน — ทิ้งทั้งก้อน ไม่ให้เหลือนิสิตค้าง
        session.rollback()
        raise HTTPException(status_code=400, detail="ข้อมูลซ้ำกับที่มีอยู่แล้ว กรุณาตรวจสอบอีกครั้ง")
    session.refresh(student)
    return StudentWithAccountRead(**student.model_dump(), username=username)


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
    # แก้รหัสนิสิต/กลุ่มหลักสูตรแล้วรุ่นกับชุดเกณฑ์ต้องตามไปด้วย เว้นแต่ผู้ดูแล
    # ระบุค่ามาเองในคำขอเดียวกัน
    if ("student_id" in data or "program_type" in data) and "criteria_set_id" not in data:
        if "cohort" not in data:
            student.cohort = None
        student.criteria_set_id = None
    _fill_criteria_fields(session, student)
    session.add(student)
    session.commit()
    session.refresh(student)
    return student


@router.delete("/{student_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_student(student_id: int, session: Session = Depends(get_session)):
    """ลบข้อมูลนิสิต พร้อมเก็บกวาดทุกอย่างที่ชี้มาหา ไม่ให้เหลือค้าง

    บัญชีเข้าใช้งานของนิสิตต้องหายไปด้วย — ไม่งั้นจะเหลือ "บัญชีกำพร้า" ที่ยัง
    ล็อกอินได้แต่ไม่มีข้อมูลนิสิตอยู่เบื้องหลัง และ FK ที่ชี้มายังแถวที่ถูกลบไป
    แล้วก็ค้างอยู่ (บน Postgres จะเป็น FK violation ตอน commit)

    บัญชี staff/admin ที่บังเอิญผูกไว้จะถูก "ปลดการผูก" ไม่ใช่ถูกลบ — การลบนิสิต
    หนึ่งคนต้องไม่ทำให้ผู้ดูแลระบบหายไปด้วย (ปกติ API สร้างสถานะนี้ไม่ได้อยู่แล้ว
    เพราะ staff/admin ถูกบังคับให้ student_id เป็น None ตรงนี้กันข้อมูลจากทางอื่น)

    ลบได้เฉพาะนิสิตที่ยังไม่มีประวัติเข้าร่วม — มีประวัติเมื่อไหร่ตอบ 400
    """
    student = session.get(Student, student_id)
    if not student:
        raise HTTPException(status_code=404, detail="Student not found")

    # นิสิตที่เคยเข้าร่วมกิจกรรมแล้วลบไม่ได้ — ลบทิ้งจะพา lineage หายไปด้วย
    # (participation → raw_file → object ใน MinIO → silver_evidence_ocr) และ
    # FK ที่ชี้มายัง participation เป็น NO ACTION ทั้งหมด บน Postgres จึงล้ม
    # กลางคันอยู่ดี ให้ปิดสถานะนิสิตเป็น inactive แทนการลบ
    participation_count = session.exec(
        select(func.count())
        .select_from(Participation)
        .where(Participation.student_id == student_id)
    ).one()
    if participation_count:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: นิสิตมีประวัติเข้าร่วม {participation_count} รายการ",
        )

    linked_users = session.exec(select(User).where(User.student_id == student_id)).all()
    for user in linked_users:
        if user.role == UserRole.student:
            session.delete(user)
        else:
            user.student_id = None
            session.add(user)

    session.delete(student)
    session.commit()
    return None
