"""Aggregate v1 API router."""

from fastapi import APIRouter

from app.api.v1 import auth, friends, location_shares, media, posts, rides, users

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(friends.router)
api_router.include_router(rides.router)
api_router.include_router(location_shares.router)
api_router.include_router(posts.router)
api_router.include_router(media.router)
