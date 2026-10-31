"""Best-effort security alert emails for the account owner.

Alert delivery runs on a background executor and never raises into the auth
flow. Only high-signal events are sent, with a threshold for repeated OTP
failures and a cooldown to prevent alert storms.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from datetime import datetime
from typing import Callable, Protocol

from .email import EmailService
from .security_events import SecurityEvent

_ALERTED_EVENTS = frozenset(
    {
        "login_succeeded",
        "account_locked",
        "login_otp_failed",
    }
)


class AlertExecutor(Protocol):
    """Minimal executor boundary used to make tests deterministic."""

    def submit(
        self,
        fn: Callable[..., object],
        *args: object,
        **kwargs: object,
    ) -> object:
        """Schedule one callable."""

    def shutdown(self, wait: bool = True) -> None:
        """Release executor resources."""


@dataclass(frozen=True, slots=True)
class _Alert:
    to: str
    event_type: str
    occurred_at: datetime


class SecurityAlertNotifier:
    """Turn selected security events into background emails.

    The notifier only alerts when an event belongs to a known user and has an
    email address. Unknown-email lockout events are deliberately skipped so the
    endpoint cannot be used to send mail to arbitrary addresses.
    """

    def __init__(
        self,
        email_service: EmailService,
        *,
        otp_failure_threshold: int = 3,
        otp_failure_window_seconds: float = 900.0,
        cooldown_seconds: float = 300.0,
        executor: AlertExecutor | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if otp_failure_threshold <= 0:
            raise ValueError("otp_failure_threshold must be positive")
        if otp_failure_window_seconds <= 0:
            raise ValueError("otp_failure_window_seconds must be positive")
        if cooldown_seconds < 0:
            raise ValueError("cooldown_seconds cannot be negative")

        self._email = email_service
        self._otp_failure_threshold = otp_failure_threshold
        self._otp_failure_window_seconds = otp_failure_window_seconds
        self._cooldown_seconds = cooldown_seconds
        self._executor = executor or ThreadPoolExecutor(
            max_workers=1,
            thread_name_prefix="security-alert",
        )
        self._owns_executor = executor is None
        self._clock = clock

        self._lock = threading.Lock()
        self._cooldowns: dict[tuple[str, str], float] = {}
        self._otp_failures: dict[str, deque[float]] = {}
        self._condition = threading.Condition()
        self._pending = 0
        self._closed = False

    def notify(self, event: SecurityEvent) -> None:
        """Consider one event for delivery; never raise into the caller."""

        try:
            self._notify(event)
        except Exception:
            # Alerting is best-effort. Authentication must not fail because a
            # notifier or an SMTP server had a problem.
            return

    def _notify(self, event: SecurityEvent) -> None:
        if not self._email.is_configured:
            return
        if event.event_type not in _ALERTED_EVENTS:
            return
        if not event.email or not event.user_id:
            return

        now = self._clock()
        with self._lock:
            if event.event_type == "login_otp_failed":
                failures = self._otp_failures.setdefault(
                    event.email,
                    deque(),
                )
                cutoff = now - self._otp_failure_window_seconds
                while failures and failures[0] < cutoff:
                    failures.popleft()
                failures.append(now)
                if len(failures) < self._otp_failure_threshold:
                    return
                # Require a fresh set of failures before another OTP alert.
                self._otp_failures.pop(event.email, None)

            key = (event.event_type, event.email)
            if now < self._cooldowns.get(key, 0.0):
                return
            self._cooldowns[key] = now + self._cooldown_seconds
            alert = _Alert(
                to=event.email,
                event_type=event.event_type,
                occurred_at=event.created_at,
            )

        self._submit(alert)

    def _submit(self, alert: _Alert) -> None:
        with self._condition:
            if self._closed:
                return
            self._pending += 1
        try:
            self._executor.submit(self._deliver, alert)
        except Exception:
            with self._condition:
                self._pending -= 1
                self._condition.notify_all()

    def _deliver(self, alert: _Alert) -> None:
        try:
            self._email.send_security_alert(
                to=alert.to,
                event_type=alert.event_type,
                occurred_at=alert.occurred_at,
            )
        except Exception:
            pass
        finally:
            with self._condition:
                self._pending -= 1
                self._condition.notify_all()

    def wait_for_idle(self, timeout: float = 5.0) -> bool:
        """Wait until queued alerts finish; used by tests and shutdown."""

        deadline = time.monotonic() + max(0.0, timeout)
        with self._condition:
            while self._pending:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    return False
                self._condition.wait(remaining)
            return True

    def close(self) -> None:
        """Stop accepting alerts and wait for queued delivery."""

        with self._condition:
            self._closed = True
        if self._owns_executor:
            self._executor.shutdown(wait=True)
