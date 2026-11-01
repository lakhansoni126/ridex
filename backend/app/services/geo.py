"""GeoAlchemy / WKT helpers."""

from __future__ import annotations

from geoalchemy2 import WKTElement
from geoalchemy2.shape import to_shape
from shapely.geometry import Point


def point_wkt(lon: float, lat: float) -> WKTElement:
    return WKTElement(f"POINT({lon} {lat})", srid=4326)


def linestring_wkt(coords: list[tuple[float, float]]) -> WKTElement | None:
    """coords as (lon, lat) pairs."""
    if len(coords) < 2:
        return None
    path = ", ".join(f"{lon} {lat}" for lon, lat in coords)
    return WKTElement(f"LINESTRING({path})", srid=4326)


def geom_to_latlon(geom) -> tuple[float | None, float | None]:
    if geom is None:
        return None, None
    try:
        shape = to_shape(geom)
        if isinstance(shape, Point):
            return float(shape.y), float(shape.x)
    except Exception:
        return None, None
    return None, None
