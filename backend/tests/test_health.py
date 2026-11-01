"""Smoke tests for health and security helpers."""

from app.core.security import (
    create_access_token,
    hash_password,
    hash_token,
    verify_access_token,
    verify_password,
)


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["service"] == "RideX"


def test_password_hash_roundtrip():
    hashed = hash_password("secret-password")
    assert verify_password("secret-password", hashed)
    assert not verify_password("wrong", hashed)


def test_jwt_roundtrip():
    from uuid import uuid4

    uid = uuid4()
    token = create_access_token(uid)
    assert verify_access_token(token) == uid


def test_refresh_token_hash_stable():
    assert hash_token("abc") == hash_token("abc")
    assert hash_token("abc") != hash_token("abd")


def test_openapi_available(client):
    resp = client.get("/openapi.json")
    assert resp.status_code == 200
    paths = resp.json()["paths"]
    assert "/api/v1/auth/register" in paths
    assert "/api/v1/rides" in paths
    assert "/api/v1/posts" in paths
