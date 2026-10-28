import os

os.environ["DATABASE_URL"] = os.getenv(
    "TEST_DATABASE_URL",
    "postgresql://user:password@localhost:5432/workout_test",
)

from typing import Annotated

import pytest
from fastapi import Depends
from fastapi.security import HTTPAuthorizationCredentials
from fastapi.testclient import TestClient
from sqlalchemy import text

from workout import auth
from workout.database import Base, SessionLocal, engine
from workout.main import app
from workout.seed import init_db


@pytest.fixture(scope="session", autouse=True)
def setup_test_database():
    Base.metadata.drop_all(bind=engine)
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)


@pytest.fixture(autouse=True)
def clean_tables():
    table_names = ", ".join(f'"{table.name}"' for table in Base.metadata.sorted_tables)
    with engine.begin() as conn:
        conn.execute(text(f"TRUNCATE {table_names} CASCADE"))
    init_db(engine)
    yield


@pytest.fixture
def db_session():
    session = SessionLocal()
    try:
        yield session
    finally:
        session.close()


def fake_claims(
    credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(auth.bearer)],
):
    """Test auth: the bearer token *is* the user id (Cognito `sub`)."""
    if credentials is None:
        return auth.get_claims(None)
    sub = credentials.credentials
    return {"sub": sub, "email": f"{sub}@example.com"}


@pytest.fixture
def client():
    app.dependency_overrides[auth.get_claims] = fake_claims
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()


def auth_headers(user_id: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {user_id}"}
