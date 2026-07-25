"""Gold Layer maintenance endpoints.

The dashboard reads from the ``gold_*`` views; this router lets an admin rebuild
them on demand, standing in for the Bronze→Silver→Gold ETL refresh step.
"""

from fastapi import APIRouter, Depends
from sqlmodel import Session

from app.auth import require_admin
from app.database import get_session
from app.gold import GOLD_VIEW_NAMES, create_gold_layer

router = APIRouter(prefix="/gold", tags=["gold"])


@router.post("/refresh", dependencies=[Depends(require_admin)])
def refresh_gold_layer(session: Session = Depends(get_session)) -> dict:
    """Rebuild every gold view (admin only). Simulates an ETL refresh run."""
    create_gold_layer(session)
    return {"status": "refreshed", "views": GOLD_VIEW_NAMES}
