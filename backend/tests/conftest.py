import os
import sys
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

BACKEND_DIR = os.path.dirname(os.path.dirname(__file__))
if BACKEND_DIR not in sys.path:
    sys.path.insert(0, BACKEND_DIR)

import main  # noqa: E402
import models  # noqa: E402
from database import Base  # noqa: E402


@pytest.fixture()
def client(monkeypatch: pytest.MonkeyPatch) -> Generator[TestClient, None, None]:
    test_engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    TestingSessionLocal = sessionmaker(
        autocommit=False,
        autoflush=False,
        bind=test_engine,
    )

    Base.metadata.create_all(bind=test_engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    monkeypatch.setattr(main, "ADMIN_ALLOWED_EMAILS", set())
    main.app.dependency_overrides[main.get_db] = override_get_db

    with TestClient(main.app) as test_client:
        yield test_client

    main.app.dependency_overrides.clear()


def auth_headers(token: str) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {token}"}
    if main.ADMIN_API_KEY.strip():
        headers["X-Admin-Key"] = main.ADMIN_API_KEY.strip()
    return headers


def signup_and_login(client: TestClient, email: str = "admin@example.com") -> dict:
    signup_response = client.post(
        "/signup",
        json={
            "name": "Admin User",
            "email": email,
            "password": "strong-password-123",
        },
    )
    assert signup_response.status_code == 200
    payload = signup_response.json()
    assert payload["access_token"]
    assert payload["user"]["email"] == email
    return payload
