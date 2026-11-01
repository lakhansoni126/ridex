"""Unit tests for geo helpers and rate limiter."""

from uuid import uuid4

from app.core.rate_limit import LocationRateLimiter
from app.services.geo import point_wkt


def test_point_wkt():
    elem = point_wkt(77.6, 12.9)
    assert "POINT(77.6 12.9)" in str(elem.data) or "POINT(77.6 12.9)" in elem.desc


def test_location_rate_limiter():
    limiter = LocationRateLimiter()
    uid = uuid4()
    assert limiter.allow(uid, speed_mps=10.0) is True
    assert limiter.allow(uid, speed_mps=10.0) is False
    limiter.clear(uid)
    assert limiter.allow(uid, speed_mps=10.0) is True
