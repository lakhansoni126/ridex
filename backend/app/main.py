"""RideX API entrypoint."""

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import get_settings
from app.services.media import ensure_storage_dirs
from app.ws import location_shares as ws_shares
from app.ws import rides as ws_rides

settings = get_settings()


@asynccontextmanager
async def lifespan(_app: FastAPI):
    ensure_storage_dirs()
    yield


app = FastAPI(
    title="RideX API",
    version="0.2.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origin_list,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix=settings.api_prefix)
app.include_router(ws_rides.router)
app.include_router(ws_shares.router)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok", "service": "RideX"}
