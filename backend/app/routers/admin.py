"""
Admin router — internal operations protected by X-Admin-Secret header.

Endpoints:
    POST /admin/run-nightly-crew   Trigger the nightly crew immediately (for testing / debug).

Security:
    All endpoints require the X-Admin-Secret header to match the ADMIN_SECRET
    env var. If ADMIN_SECRET is empty the endpoint is disabled (returns 403).
"""

from __future__ import annotations

import asyncio
import logging

from fastapi import APIRouter, Header, HTTPException, status

from app.config import get_settings

log = logging.getLogger(__name__)
router = APIRouter()


def _verify_secret(x_admin_secret: str | None) -> None:
    """Raise 403 if the header is missing or doesn't match ADMIN_SECRET."""
    secret = get_settings().ADMIN_SECRET
    if not secret:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Admin endpoints are disabled (ADMIN_SECRET not configured).",
        )
    if x_admin_secret != secret:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Invalid admin secret.",
        )


@router.post("/run-nightly-crew", status_code=status.HTTP_202_ACCEPTED)
async def trigger_nightly_crew(
    x_admin_secret: str | None = Header(default=None),
):
    """
    Trigger the nightly diagnostic + planning + monitoring crew immediately.

    Returns 202 Accepted and fires the crew in the background so the HTTP
    response is instant. Watch Railway logs for nightly_crew.* log lines.
    """
    _verify_secret(x_admin_secret)

    from app.scheduler import run_nightly_crew

    log.info("admin.trigger_nightly_crew  manual run requested")
    asyncio.create_task(run_nightly_crew())

    return {
        "status": "accepted",
        "message": "Nightly crew started in background. Watch logs for nightly_crew.* entries.",
    }
