from typing import Optional

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, func, select

from app.auth import get_current_user, require_admin
from app.database import get_session
from app.models import Activity, HourCategory, HourSubcategory
from app.schemas import (
    HourCategoryRead,
    HourCategoryWrite,
    HourSubcategoryDetailRead,
    HourSubcategoryRead,
    HourSubcategoryWrite,
)

router = APIRouter(
    prefix="/hour-categories", tags=["hour-categories"], dependencies=[Depends(get_current_user)]
)

# หมวดย่อยแยก prefix ของตัวเอง เพราะมันถูกอ้างด้วย id ของตัวเองล้วน ๆ
# (`/hour-subcategories/{id}`) ไม่ใช่ nested ใต้หมวดใหญ่ — จะได้ไม่ต้องส่ง
# category_id ที่ไม่มีใครใช้มาใน path ตอนแก้/ลบ
subcategory_router = APIRouter(
    prefix="/hour-subcategories",
    tags=["hour-categories"],
    dependencies=[Depends(get_current_user)],
)


def _to_read(category: HourCategory, subcategories: list[HourSubcategory]) -> HourCategoryRead:
    return HourCategoryRead(
        id=category.id,
        name=category.name,
        required_hours=category.required_hours,
        subcategories=[
            HourSubcategoryRead(id=sub.id, name=sub.name, required_hours=sub.required_hours)
            for sub in subcategories
        ],
    )


def _subcategories_of(session: Session, category_id: int) -> list[HourSubcategory]:
    return list(
        session.exec(
            select(HourSubcategory).where(HourSubcategory.category_id == category_id)
        ).all()
    )


def _get_category(session: Session, category_id: int) -> HourCategory:
    category = session.get(HourCategory, category_id)
    if not category:
        raise HTTPException(status_code=404, detail="ไม่พบหมวดชั่วโมงนี้")
    return category


def _get_subcategory(session: Session, subcategory_id: int) -> HourSubcategory:
    subcategory = session.get(HourSubcategory, subcategory_id)
    if not subcategory:
        raise HTTPException(status_code=404, detail="ไม่พบหมวดย่อยนี้")
    return subcategory


def _reject_duplicate_category(session: Session, name: str, exclude_id: Optional[int]) -> None:
    """ชื่อหมวดใหญ่ต้องไม่ซ้ำกัน

    ไม่ได้บังคับที่ระดับฐานข้อมูล แต่ต้องกันที่ API เพราะทั้งแอปอ้างหมวดด้วย
    "ชื่อ" ให้คนอ่าน (dropdown เลือกหมวดของฟอร์มกิจกรรม, กราฟรายหมวดบนแดชบอร์ด)
    — ชื่อซ้ำแปลว่าผู้ใช้แยกไม่ออกว่ากำลังเลือกอันไหน
    """
    query = select(HourCategory).where(HourCategory.name == name)
    if exclude_id is not None:
        query = query.where(HourCategory.id != exclude_id)
    if session.exec(query).first():
        raise HTTPException(status_code=400, detail=f'มีหมวดชั่วโมงชื่อ "{name}" อยู่แล้ว')


def _reject_duplicate_subcategory(
    session: Session, category_id: int, name: str, exclude_id: Optional[int]
) -> None:
    """ชื่อหมวดย่อยต้องไม่ซ้ำ *ภายในหมวดใหญ่เดียวกัน*

    ข้ามหมวดใหญ่ให้ซ้ำได้ตามที่ข้อมูลจริงเป็นอยู่ (เช่น "กิจกรรมบูรณาการ n"
    มีอยู่หลายหมวด) — ที่กันคือความกำกวมในรายการเดียวกันเท่านั้น
    """
    query = select(HourSubcategory).where(
        HourSubcategory.category_id == category_id, HourSubcategory.name == name
    )
    if exclude_id is not None:
        query = query.where(HourSubcategory.id != exclude_id)
    if session.exec(query).first():
        raise HTTPException(status_code=400, detail=f'หมวดนี้มีหมวดย่อยชื่อ "{name}" อยู่แล้ว')


@router.get("", response_model=list[HourCategoryRead])
def list_hour_categories(session: Session = Depends(get_session)):
    categories = session.exec(select(HourCategory)).all()
    subcategories = session.exec(select(HourSubcategory)).all()
    subs_by_category: dict[int, list[HourSubcategory]] = {}
    for sub in subcategories:
        subs_by_category.setdefault(sub.category_id, []).append(sub)

    return [
        _to_read(category, subs_by_category.get(category.id, [])) for category in categories
    ]


@router.post(
    "", response_model=HourCategoryRead, status_code=201, dependencies=[Depends(require_admin)]
)
def create_hour_category(payload: HourCategoryWrite, session: Session = Depends(get_session)):
    name = payload.name.strip()
    _reject_duplicate_category(session, name, exclude_id=None)

    category = HourCategory(name=name, required_hours=payload.required_hours)
    session.add(category)
    session.commit()
    session.refresh(category)
    return _to_read(category, [])


@router.put(
    "/{category_id}", response_model=HourCategoryRead, dependencies=[Depends(require_admin)]
)
def update_hour_category(
    category_id: int, payload: HourCategoryWrite, session: Session = Depends(get_session)
):
    category = _get_category(session, category_id)
    name = payload.name.strip()
    _reject_duplicate_category(session, name, exclude_id=category_id)

    category.name = name
    category.required_hours = payload.required_hours
    session.add(category)
    session.commit()
    session.refresh(category)
    return _to_read(category, _subcategories_of(session, category_id))


@router.delete("/{category_id}", status_code=204, dependencies=[Depends(require_admin)])
def delete_hour_category(category_id: int, session: Session = Depends(get_session)):
    """ลบหมวดใหญ่ได้เฉพาะตอนที่ไม่มีหมวดย่อยอยู่ข้างใต้

    กิจกรรมผูกกับ *หมวดย่อย* ไม่ได้ผูกกับหมวดใหญ่โดยตรง การกันที่หมวดย่อยจึง
    กันกิจกรรมให้ด้วยในตัว — ลบหมวดใหญ่ทิ้งทั้งที่ยังมีลูกจะทำให้ชั่วโมงที่นิสิต
    สะสมไว้ในหมวดนั้นกลายเป็นชั่วโมงที่ไม่สังกัดเกณฑ์ไหนเลย
    """
    _get_category(session, category_id)

    subcategory_count = session.exec(
        select(func.count())
        .select_from(HourSubcategory)
        .where(HourSubcategory.category_id == category_id)
    ).one()
    if subcategory_count:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: หมวดนี้มีหมวดย่อยอยู่ {subcategory_count} รายการ "
            "ให้ลบหรือย้ายหมวดย่อยออกก่อน",
        )

    session.delete(session.get(HourCategory, category_id))
    session.commit()


@subcategory_router.post(
    "",
    response_model=HourSubcategoryDetailRead,
    status_code=201,
    dependencies=[Depends(require_admin)],
)
def create_hour_subcategory(payload: HourSubcategoryWrite, session: Session = Depends(get_session)):
    _get_category(session, payload.category_id)
    name = payload.name.strip()
    _reject_duplicate_subcategory(session, payload.category_id, name, exclude_id=None)

    subcategory = HourSubcategory(
        category_id=payload.category_id, name=name, required_hours=payload.required_hours
    )
    session.add(subcategory)
    session.commit()
    session.refresh(subcategory)
    return subcategory


@subcategory_router.put(
    "/{subcategory_id}",
    response_model=HourSubcategoryDetailRead,
    dependencies=[Depends(require_admin)],
)
def update_hour_subcategory(
    subcategory_id: int, payload: HourSubcategoryWrite, session: Session = Depends(get_session)
):
    subcategory = _get_subcategory(session, subcategory_id)
    _get_category(session, payload.category_id)
    name = payload.name.strip()
    _reject_duplicate_subcategory(session, payload.category_id, name, exclude_id=subcategory_id)

    subcategory.category_id = payload.category_id
    subcategory.name = name
    subcategory.required_hours = payload.required_hours
    session.add(subcategory)
    session.commit()
    session.refresh(subcategory)
    return subcategory


@subcategory_router.delete(
    "/{subcategory_id}", status_code=204, dependencies=[Depends(require_admin)]
)
def delete_hour_subcategory(subcategory_id: int, session: Session = Depends(get_session)):
    """ลบหมวดย่อยได้เฉพาะตอนที่ยังไม่มีกิจกรรมผูกอยู่

    `Activity.subcategory_id` เป็น FK แบบ NO ACTION — ลบทิ้งทั้งที่ยังมีกิจกรรม
    ชี้อยู่ บน Postgres จะล้มตอน commit ส่วนบน SQLite จะกลายเป็นกิจกรรมที่ชี้ไป
    หมวดที่ไม่มีจริง (ชั่วโมงหายไปจากสรุปของนิสิตเงียบ ๆ)
    """
    _get_subcategory(session, subcategory_id)

    activity_count = session.exec(
        select(func.count()).select_from(Activity).where(Activity.subcategory_id == subcategory_id)
    ).one()
    if activity_count:
        raise HTTPException(
            status_code=400,
            detail=f"ลบไม่ได้: มีกิจกรรมใช้หมวดย่อยนี้อยู่ {activity_count} รายการ",
        )

    session.delete(session.get(HourSubcategory, subcategory_id))
    session.commit()
