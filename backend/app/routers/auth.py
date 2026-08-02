from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlmodel import Session, func, select

from app.auth import (
    create_access_token,
    get_current_user,
    hash_password,
    require_admin,
    verify_password,
)
from app.database import get_session
from app.models import Student, User, UserCreate, UserRead, UserRole, UserUpdate
from app.schemas import Page, Token

router = APIRouter(prefix="/auth", tags=["auth"])


def _validate_student_link(session: Session, role: UserRole, student_id: Optional[int]) -> Optional[int]:
    """A student account *may* be linked to an existing student, but need not be.

    การผูกไม่บังคับ เพื่อให้ผู้ดูแลสร้างบัญชีไว้ก่อนแล้วค่อยผูกทีหลังได้ (เช่น นิสิต
    เข้าใหม่ที่ยังไม่มีข้อมูลในระบบ) บัญชีที่ยังไม่ผูกจะเห็นรายการเป็นค่าว่างและ
    เรียก endpoint แบบ /me ไม่ได้ ซึ่งเป็นพฤติกรรมที่ตั้งใจและมีเทสต์คุมอยู่แล้ว
    (test_unlinked_student_gets_empty_lists_not_error)

    ถ้าระบุ student_id มา ยังต้องมีอยู่จริง — กันพิมพ์ผิดแล้วผูกไปหา record ที่ไม่มี
    """
    if role == UserRole.student:
        if student_id is None:
            return None
        if not session.get(Student, student_id):
            raise HTTPException(status_code=400, detail="student_id does not exist")
        return student_id
    # staff / admin are never tied to a student record
    return None


@router.post("/login", response_model=Token)
def login(
    form_data: OAuth2PasswordRequestForm = Depends(), session: Session = Depends(get_session)
):
    user = session.exec(select(User).where(User.username == form_data.username)).first()
    if not user or not verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    access_token = create_access_token(data={"sub": user.username, "role": user.role.value})
    return {"access_token": access_token, "token_type": "bearer"}


@router.post("/register", response_model=UserRead, status_code=201)
def register(
    payload: UserCreate,
    session: Session = Depends(get_session),
    _: User = Depends(require_admin),
):
    existing = session.exec(select(User).where(User.username == payload.username)).first()
    if existing:
        raise HTTPException(status_code=400, detail="username already exists")

    student_id = _validate_student_link(session, payload.role, payload.student_id)
    user = User(
        username=payload.username,
        hashed_password=hash_password(payload.password),
        role=payload.role,
        student_id=student_id,
    )
    session.add(user)
    session.commit()
    session.refresh(user)
    return user


@router.get("/users", response_model=Page[UserRead], dependencies=[Depends(require_admin)])
def list_users(
    skip: int = Query(0, ge=0),
    limit: int = Query(50, ge=1, le=200),
    search: Optional[str] = Query(None, description="ค้นหาจากชื่อผู้ใช้"),
    session: Session = Depends(get_session),
):
    query = select(User)
    count_query = select(func.count()).select_from(User)
    if search:
        condition = User.username.ilike(f"%{search}%")
        query = query.where(condition)
        count_query = count_query.where(condition)

    total = session.exec(count_query).one()
    # ลำดับคงที่ ไม่ให้แถวที่เพิ่งแก้ (role/รหัสผ่าน) ย้ายตำแหน่งในรายการ
    items = session.exec(query.order_by(User.id).offset(skip).limit(limit)).all()
    return Page(items=items, total=total, skip=skip, limit=limit)


@router.put("/users/{user_id}", response_model=UserRead, dependencies=[Depends(require_admin)])
def update_user(
    user_id: int,
    payload: UserUpdate,
    session: Session = Depends(get_session),
):
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    data = payload.model_dump(exclude_unset=True)
    new_role = data.get("role", user.role)
    # student_id is only meaningful for the (possibly new) role
    new_student_id = data.get("student_id", user.student_id)
    user.student_id = _validate_student_link(session, new_role, new_student_id)
    user.role = new_role
    if "password" in data and data["password"]:
        user.hashed_password = hash_password(data["password"])

    session.add(user)
    session.commit()
    session.refresh(user)
    return user


@router.delete("/users/{user_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_user(
    user_id: int,
    session: Session = Depends(get_session),
    current_user: User = Depends(get_current_user),
):
    if user_id == current_user.id:
        raise HTTPException(status_code=400, detail="ไม่สามารถลบบัญชีของตนเองได้")
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    session.delete(user)
    session.commit()
    return None
