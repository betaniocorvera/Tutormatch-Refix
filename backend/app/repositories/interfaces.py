"""Repository contracts.

The service layer depends only on these interfaces. The in-memory and
PostgreSQL implementations satisfy the same contracts, so auth, profile,
matching, and chat code do not need to know which storage backend is active.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any

from ..models.auth import RefreshToken
from ..models.chat import Conversation
from ..models.profile import Profile
from ..models.user import User


class UserRepository(ABC):
    @abstractmethod
    def get_by_id(self, user_id: str) -> User | None:
        raise NotImplementedError

    @abstractmethod
    def get_by_email(self, email: str) -> User | None:
        raise NotImplementedError

    @abstractmethod
    def add(self, user: User) -> None:
        raise NotImplementedError

    @abstractmethod
    def update(self, user: User) -> None:
        raise NotImplementedError

    @abstractmethod
    def list_all(self) -> list[User]:
        raise NotImplementedError

    @abstractmethod
    def export_state(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def import_state(self, state: list[dict[str, Any]]) -> None:
        raise NotImplementedError


class ProfileRepository(ABC):
    @abstractmethod
    def get_by_user_id(self, user_id: str) -> Profile | None:
        raise NotImplementedError

    @abstractmethod
    def add(self, profile: Profile) -> None:
        raise NotImplementedError

    @abstractmethod
    def update(self, profile: Profile) -> None:
        raise NotImplementedError

    @abstractmethod
    def list_all(self) -> list[Profile]:
        raise NotImplementedError

    @abstractmethod
    def export_state(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def import_state(self, state: list[dict[str, Any]]) -> None:
        raise NotImplementedError


class RefreshTokenRepository(ABC):
    @abstractmethod
    def add(self, token: RefreshToken) -> None:
        raise NotImplementedError

    @abstractmethod
    def get_by_jti(self, jti: str) -> RefreshToken | None:
        raise NotImplementedError

    @abstractmethod
    def revoke(self, jti: str, *, replaced_by_jti: str | None = None) -> None:
        raise NotImplementedError

    @abstractmethod
    def revoke_all_for_user(self, user_id: str) -> None:
        raise NotImplementedError

    @abstractmethod
    def list_all(self) -> list[RefreshToken]:
        raise NotImplementedError

    @abstractmethod
    def export_state(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def import_state(self, state: list[dict[str, Any]]) -> None:
        raise NotImplementedError


class ConversationRepository(ABC):
    @abstractmethod
    def get_by_id(self, conversation_id: str) -> Conversation | None:
        raise NotImplementedError

    @abstractmethod
    def get_between(
        self,
        first_user_id: str,
        second_user_id: str,
    ) -> Conversation | None:
        raise NotImplementedError

    @abstractmethod
    def add(self, conversation: Conversation) -> None:
        raise NotImplementedError

    @abstractmethod
    def update(self, conversation: Conversation) -> None:
        raise NotImplementedError

    @abstractmethod
    def list_all(self) -> list[Conversation]:
        raise NotImplementedError

    @abstractmethod
    def export_state(self) -> list[dict[str, Any]]:
        raise NotImplementedError

    @abstractmethod
    def import_state(self, state: list[dict[str, Any]]) -> None:
        raise NotImplementedError
