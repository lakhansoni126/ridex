"""Pytest fixtures — unit/smoke tests that do not require Postgres."""

import pytest
from fastapi.testclient import TestClient

from app.main import app


@pytest.fixture
def client() -> TestClient:
    return TestClient(app)
