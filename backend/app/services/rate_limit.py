"""In-memory login rate limiting.

Keys are normally ``client-ip|email``. A sliding window is used so a burst of
failed attempts cannot be hidden by a fixed-window boundary. This is
single-process state; a multi-worker deployment would replace it with Redis or
a database-backed limiter.
"""

from __future__ import annotations

import math
import threading
import time
from collections import deque
from collections.abc import Callable


class LoginRateLimiter:
    def __init__(
        self,
        max_attempts: int,
        window_seconds: int,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        if max_attempts <= 0:
            raise ValueError("max_attempts must be positive")
        if window_seconds <= 0:
            raise ValueError("window_seconds must be positive")
        self._max_attempts = max_attempts
        self._window_seconds = float(window_seconds)
        self._clock = clock
        self._attempts: dict[str, deque[float]] = {}
        self._lock = threading.Lock()

    def check(self, key: str) -> int | None:
        """Return retry-after seconds when blocked, otherwise ``None``."""
        with self._lock:
            now = self._clock()
            attempts = self._prune(key, now)
            if attempts is None or len(attempts) < self._max_attempts:
                return None
            retry_after = self._window_seconds - (now - attempts[0])
            return max(1, math.ceil(retry_after))

    def record_failure(self, key: str) -> None:
        with self._lock:
            now = self._clock()
            attempts = self._prune(key, now)
            if attempts is None:
                attempts = deque()
                self._attempts[key] = attempts
            attempts.append(now)

    def clear(self, key: str) -> None:
        with self._lock:
            self._attempts.pop(key, None)

    def reset(self) -> None:
        with self._lock:
            self._attempts.clear()

    def _prune(self, key: str, now: float) -> deque[float] | None:
        attempts = self._attempts.get(key)
        if attempts is None:
            return None
        cutoff = now - self._window_seconds
        while attempts and attempts[0] <= cutoff:
            attempts.popleft()
        if not attempts:
            self._attempts.pop(key, None)
            return None
        return attempts
