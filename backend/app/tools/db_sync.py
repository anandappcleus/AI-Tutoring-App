"""
Sync-to-async bridge for CrewAI tools.

CrewAI tool `_run` methods are synchronous, but our SQLAlchemy engine is async.
This helper lets a sync context safely drive an async coroutine:

- No running event loop (standalone scripts, pytest without asyncio):
      asyncio.run() creates a fresh loop.

- Running event loop already exists (FastAPI/uvicorn worker thread):
      We dispatch to a ThreadPoolExecutor so asyncio.run() can create its own
      loop in that thread without blocking the main loop.
"""

from __future__ import annotations

import asyncio
import concurrent.futures
from collections.abc import Coroutine
from typing import TypeVar

T = TypeVar("T")


def run_async(coro: Coroutine[None, None, T]) -> T:
    """Run *coro* synchronously regardless of the calling context."""
    try:
        asyncio.get_running_loop()
    except RuntimeError:
        # No loop running — safe to use asyncio.run() directly.
        return asyncio.run(coro)
    else:
        # A loop is already running (FastAPI worker).
        # Run the coroutine in a separate thread that owns its own event loop.
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            future = pool.submit(asyncio.run, coro)
            return future.result()
