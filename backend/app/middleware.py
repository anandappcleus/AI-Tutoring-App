"""Application-wide ASGI middleware.

RequestLoggingMiddleware
------------------------
• Generates or propagates an ``X-Request-ID`` correlation header.
• Stores it in ``REQUEST_ID_CTX`` so every log line during the request
  carries the same ID — works across async tasks spawned in the same context.
• Logs request start (method, path, client IP) and completion (status, ms).
• Echoes the correlation ID back to the caller via the response header.

Usage — registered in ``app/main.py``::

    from app.middleware import RequestLoggingMiddleware
    app.add_middleware(RequestLoggingMiddleware)
"""
from __future__ import annotations

import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import Response

from app.logging_config import REQUEST_ID_CTX

log = logging.getLogger("smarttutor.http")


class RequestLoggingMiddleware(BaseHTTPMiddleware):
    """Log every HTTP request with correlation ID and latency."""

    async def dispatch(self, request: Request, call_next) -> Response:
        # Generate or propagate a 12-hex-char correlation ID
        rid = request.headers.get("X-Request-ID") or uuid.uuid4().hex[:12]
        ctx_token = REQUEST_ID_CTX.set(rid)

        client_ip = request.client.host if request.client else "-"
        log.info("→ %s %s  client=%s", request.method, request.url.path, client_ip)

        t0 = time.perf_counter()
        try:
            response = await call_next(request)
            ms = (time.perf_counter() - t0) * 1_000
            log.info(
                "← %s %s  status=%d  %.1fms",
                request.method,
                request.url.path,
                response.status_code,
                ms,
            )
            response.headers["X-Request-ID"] = rid
            return response
        except Exception:
            ms = (time.perf_counter() - t0) * 1_000
            log.exception(
                "unhandled_exception  %s %s  %.1fms",
                request.method,
                request.url.path,
                ms,
            )
            raise
        finally:
            # Reset AFTER logging so all log lines in this request carry the
            # correlation ID, including the "←" response line above.
            REQUEST_ID_CTX.reset(ctx_token)
