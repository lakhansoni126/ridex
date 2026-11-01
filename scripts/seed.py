#!/usr/bin/env python3
"""Seed demo users for local development.

Run inside the API container:
  docker compose exec -T api python /scripts/seed.py

Or on the host (with backend deps + DB on localhost):
  cd backend && PYTHONPATH=. python ../scripts/seed.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"
for candidate in (Path("/app"), BACKEND):
    if candidate.exists() and str(candidate) not in sys.path:
        sys.path.insert(0, str(candidate))

os.environ.setdefault(
    "DATABASE_URL",
    "postgresql+psycopg://ridex:ridex_dev_password@localhost:5432/ridex",
)

from sqlalchemy import select  # noqa: E402

from app.core.database import SessionLocal  # noqa: E402
from app.core.security import hash_password  # noqa: E402
from app.models.enums import FriendshipStatus  # noqa: E402
from app.models.friendship import Friendship  # noqa: E402
from app.models.user import User  # noqa: E402

DEMO_USERS = [
    {
        "email": "alex@ridex.local",
        "username": "alex",
        "display_name": "Alex Driver",
        "password": "password123",
    },
    {
        "email": "sam@ridex.local",
        "username": "sam",
        "display_name": "Sam Cruiser",
        "password": "password123",
    },
    {
        "email": "jordan@ridex.local",
        "username": "jordan",
        "display_name": "Jordan Roadster",
        "password": "password123",
    },
]


def main() -> None:
    db = SessionLocal()
    try:
        created: list[User] = []
        for spec in DEMO_USERS:
            existing = db.scalar(select(User).where(User.email == spec["email"]))
            if existing:
                print(f"exists: {spec['username']}")
                created.append(existing)
                continue
            user = User(
                email=spec["email"],
                username=spec["username"],
                display_name=spec["display_name"],
                password_hash=hash_password(spec["password"]),
                bio="Demo RideX user",
            )
            db.add(user)
            db.flush()
            created.append(user)
            print(f"created: {spec['username']} / {spec['password']}")
        db.commit()

        if len(created) >= 2:
            a, b = created[0], created[1]
            fr = db.scalar(
                select(Friendship).where(
                    Friendship.requester_id == a.id,
                    Friendship.addressee_id == b.id,
                )
            )
            if not fr:
                db.add(
                    Friendship(
                        requester_id=a.id,
                        addressee_id=b.id,
                        status=FriendshipStatus.accepted,
                    )
                )
                db.commit()
                print(f"friended: {a.username} <-> {b.username}")
    finally:
        db.close()


if __name__ == "__main__":
    main()
