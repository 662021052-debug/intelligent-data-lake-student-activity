from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import logging

from app.config import settings
from app.database import create_db_and_tables, engine
from app.gold import init_gold_layer
from app.routers import activities, auth, dashboard, gold, hour_categories, participations, students
from app.storage import get_storage

logger = logging.getLogger("uvicorn.error")


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    # Rebuild the Gold Layer (analytics views) so the dashboard always reads a
    # star schema that matches the current operational tables.
    try:
        init_gold_layer(engine)
    except Exception as exc:  # noqa: BLE001 - dashboard is non-critical for booting
        logger.warning("Could not (re)build gold layer on startup: %s", exc)
    # Bronze bucket is created on startup if it does not exist yet. A storage
    # outage must not stop the API from booting, so failures are logged, not fatal.
    try:
        get_storage().ensure_bucket(settings.minio_bucket_bronze)
    except Exception as exc:  # noqa: BLE001 - best effort, keep API available
        logger.warning("Could not ensure bronze bucket on startup: %s", exc)
    yield


app = FastAPI(title="Intelligent Data Lake - Student Activity Tracking API", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health_check() -> dict:
    return {"status": "ok"}


app.include_router(auth.router)
app.include_router(students.router)
app.include_router(activities.router)
app.include_router(participations.router)
app.include_router(hour_categories.router)
app.include_router(gold.router)
app.include_router(dashboard.router)
