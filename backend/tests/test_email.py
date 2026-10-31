from __future__ import annotations

import smtplib
from datetime import datetime, timedelta, timezone

import pytest

from app.config import Settings
from app.errors import EmailDeliveryFailed, EmailDeliveryUnavailable
from app.services.email import (
    EmailService,
    OutboundEmail,
    SmtpEmailTransport,
    UnavailableEmailTransport,
)


class _RecordingTransport:
    def __init__(self) -> None:
        self.messages: list[OutboundEmail] = []

    def send(self, message: OutboundEmail) -> None:
        self.messages.append(message)


class _FakeSMTP:
    instances: list["_FakeSMTP"] = []

    def __init__(
        self,
        host: str,
        port: int,
        timeout: float | None = None,
        **kwargs,
    ) -> None:
        self.host = host
        self.port = port
        self.timeout = timeout
        self.started_tls = False
        self.login_args: tuple[str, str] | None = None
        self.message = None
        self.instances.append(self)

    def __enter__(self) -> "_FakeSMTP":
        return self

    def __exit__(self, *args) -> None:
        return None

    def starttls(self, *, context) -> None:
        self.started_tls = True

    def login(self, username: str, password: str) -> None:
        self.login_args = (username, password)

    def send_message(self, message) -> None:
        self.message = message


def _smtp_settings(**overrides) -> Settings:
    return Settings(
        jwt_secret="s" * 64,
        smtp_host="smtp.example.com",
        smtp_from="no-reply@example.com",
        **overrides,
    )


def test_email_service_puts_the_code_only_in_the_body() -> None:
    transport = _RecordingTransport()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    EmailService(transport).send_otp(
        to="maya@example.com",
        code="123456",
        expires_at=expires_at,
        purpose="sign-in",
    )

    message = transport.messages[0]
    assert message.to == "maya@example.com"
    assert "123456" in message.body
    assert "123456" not in message.subject


def test_password_reset_otp_uses_a_password_reset_subject() -> None:
    transport = _RecordingTransport()
    expires_at = datetime.now(timezone.utc) + timedelta(minutes=10)

    EmailService(transport).send_otp(
        to="maya@example.com",
        code="123456",
        expires_at=expires_at,
        purpose="password reset",
    )

    message = transport.messages[0]
    assert "password reset" in message.subject.lower()
    assert "123456" in message.body
    assert "123456" not in message.subject


def test_unavailable_transport_returns_a_generic_error() -> None:
    with pytest.raises(EmailDeliveryUnavailable):
        UnavailableEmailTransport().send(
            OutboundEmail(
                to="maya@example.com",
                subject="Hello",
                body="Body",
            )
        )


def test_smtp_transport_uses_starttls_and_authentication(monkeypatch) -> None:
    _FakeSMTP.instances.clear()
    monkeypatch.setattr(smtplib, "SMTP", _FakeSMTP)
    transport = SmtpEmailTransport(
        _smtp_settings(
            smtp_username="mailer",
            smtp_password="smtp-secret",
        )
    )

    transport.send(
        OutboundEmail(
            to="maya@example.com",
            subject="TutorMatch test",
            body="Hello from the test.",
        )
    )

    fake = _FakeSMTP.instances[-1]
    assert fake.host == "smtp.example.com"
    assert fake.port == 587
    assert fake.started_tls is True
    assert fake.login_args == ("mailer", "smtp-secret")
    assert fake.message["From"] == "no-reply@example.com"
    assert fake.message["To"] == "maya@example.com"
    assert fake.message["Subject"] == "TutorMatch test"
    assert "Hello from the test." in fake.message.get_content()


def test_smtp_transport_supports_implicit_tls(monkeypatch) -> None:
    class FakeSMTPSSL(_FakeSMTP):
        pass

    FakeSMTPSSL.instances = []
    monkeypatch.setattr(smtplib, "SMTP_SSL", FakeSMTPSSL)
    transport = SmtpEmailTransport(
        _smtp_settings(
            smtp_ssl=True,
            smtp_starttls=False,
        )
    )

    transport.send(
        OutboundEmail(
            to="maya@example.com",
            subject="TutorMatch test",
            body="Hello from the test.",
        )
    )

    fake = FakeSMTPSSL.instances[-1]
    assert fake.started_tls is False
    assert fake.message["To"] == "maya@example.com"


def test_smtp_transport_hides_server_failures(monkeypatch) -> None:
    class FailingSMTP(_FakeSMTP):
        def send_message(self, message) -> None:
            raise smtplib.SMTPException("server details")

    monkeypatch.setattr(smtplib, "SMTP", FailingSMTP)
    transport = SmtpEmailTransport(_smtp_settings())

    with pytest.raises(EmailDeliveryFailed) as exc_info:
        transport.send(
            OutboundEmail(
                to="maya@example.com",
                subject="TutorMatch test",
                body="Hello from the test.",
            )
        )

    assert "server details" not in str(exc_info.value)
