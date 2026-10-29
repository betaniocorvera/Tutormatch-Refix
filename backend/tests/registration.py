"""Shared valid registration payloads for the test suite.

The password meets the production policy: ten characters or more, upper and
lower case, a digit, a symbol, not a common password, and not containing the
email local part or the person's name.
"""

from __future__ import annotations

from app.privacy import PRIVACY_POLICY_VERSION

COMPLIANT_PASSWORD = "CorrectHorse1!"
DEFAULT_SECURITY_QUESTIONS = (
    {"question_id": "first-pet", "answer": "Biscuit"},
    {"question_id": "first-school", "answer": "St Mary's"},
    {"question_id": "favourite-teacher", "answer": "Mrs Santos"},
)


def registration_payload(
    *,
    email: str = "student@example.com",
    password: str = COMPLIANT_PASSWORD,
    role: str = "student",
    display_name: str = "Maya Chen",
    phone: str = "",
    area_id: str = "london-highbury",
    subjects: list[str] | None = None,
    security_questions: list[dict[str, str]] | None = None,
    privacy_consent: bool = True,
    privacy_policy_version: str = PRIVACY_POLICY_VERSION,
) -> dict:
    return {
        "email": email,
        "password": password,
        "role": role,
        "display_name": display_name,
        "phone": phone,
        "area_id": area_id,
        "subjects": ["Calculus"] if subjects is None else subjects,
        "security_questions": (
            [dict(item) for item in DEFAULT_SECURITY_QUESTIONS]
            if security_questions is None
            else security_questions
        ),
        "privacy_consent": privacy_consent,
        "privacy_policy_version": privacy_policy_version,
    }
