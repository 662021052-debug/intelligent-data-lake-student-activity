import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, SQLModel, create_engine
from sqlmodel.pool import StaticPool

from app.auth import hash_password
from app.database import get_session
from app.main import app
from app.models import User, UserRole

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


@pytest.fixture(name="client")
def client_fixture(session):
    def get_session_override():
        return session

    app.dependency_overrides[get_session] = get_session_override
    client = TestClient(app)

    staff_token = _login(client, "staff", "staff123")
    client.headers["Authorization"] = f"Bearer {staff_token}"

    yield client
    app.dependency_overrides.clear()


@pytest.fixture(name="tokens")
def tokens_fixture(client):
    return {
        "admin": _login(client, "admin", "admin123"),
        "staff": client.headers["Authorization"].split(" ")[1],
        "student": _login(client, "student", "student123"),
    }
