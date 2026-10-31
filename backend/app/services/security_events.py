"""In-memory security alert events.

These records are the hand-off point for a future alert-email sender and the
security dashboard. They deliberately contain no passwords, OTPs, tokens, or
security answers. The service is bounded and thread-safe.
"""

from __future__ import annotations

import logging
import threading
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from datetime import datetime, timezone
from uuid import uuid4

logger = logging.getLogger(__name__)


@dataclass(frozen=True, slots=True)
class SecurityEvent:
    id: str
    event_type: str
    created_at: datetime
    user_id: str | None = None
    email: str | None = None
    client_key: str | None = None
    detail: str | None = None


class SecurityEventService:
    def __init__(
        self,
        max_events: int = 1000,
        *,
        on_event: Callable[[SecurityEvent], None] | None = None,
    ) -> None:
        if max_events <= 0:
            raise ValueError("max_events must be positive")
        self._events: deque[SecurityEvent] = deque(maxlen=max_events)
        self._lock = threading.Lock()
        self._on_event = on_event

    def record(
        self,
        event_type: str,
        *,
        user_id: str | None = None,
        email: str | None = None,
        client_key: str | None = None,
        detail: str | None = None,
    ) -> SecurityEvent:
        event = SecurityEvent(
            id=str(uuid4()),
            event_type=event_type,
            created_at=datetime.now(timezone.utc),
            user_id=user_id,
            email=email,
            client_key=client_key,
            detail=detail,
        )
        with self._lock:
            self._events.append(event)
        if self._on_event is not None:
            try:
                self._on_event(event)
            except Exception:
                logger.warning("A security event listener failed.")
        return event

    @property
    def events(self) -> tuple[SecurityEvent, ...]:
        with self._lock:
            return tuple(self._events)

    def recent(self, limit: int = 50) -> list[SecurityEvent]:
        if limit <= 0:
            return []
        with self._lock:
            return list(self._events)[-limit:]

    def clear(self) -> None:
        with self._lock:
            self._events.clear()
