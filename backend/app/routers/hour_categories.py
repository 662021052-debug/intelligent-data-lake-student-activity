from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from app.auth import get_current_user
from app.database import get_session
from app.models import HourCategory, HourSubcategory
from app.schemas import HourCategoryRead, HourSubcategoryRead

router = APIRouter(
    prefix="/hour-categories", tags=["hour-categories"], dependencies=[Depends(get_current_user)]
)


@router.get("", response_model=list[HourCategoryRead])
def list_hour_categories(session: Session = Depends(get_session)):
    categories = session.exec(select(HourCategory)).all()
    subcategories = session.exec(select(HourSubcategory)).all()
    subs_by_category: dict[int, list[HourSubcategory]] = {}
    for sub in subcategories:
        subs_by_category.setdefault(sub.category_id, []).append(sub)

    return [
        HourCategoryRead(
            id=category.id,
            name=category.name,
            required_hours=category.required_hours,
            subcategories=[
                HourSubcategoryRead(id=sub.id, name=sub.name, required_hours=sub.required_hours)
                for sub in subs_by_category.get(category.id, [])
            ],
        )
        for category in categories
    ]
