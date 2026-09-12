from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

import logging

from app.config import settings
from app.database import create_db_and_tables, engine
from app.gold import init_gold_layer
from app.routers import (
    activities,
    auth,
    chatbot,
    criteria,
    dashboard,
    gold,
    hour_categories,
    notifications,
    participations,
    reports,
    students,
)
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
    # Ingest the public activity-rules document into the vector store so the
    # chatbot's RAG path can answer rule questions. Best-effort: a failure here
    # (e.g. no LLM key, pgvector unavailable) must not stop the API from booting.
    try:
        from app import rag
        from app.llm import get_llm
        from app.vectorstore import get_vector_store

        rag.ingest_rules(get_llm(), get_vector_store())
    except Exception as exc:  # noqa: BLE001 - chatbot is non-critical for booting
        logger.warning("Could not ingest chatbot rules on startup: %s", exc)
    # งานตั้งเวลาแจ้งเตือนกลุ่มเสี่ยงรายวัน — ปิดไว้เป็นค่าเริ่มต้น และ apscheduler
    # ถูก import แบบ lazy ข้างใน จึงไม่บังคับให้ทุกเครื่องต้องติดตั้ง
    stop_scheduler = None
    try:
        from app.scheduler import shutdown_notification_scheduler, start_notification_scheduler

        start_notification_scheduler()
        stop_scheduler = shutdown_notification_scheduler
    except Exception as exc:  # noqa: BLE001 - notifications are non-critical for booting
        logger.warning("Could not start the notification scheduler: %s", exc)

    yield

    if stop_scheduler is not None:
        stop_scheduler()


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
app.include_router(hour_categories.subcategory_router)
app.include_router(criteria.router)
app.include_router(gold.router)
app.include_router(dashboard.router)
app.include_router(notifications.router)
app.include_router(reports.router)
app.include_router(chatbot.router)
