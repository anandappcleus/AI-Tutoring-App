"""
WhatsApp Send Tool — sends a message via the WhatsApp Cloud API.

Requires in .env:
    WHATSAPP_TOKEN             Meta Graph API bearer token
    WHATSAPP_PHONE_NUMBER_ID   Sender phone number ID from the Meta dashboard

If either env var is empty, the tool logs a warning and returns a "disabled" status
so the agent crew can still run during development without WhatsApp credentials.

Used by:
    Progress Monitor Agent — notify parents/students about topic plateaus.
"""

from __future__ import annotations

import json
import logging

import httpx
from crewai.tools import BaseTool
from pydantic import BaseModel, Field

from app.config import get_settings

log = logging.getLogger(__name__)

_WA_BASE = "https://graph.facebook.com"


class WhatsAppInput(BaseModel):
    to: str = Field(
        ...,
        description=(
            "Recipient phone number in international format without '+', e.g. '919876543210'."
        ),
    )
    message: str = Field(
        ...,
        max_length=4096,
        description="Text message body to send. Keep alerts under 160 characters.",
    )


class WhatsAppTool(BaseTool):
    """Send a WhatsApp text message via the WhatsApp Cloud API."""

    name: str = "WhatsApp Send Tool"
    description: str = (
        "Send a WhatsApp message to a phone number. "
        "The 'to' field must be in international format without '+' (e.g. '919876543210'). "
        "Use this only after detecting a topic plateau to alert the student or parent."
    )
    args_schema: type[BaseModel] = WhatsAppInput

    def _run(self, to: str, message: str) -> str:
        s = get_settings()
        if not s.WHATSAPP_TOKEN or not s.WHATSAPP_PHONE_NUMBER_ID:
            log.warning(
                "whatsapp_tool disabled — WHATSAPP_TOKEN or WHATSAPP_PHONE_NUMBER_ID not set"
            )
            return json.dumps(
                {"status": "disabled", "reason": "WHATSAPP_TOKEN not configured"}
            )

        url = f"{_WA_BASE}/{s.WHATSAPP_API_VERSION}/{s.WHATSAPP_PHONE_NUMBER_ID}/messages"
        payload = {
            "messaging_product": "whatsapp",
            "recipient_type": "individual",
            "to": to,
            "type": "text",
            "text": {"preview_url": False, "body": message},
        }
        headers = {
            "Authorization": f"Bearer {s.WHATSAPP_TOKEN}",
            "Content-Type": "application/json",
        }

        log.info("whatsapp_tool  to=%s  chars=%d", to, len(message))
        try:
            with httpx.Client(timeout=10.0) as client:
                response = client.post(url, json=payload, headers=headers)
                response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            log.error(
                "whatsapp_tool HTTP error  to=%s  status=%d  body=%s",
                to,
                exc.response.status_code,
                exc.response.text[:200],
                exc_info=True,
            )
            raise
        except Exception:
            log.error("whatsapp_tool request failed  to=%s", to, exc_info=True)
            raise

        result = response.json()
        log.info(
            "whatsapp_tool  sent  to=%s  message_id=%s",
            to,
            result.get("messages", [{}])[0].get("id", "unknown"),
        )
        return json.dumps({"status": "sent", "to": to, "response": result})


whatsapp_tool = WhatsAppTool()
