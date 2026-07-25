"""Postgres integration test for the low-participation div-by-zero guard.

SQLite returns NULL on divide-by-zero, so a SQLite test cannot prove the fix.
This runs the real endpoint against Postgres, where an unguarded
`COUNT(...) / max_participants` with a 0-capacity activity raises and 500s.

Opt-in: set TEST_DATABASE_URL to a *dedicated, disposable* Postgres database,
e.g. TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/activity_lake_test
It is skipped entirely when that env var is unset.
"""

import os

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine, text

from app.auth import hash_password
from app.database import get_session
from app.gold import GOLD_VIEW_NAMES, create_gold_layer
from app.main import app
from app.models import (
    Activity,
    ApprovalStatus,
    HourCategory,
    HourSubcategory,
    User,
    UserRole,
)

PG_URL = os.environ.get("TEST_DATABASE_URL")

pytestmark = pytest.mark.skipif(
    not PG_URL or not PG_URL.startswith("postgresql"),
    reason="set TEST_DATABASE_URL to a disposable Postgres database to run",
)

_ENUM_TYPES = ["studentstatus", "userrole", "evidencestatus", "approvalstatus", "ocrdecision"]


def _reset(engine) -> None:
    """Give the disposable test DB a clean slate (tables, gold views, enum types)."""
    with engine.begin() as conn:
        for view in GOLD_VIEW_NAMES:
            conn.execute(text(f"DROP VIEW IF EXISTS {view} CASCADE"))
    SQLModel.metadata.drop_all(engine)
    with engine.begin() as conn:
        for enum in _ENUM_TYPES:
            conn.execute(text(f"DROP TYPE IF EXISTS {enum} CASCADE"))
    SQLModel.metadata.create_all(engine)


def test_low_participation_survives_zero_capacity_on_postgres():
    engine = create_engine(PG_URL)
    _reset(engine)

    def get_session_override():
        with Session(engine) as session:
            yield session

    app.dependency_overrides[get_session] = get_session_override
    client = TestClient(app)
    try:
        with Session(engine) as session:
            session.add(
                User(username="pg_admin", hashed_password=hash_password("pw"), role=UserRole.admin)
            )
            cat = HourCategory(name="pgcat", required_hours=10)
            session.add(cat)
            session.commit()
            session.refresh(cat)
            sub = HourSubcategory(category_id=cat.id, name="pgsub", required_hours=10)
            session.add(sub)
            session.commit()
            session.refresh(sub)
            # 0-capacity activity: the unguarded ORDER BY division would 500 here.
            session.add(
                Activity(
                    name="PGZeroCap", activity_type="วิชาการ", is_required=False,
                    max_participants=0, start_at="2026-08-01 09:00:00", location="ห้อง",
                    hours=4, subcategory_id=sub.id, approval_status=ApprovalStatus.approved,
                )
            )
            session.commit()
            create_gold_layer(session)

        token = client.post(
            "/auth/login", data={"username": "pg_admin", "password": "pw"}
        ).json()["access_token"]
        resp = client.get(
            "/dashboard/low-participation", headers={"Authorization": f"Bearer {token}"}
        )
        assert resp.status_code == 200, resp.text
        assert any(r["name"] == "PGZeroCap" for r in resp.json())
    finally:
        app.dependency_overrides.clear()
        _reset(engine)
