from __future__ import annotations

from datetime import datetime, timezone

import pytest

from app.services.email import (
    EmailService,
    OutboundEmail,
    UnavailableEmailTransport,
)
from app.services.security_alerts import SecurityAlertNotifier
from app.services.security_events import SecurityEvent, SecurityEventService
from tests.registration import COMPLIANT_PASSWORD


class _RecordingTransport:
    def __init__(self) -> None:
        self.messages: list[OutboundEmail] = []

    def send(self, message: OutboundEmail) -> None:
        self.messages.append(message)


class _ImmediateExecutor:
    def submit(self, fn, *args, **kwargs):
        return fn(*args, **kwargs)

    def shutdown(self, wait: bool = True) -> None:
        return None


def _event(
    event_type: str,
    *,
    email: str | None = "maya@example.com",
    user_id: str | None = "user-1",
) -> SecurityEvent:
    return SecurityEvent(
        id="event-1",
        event_type=event_type,
        created_at=datetime.now(timezone.utc),
        user_id=user_id,
        email=email,
    )


def _notifier(
    transport,
    *,
    clock=None,
    cooldown_seconds: float = 300.0,
) -> SecurityAlertNotifier:
    kwargs = {"clock": clock} if clock is not None else {}
    return SecurityAlertNotifier(
        EmailService(transport),
        executor=_ImmediateExecutor(),
        cooldown_seconds=cooldown_seconds,
        **kwargs,
    )


def test_new_login_sends_a_security_alert() -> None:
    transport = _RecordingTransport()
    notifier = _notifier(transport)

    notifier.notify(_event("login_succeeded"))

    assert len(transport.messages) == 1
    message = transport.messages[0]
    assert message.to == "maya@example.com"
    assert message.subject == "TutorMatch security alert"
    assert "new sign-in" in message.body.lower()


def test_lockout_sends_a_security_alert() -> None:
    transport = _RecordingTransport()
    notifier = _notifier(transport)

    notifier.notify(_event("account_locked"))

    assert len(transport.messages) == 1
    assert "locked" in transport.messages[0].body.lower()


def test_repeated_otp_failures_send_one_alert_at_the_threshold() -> None:
    transport = _RecordingTransport()
    notifier = _notifier(transport)

    notifier.notify(_event("login_otp_failed"))
    notifier.notify(_event("login_otp_failed"))
    assert transport.messages == []

    notifier.notify(_event("login_otp_failed"))

    assert len(transport.messages) == 1
    assert "verification codes" in transport.messages[0].body.lower()


def test_alert_cooldown_prevents_duplicate_emails() -> None:
    now = [100.0]
    transport = _RecordingTransport()
    notifier = _notifier(transport, clock=lambda: now[0])

    notifier.notify(_event("login_succeeded"))
    notifier.notify(_event("login_succeeded"))
    assert len(transport.messages) == 1

    now[0] += 301
    notifier.notify(_event("login_succeeded"))
    assert len(transport.messages) == 2


def test_unknown_accounts_do_not_receive_alerts() -> None:
    transport = _RecordingTransport()
    notifier = _notifier(transport)

    notifier.notify(
        _event(
            "account_locked",
            email="unknown@example.com",
            user_id=None,
        )
    )

    assert transport.messages == []


def test_unconfigured_email_skips_alerts() -> None:
    notifier = SecurityAlertNotifier(
        EmailService(UnavailableEmailTransport()),
        executor=_ImmediateExecutor(),
    )

    notifier.notify(_event("login_succeeded"))

    assert notifier.wait_for_idle(timeout=0.1) is True


def test_delivery_failure_never_raises_into_the_caller() -> None:
    class FailingTransport:
        def send(self, message: OutboundEmail) -> None:
            raise RuntimeError("smtp unavailable")

    notifier = _notifier(FailingTransport())

    notifier.notify(_event("login_succeeded"))


def test_event_listener_failure_does_not_break_event_recording() -> None:
    def fail(event: SecurityEvent) -> None:
        raise RuntimeError("listener failed")

    events = SecurityEventService(on_event=fail)

    event = events.record("login_succeeded", email="maya@example.com")

    assert event.event_type == "login_succeeded"
    assert len(events.events) == 1


def test_invalid_threshold_is_rejected() -> None:
    with pytest.raises(ValueError, match="otp_failure_threshold"):
        SecurityAlertNotifier(
            EmailService(_RecordingTransport()),
            otp_failure_threshold=0,
            executor=_ImmediateExecutor(),
        )


def test_password_login_sends_a_security_alert(
    app,
    client,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201

    response = client.post(
        "/auth/login",
        json={
            "email": "student@example.com",
            "password": COMPLIANT_PASSWORD,
        },
    )

    assert response.status_code == 200
    assert app.state.container.security_alerts.wait_for_idle()
    alerts = [
        message
        for message in recording_email.messages
        if message.subject == "TutorMatch security alert"
    ]
    assert len(alerts) == 1
    assert alerts[0].to == "student@example.com"
    assert "new sign-in" in alerts[0].body.lower()
    assert COMPLIANT_PASSWORD not in alerts[0].body


def test_lockout_sends_a_security_alert(
    app,
    client,
    register,
    recording_email,
) -> None:
    assert register().status_code == 201

    for _ in range(5):
        response = client.post(
            "/auth/login",
            json={
                "email": "student@example.com",
                "password": "wrong password",
            },
        )
        assert response.status_code == 401

    assert app.state.container.security_alerts.wait_for_idle()
    alerts = [
        message
        for message in recording_email.messages
        if message.subject == "TutorMatch security alert"
    ]
    assert len(alerts) == 1
    assert "locked" in alerts[0].body.lower()
