from __future__ import annotations

from app.services.rate_limit import LoginRateLimiter


class FakeClock:
    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


def test_blocks_after_max_attempts() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=3,
        window_seconds=60,
        clock=clock,
    )

    assert limiter.check("key") is None
    for _ in range(3):
        limiter.record_failure("key")

    assert limiter.check("key") == 60


def test_window_expiry_unblocks() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=2,
        window_seconds=10,
        clock=clock,
    )

    limiter.record_failure("key")
    limiter.record_failure("key")
    assert limiter.check("key") == 10

    clock.advance(10)
    assert limiter.check("key") is None


def test_old_attempts_are_pruned_individually() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=2,
        window_seconds=10,
        clock=clock,
    )

    limiter.record_failure("key")
    clock.advance(6)
    limiter.record_failure("key")
    assert limiter.check("key") == 4

    clock.advance(5)
    assert limiter.check("key") is None


def test_success_clear_resets_the_key() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=2,
        window_seconds=10,
        clock=clock,
    )

    limiter.record_failure("key")
    limiter.record_failure("key")
    assert limiter.check("key") == 10

    limiter.clear("key")
    assert limiter.check("key") is None


def test_keys_are_independent() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=1,
        window_seconds=10,
        clock=clock,
    )

    limiter.record_failure("first")

    assert limiter.check("first") == 10
    assert limiter.check("second") is None


def test_reset_clears_all_keys() -> None:
    clock = FakeClock()
    limiter = LoginRateLimiter(
        max_attempts=1,
        window_seconds=10,
        clock=clock,
    )

    limiter.record_failure("key")
    limiter.reset()

    assert limiter.check("key") is None
