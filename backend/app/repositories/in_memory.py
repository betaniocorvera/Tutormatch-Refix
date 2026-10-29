"""In-memory repository implementations.

They intentionally expose export/import methods so the optional JSON snapshot
can persist them. The PostgreSQL implementations in ``sql.py`` satisfy the same
interfaces and do not use the snapshot helpers.
"""

from __future__ import annotations

import threading
from collections.abc import Callable
from datetime import datetime, timezone
from typing import Any

from ..errors import DuplicateEmailError
from ..models.auth import RefreshToken
from ..models.chat import Conversation
from ..models.profile import Profile
from ..models.user import User
from .interfaces import (
    ConversationRepository,
    ProfileRepository,
    RefreshTokenRepository,
    UserRepository,
)

ChangeCallback = Callable[[], None]


def _noop() -> None:
    return None


def _normalized_email(email: object) -> str:
    return str(email).strip().lower()


class InMemoryUserRepository(UserRepository):
    def __init__(self, on_change: ChangeCallback | None = None) -> None:
        self._users: dict[str, User] = {}
        self._email_index: dict[str, str] = {}
        self._on_change = on_change or _noop
        self._lock = threading.RLock()

    def get_by_id(self, user_id: str) -> User | None:
        with self._lock:
            return self._users.get(user_id)

    def get_by_email(self, email: str) -> User | None:
        with self._lock:
            user_id = self._email_index.get(_normalized_email(email))
            return self._users.get(user_id) if user_id else None

    def add(self, user: User) -> None:
        email = _normalized_email(user.email)
        with self._lock:
            if email in self._email_index:
                raise DuplicateEmailError(email)
            self._users[user.id] = user
            self._email_index[email] = user.id
        self._on_change()

    def update(self, user: User) -> None:
        with self._lock:
            existing = self._users.get(user.id)
            if existing is None:
                raise KeyError(f"Unknown user: {user.id}")
            old_email = _normalized_email(existing.email)
            new_email = _normalized_email(user.email)
            if old_email != new_email:
                owner = self._email_index.get(new_email)
                if owner is not None and owner != user.id:
                    raise DuplicateEmailError(new_email)
                self._email_index.pop(old_email, None)
                self._email_index[new_email] = user.id
            self._users[user.id] = user
        self._on_change()

    def list_all(self) -> list[User]:
        with self._lock:
            return list(self._users.values())

    def export_state(self) -> list[dict[str, Any]]:
        with self._lock:
            return [
                user.model_dump(mode="json")
                for user in self._users.values()
            ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        # Loading a snapshot must not schedule another save.
        with self._lock:
            self._users.clear()
            self._email_index.clear()
            for item in state:
                user = User.model_validate(item)
                email = _normalized_email(user.email)
                self._users[user.id] = user
                self._email_index[email] = user.id


class InMemoryProfileRepository(ProfileRepository):
    def __init__(self, on_change: ChangeCallback | None = None) -> None:
        self._profiles: dict[str, Profile] = {}
        self._on_change = on_change or _noop
        self._lock = threading.RLock()

    def get_by_user_id(self, user_id: str) -> Profile | None:
        with self._lock:
            return self._profiles.get(user_id)

    def add(self, profile: Profile) -> None:
        with self._lock:
            if profile.user_id in self._profiles:
                raise ValueError(
                    f"Profile already exists for user: {profile.user_id}"
                )
            self._profiles[profile.user_id] = profile
        self._on_change()

    def update(self, profile: Profile) -> None:
        with self._lock:
            if profile.user_id not in self._profiles:
                raise KeyError(
                    f"Unknown profile for user: {profile.user_id}"
                )
            self._profiles[profile.user_id] = profile
        self._on_change()

    def list_all(self) -> list[Profile]:
        with self._lock:
            return list(self._profiles.values())

    def export_state(self) -> list[dict[str, Any]]:
        with self._lock:
            return [
                profile.model_dump(mode="json")
                for profile in self._profiles.values()
            ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        with self._lock:
            self._profiles.clear()
            for item in state:
                profile = Profile.model_validate(item)
                self._profiles[profile.user_id] = profile


class InMemoryRefreshTokenRepository(RefreshTokenRepository):
    def __init__(self, on_change: ChangeCallback | None = None) -> None:
        self._tokens: dict[str, RefreshToken] = {}
        self._on_change = on_change or _noop
        self._lock = threading.RLock()

    def add(self, token: RefreshToken) -> None:
        with self._lock:
            if token.jti in self._tokens:
                raise ValueError(
                    f"Duplicate refresh token id: {token.jti}"
                )
            self._tokens[token.jti] = token
        self._on_change()

    def get_by_jti(self, jti: str) -> RefreshToken | None:
        with self._lock:
            return self._tokens.get(jti)

    def revoke(self, jti: str, *, replaced_by_jti: str | None = None) -> None:
        changed = False
        with self._lock:
            token = self._tokens.get(jti)
            if token is not None and token.revoked_at is None:
                self._tokens[jti] = token.model_copy(
                    update={
                        "revoked_at": datetime.now(timezone.utc),
                        "replaced_by_jti": replaced_by_jti,
                    }
                )
                changed = True
        if changed:
            self._on_change()

    def revoke_all_for_user(self, user_id: str) -> None:
        now = datetime.now(timezone.utc)
        changed = False
        with self._lock:
            for jti, token in list(self._tokens.items()):
                if token.user_id == user_id and token.revoked_at is None:
                    self._tokens[jti] = token.model_copy(
                        update={"revoked_at": now}
                    )
                    changed = True
        if changed:
            self._on_change()

    def list_all(self) -> list[RefreshToken]:
        with self._lock:
            return list(self._tokens.values())

    def export_state(self) -> list[dict[str, Any]]:
        with self._lock:
            return [
                token.model_dump(mode="json")
                for token in self._tokens.values()
            ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        with self._lock:
            self._tokens.clear()
            for item in state:
                token = RefreshToken.model_validate(item)
                self._tokens[token.jti] = token


class InMemoryConversationRepository(ConversationRepository):
    def __init__(self, on_change: ChangeCallback | None = None) -> None:
        self._conversations: dict[str, Conversation] = {}
        self._on_change = on_change or _noop
        self._lock = threading.RLock()

    def get_by_id(self, conversation_id: str) -> Conversation | None:
        with self._lock:
            return self._conversations.get(conversation_id)

    def get_between(
        self,
        first_user_id: str,
        second_user_id: str,
    ) -> Conversation | None:
        pair = {first_user_id, second_user_id}
        if len(pair) != 2:
            return None
        with self._lock:
            for conversation in self._conversations.values():
                if {
                    conversation.student_id,
                    conversation.tutor_id,
                } == pair:
                    return conversation
        return None

    def add(self, conversation: Conversation) -> None:
        with self._lock:
            if conversation.id in self._conversations:
                raise ValueError(
                    f"Conversation already exists: {conversation.id}"
                )
            self._conversations[conversation.id] = conversation
        self._on_change()

    def update(self, conversation: Conversation) -> None:
        with self._lock:
            if conversation.id not in self._conversations:
                raise KeyError(
                    f"Unknown conversation: {conversation.id}"
                )
            self._conversations[conversation.id] = conversation
        self._on_change()

    def list_all(self) -> list[Conversation]:
        with self._lock:
            return list(self._conversations.values())

    def export_state(self) -> list[dict[str, Any]]:
        with self._lock:
            return [
                conversation.model_dump(mode="json")
                for conversation in self._conversations.values()
            ]

    def import_state(self, state: list[dict[str, Any]]) -> None:
        with self._lock:
            self._conversations.clear()
            for item in state:
                conversation = Conversation.model_validate(item)
                self._conversations[conversation.id] = conversation
