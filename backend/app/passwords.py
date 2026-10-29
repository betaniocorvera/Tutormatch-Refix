"""Password policy and security-answer normalization.

Both helpers are deliberately free of request or model imports so the Pydantic
models and the auth service can share one implementation. No error message ever
contains the submitted password or answer.
"""

from __future__ import annotations

import re
import string

# A deliberately small built-in list. It catches the passwords that show up in
# every credential-stuffing list without pretending to be a full breach corpus.
COMMON_PASSWORDS = frozenset(
    {
        "1234567890",
        "123456789",
        "12345678",
        "password",
        "password1",
        "password123",
        "password123!",
        "qwerty",
        "qwerty123",
        "qwertyuiop",
        "letmein",
        "welcome",
        "welcome1",
        "admin",
        "admin123",
        "iloveyou",
        "monkey",
        "dragon",
        "football",
        "baseball",
        "abc123",
        "111111",
        "123123",
        "000000",
        "sunshine",
        "princess",
        "trustno1",
        "master",
        "shadow",
        "superman",
        "batman",
        "starwars",
        "whatever",
        "freedom",
        "hello",
        "charlie",
        "donald",
        "passw0rd",
        "p@ssw0rd",
        "1q2w3e4r",
        "zaq12wsx",
        "tutormatch",
        "tutormatch1",
        "tutormatch123",
    }
)

_NAME_SEPARATORS = re.compile(r"[\s\-'.]+")


def validate_password_policy(
    password: str,
    *,
    email: str,
    display_name: str,
) -> None:
    """Raise ``ValueError`` when a new password does not meet the policy."""

    if len(password) < 10:
        raise ValueError("Password must be at least 10 characters.")
    if not any(character.islower() for character in password):
        raise ValueError("Password must include a lower-case letter.")
    if not any(character.isupper() for character in password):
        raise ValueError("Password must include an upper-case letter.")
    if not any(character.isdigit() for character in password):
        raise ValueError("Password must include a digit.")
    if not any(character in string.punctuation for character in password):
        raise ValueError("Password must include a symbol.")
    if password.casefold() in COMMON_PASSWORDS:
        raise ValueError("Choose a less common password.")

    folded = password.casefold()
    local_part = email.split("@", 1)[0].strip().casefold()
    if len(local_part) >= 3 and local_part in folded:
        raise ValueError("Password must not contain your email address.")

    name = display_name.strip().casefold()
    if len(name) >= 3 and name in folded:
        raise ValueError("Password must not contain your name.")
    for token in _NAME_SEPARATORS.split(name):
        if len(token) >= 3 and token in folded:
            raise ValueError("Password must not contain your name.")


def normalize_security_answer(value: str) -> str:
    """Trim, lower-case, and collapse whitespace before hashing an answer."""

    return " ".join(value.strip().lower().split())
