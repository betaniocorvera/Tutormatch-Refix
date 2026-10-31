"""Account-scoped login lockout.

The existing rate limiter is keyed by client IP and email. This service adds a
second, account-scoped check so rotating IPs cannot keep guessing one account's
password forever. State is intentionally in memory; a multi-worker deployment
would move it to Redis or the database.
"""

from __future__ import annotations

import math
import threading
import time
from collections import deque
from collections.abc import Callable


class AccountLockout:
    def __init__(
        self,
        max_attempts: int,
        lockout_seconds: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if max_attempts <= 0:
            raise ValueError("max_attempts must be positive")
        if lockout_seconds <= 0:
            raise ValueError("lockout_seconds must be positive")
        self.max_attempts = max_attempts
        self._lockout_seconds = float(lockout_seconds)
        self._clock = clock
        self._failures: dict[str, deque[float]] = {}
        self._locked_until: dict[str, float] = {}
        self._lock = threading.Lock()

    def check(self, key: str) -> int | None:
        """Return retry-after seconds when the account is locked."""

        with self._lock:
            now = self._clock()
            locked_until = self._locked_until.get(key)
            if locked_until is not None:
                if locked_until > now:
                    return max(1, math.ceil(locked_until - now))
                self._locked_until.pop(key, None)
                self._failures.pop(key, None)
            self._prune(key, now)
            return None

    def record_failure(self, key: str) -> bool:
        """Record one failure and return ``True`` if it caused a lockout."""

        with self._lock:
            now = self._clock()
            locked_until = self._locked_until.get(key)
            if locked_until is not None:
                if locked_until > now:
                    return False
                self._locked_until.pop(key, None)
                self._failures.pop(key, None)

            self._prune(key, now)
            attempts = self._failures.get(key)
            if attempts is None:
                attempts = deque()
                self._failures[key] = attempts
            attempts.append(now)
            if len(attempts) < self.max_attempts:
                return False

            self._locked_until[key] = now + self._lockout_seconds
            self._failures.pop(key, None)
            return True

    def clear(self, key: str) -> None:
        with self._lock:
            self._failures.pop(key, None)
            self._locked_until.pop(key, None)

    def reset(self) -> None:
        with self._lock:
            self._failures.clear()
            self._locked_until.clear()

    def _prune(self, key: str, now: float) -> None:
        attempts = self._failures.get(key)
        if attempts is None:
            return
        cutoff = now - self._lockout_seconds
        while attempts and attempts[0] <= cutoff:
            attempts.popleft()
        if not attempts:
            self._failures.pop(key, None)
