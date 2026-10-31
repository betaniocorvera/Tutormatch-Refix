"""SMTP delivery for one-time codes and future transactional email.

The OTP itself is never logged or returned by an API. This module only turns an
already-generated code into an email and hands it to a transport. A missing or
failing SMTP server produces a generic application error, never the SMTP
response or credentials.
"""

from __future__ import annotations

import smtplib
import ssl
from dataclasses import dataclass
from datetime import datetime, timezone
from email.message import EmailMessage
from typing import Protocol

from ..config import Settings
from ..errors import EmailDeliveryFailed, EmailDeliveryUnavailable


@dataclass(frozen=True, slots=True)
class OutboundEmail:
    """A fully-rendered message ready for a transport."""

    to: str
    subject: str
    body: str


class EmailTransport(Protocol):
    """Small boundary so tests can replace SMTP without a network."""

    def send(self, message: OutboundEmail) -> None:
        """Deliver one message or raise an application error."""


class UnavailableEmailTransport:
    """Used when SMTP is not configured.

    The API returns a clear 503 instead of silently accepting an OTP that no
    user can receive.
    """

    def send(self, message: OutboundEmail) -> None:
        raise EmailDeliveryUnavailable()


class SmtpEmailTransport:
    """Deliver messages through a standard SMTP server.

    Port 587 with STARTTLS is the default. For implicit TLS on port 465, set
    ``SMTP_SSL=true`` and ``SMTP_STARTTLS=false``.
    """

    def __init__(self, settings: Settings) -> None:
        self._host = settings.smtp_host
        self._port = settings.smtp_port
        self._username = settings.smtp_username
        self._password = settings.smtp_password
        self._from = settings.smtp_from
        self._starttls = settings.smtp_starttls
        self._ssl = settings.smtp_ssl
        self._timeout = settings.smtp_timeout_seconds

    def send(self, message: OutboundEmail) -> None:
        if not self._host or not self._from:
            raise EmailDeliveryUnavailable()

        email = EmailMessage()
        email["From"] = self._from
        email["To"] = message.to
        email["Subject"] = message.subject
        email.set_content(message.body)

        try:
            context = ssl.create_default_context()
            if self._ssl:
                with smtplib.SMTP_SSL(
                    self._host,
                    self._port,
                    timeout=self._timeout,
                    context=context,
                ) as smtp:
                    self._authenticate(smtp)
                    smtp.send_message(email)
            else:
                with smtplib.SMTP(
                    self._host,
                    self._port,
                    timeout=self._timeout,
                ) as smtp:
                    if self._starttls:
                        smtp.starttls(context=context)
                    self._authenticate(smtp)
                    smtp.send_message(email)
        except (smtplib.SMTPException, OSError) as exc:
            raise EmailDeliveryFailed() from exc

    def _authenticate(self, smtp: smtplib.SMTP) -> None:
        if self._username:
            smtp.login(self._username, self._password)


class EmailService:
    """Render transactional messages and send them through a transport.

    ``transport`` is intentionally public so tests can inject a recorder or a
    failing transport without changing application configuration.
    """

    def __init__(self, transport: EmailTransport) -> None:
        self.transport = transport

    @property
    def is_configured(self) -> bool:
        """Whether a real or injected transport can attempt delivery."""

        return not isinstance(self.transport, UnavailableEmailTransport)

    def send_security_alert(
        self,
        *,
        to: str,
        event_type: str,
        occurred_at: datetime,
    ) -> None:
        """Send a generic account-security notice to the account owner."""

        labels = {
            "login_succeeded": (
                "A new sign-in to your TutorMatch account was completed."
            ),
            "account_locked": (
                "Your TutorMatch account was temporarily locked after "
                "repeated failed sign-in attempts."
            ),
            "login_otp_failed": (
                "Several incorrect verification codes were entered for "
                "your TutorMatch account."
            ),
        }
        label = labels.get(
            event_type,
            "A security event occurred on your TutorMatch account.",
        )
        if occurred_at.tzinfo is None:
            occurred_at = occurred_at.replace(tzinfo=timezone.utc)
        timestamp = occurred_at.astimezone(timezone.utc).strftime(
            "%Y-%m-%d %H:%M UTC"
        )
        body = (
            "TutorMatch security alert\n\n"
            f"{label}\n\n"
            f"Time: {timestamp}\n\n"
            "If this was you, no action is needed. If not, contact "
            "TutorMatch support immediately.\n"
        )
        self.transport.send(
            OutboundEmail(
                to=to,
                subject="TutorMatch security alert",
                body=body,
            )
        )

    def send_otp(
        self,
        *,
        to: str,
        code: str,
        expires_at: datetime,
        purpose: str = "email verification",
        subject: str | None = None,
    ) -> None:
        """Send an OTP to one address.

        The code is included in the email body only. It is never included in
        the subject, logs, or an API response.
        """

        labels = {
            "sign-in": "sign-in",
            "password reset": "password reset",
            "email verification": "verification",
        }
        label = labels.get(purpose.strip().lower(), "verification")
        now = (
            datetime.now(timezone.utc).replace(tzinfo=None)
            if expires_at.tzinfo is None
            else datetime.now(expires_at.tzinfo)
        )
        remaining = expires_at - now
        minutes = max(1, int(remaining.total_seconds() // 60))
        body = (
            f"Your TutorMatch {label} code is {code}.\n\n"
            f"It expires in {minutes} minutes. "
            "If you did not request this, you can ignore this email.\n"
        )
        self.transport.send(
            OutboundEmail(
                to=to,
                subject=subject or f"Your TutorMatch {label} code",
                body=body,
            )
        )
