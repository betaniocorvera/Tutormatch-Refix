"""Composition root for repositories, services, and optional persistence."""

from __future__ import annotations

from .catalog import Catalog, get_catalog
from .config import Settings
from .repositories.in_memory import (
    InMemoryConversationRepository,
    InMemoryProfileRepository,
    InMemoryRefreshTokenRepository,
    InMemoryUserRepository,
)
from .repositories.snapshot import (
    JsonSnapshotStore,
    NoopSnapshotStore,
    SnapshotStore,
)
from .security import PasswordHasher, TokenService
from .services.auth import AuthService
from .services.broadcast import ConversationBroadcaster
from .services.chat import ChatService
from .services.matching import MatchingService
from .services.profile import ProfileService
from .services.rate_limit import LoginRateLimiter
from .storage.chat_media import (
    ChatMediaStorage,
    InMemoryChatMediaStorage,
    LocalChatMediaStorage,
)
from .storage.photos import (
    InMemoryPhotoStorage,
    LocalPhotoStorage,
    PhotoStorage,
)


class AppContainer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

        snapshot: SnapshotStore
        if settings.persist_to_file:
            snapshot = JsonSnapshotStore(
                settings.store_path,
                settings.snapshot_debounce_seconds,
            )
        else:
            snapshot = NoopSnapshotStore()
        self.snapshot = snapshot

        self.users = InMemoryUserRepository(
            on_change=self.snapshot.schedule
        )
        self.profiles = InMemoryProfileRepository(
            on_change=self.snapshot.schedule
        )
        self.refresh_tokens = InMemoryRefreshTokenRepository(
            on_change=self.snapshot.schedule
        )
        self.conversations = InMemoryConversationRepository(
            on_change=self.snapshot.schedule
        )
        self.snapshot.register("users", self.users)
        self.snapshot.register("profiles", self.profiles)
        self.snapshot.register("refresh_tokens", self.refresh_tokens)
        self.snapshot.register("conversations", self.conversations)
        self.snapshot.load()

        self.catalog: Catalog = get_catalog()
        photos: PhotoStorage
        chat_media: ChatMediaStorage
        if settings.persist_to_file:
            photos = LocalPhotoStorage(settings.upload_path)
            chat_media = LocalChatMediaStorage(
                settings.upload_path / "chat"
            )
        else:
            photos = InMemoryPhotoStorage()
            chat_media = InMemoryChatMediaStorage()
        self.photos = photos
        self.chat_media = chat_media

        self.passwords = PasswordHasher()
        self.tokens = TokenService(settings)
        self.login_rate_limiter = LoginRateLimiter(
            settings.login_rate_limit_attempts,
            settings.login_rate_limit_window_seconds,
        )
        self.auth = AuthService(
            users=self.users,
            profiles=self.profiles,
            refresh_tokens=self.refresh_tokens,
            passwords=self.passwords,
            tokens=self.tokens,
            rate_limiter=self.login_rate_limiter,
            catalog=self.catalog,
        )
        self.profile = ProfileService(
            users=self.users,
            profiles=self.profiles,
            catalog=self.catalog,
            photos=self.photos,
        )
        self.matching = MatchingService(
            users=self.users,
            profiles=self.profiles,
            catalog=self.catalog,
            profile_service=self.profile,
        )
        self.broadcaster = ConversationBroadcaster()
        self.chat = ChatService(
            users=self.users,
            conversations=self.conversations,
            profile_service=self.profile,
            matching=self.matching,
            catalog=self.catalog,
            media=self.chat_media,
            broadcaster=self.broadcaster,
        )

    def close(self) -> None:
        self.snapshot.close()
