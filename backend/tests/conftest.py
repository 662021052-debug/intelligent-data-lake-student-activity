import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app import silver
from app.auth import hash_password
from app.database import get_session
from app.main import app
from app.models import RawFile, User, UserRole
from app.storage import InMemoryStorage, get_storage


@pytest.fixture(autouse=True)
def _disable_background_ocr(monkeypatch):
    """The upload endpoint schedules OCR in a background task that opens its own
    engine session (real dev.db). Neutralize it in tests — OCR is exercised
    directly via the /evidence/process endpoint with an injected fake engine."""
    monkeypatch.setattr(silver, "process_evidence_in_background", lambda participation_id: None)

TEST_USERS = {
    "admin": ("admin", "admin123", UserRole.admin),
    "staff": ("staff", "staff123", UserRole.staff),
    "student": ("student", "student123", UserRole.student),
}


@pytest.fixture(name="session")
def session_fixture():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    SQLModel.metadata.create_all(engine)
    with Session(engine) as session:
        for username, password, role in TEST_USERS.values():
            session.add(User(username=username, hashed_password=hash_password(password), role=role))
        session.commit()
        yield session


def _login(client: TestClient, username: str, password: str) -> str:
    response = client.post("/auth/login", data={"username": username, "password": password})
    assert response.status_code == 200, response.text
    return response.json()["access_token"]


@pytest.fixture(name="storage")
def storage_fixture():
    return InMemoryStorage()


@pytest.fixture(name="client")
def client_fixture(session, storage):
    def get_session_override():
        return session

    app.dependency_overrides[get_session] = get_session_override
    app.dependency_overrides[get_storage] = lambda: storage
    client = TestClient(app)

    staff_token = _login(client, "staff", "staff123")
    client.headers["Authorization"] = f"Bearer {staff_token}"

    yield client
    app.dependency_overrides.clear()


@pytest.fixture(name="add_evidence")
def add_evidence_fixture(session):
    """Insert a raw_file row so a participation counts as having evidence (A3),
    without going through the multipart upload endpoint."""

    def _add(participation_id, filename="proof.png", content_type="image/png"):
        raw_file = RawFile(
            bucket="bronze",
            object_key=f"evidence/test/participation_id={participation_id}/{filename}",
            original_filename=filename,
            content_type=content_type,
            size_bytes=10,
            checksum="0" * 64,
            source_system="student_upload",
            uploaded_by=None,
            participation_id=participation_id,
        )
        session.add(raw_file)
        session.commit()
        return raw_file

    return _add


@pytest.fixture(name="tokens")
def tokens_fixture(client):
    return {
        "admin": _login(client, "admin", "admin123"),
        "staff": client.headers["Authorization"].split(" ")[1],
        "student": _login(client, "student", "student123"),
    }
