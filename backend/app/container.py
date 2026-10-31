"""Composition root for repositories, services, and optional persistence."""

from __future__ import annotations

from .catalog import Catalog, get_catalog
from .config import Settings
from .database import Database
from .repositories.in_memory import (
    InMemoryConversationRepository,
    InMemoryProfileRepository,
    InMemoryRefreshTokenRepository,
    InMemoryUserRepository,
)
from .repositories.interfaces import (
    ConversationRepository,
    ProfileRepository,
    RefreshTokenRepository,
    UserRepository,
)
from .repositories.sql import (
    SqlConversationRepository,
    SqlProfileRepository,
    SqlRefreshTokenRepository,
    SqlUserRepository,
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
from .services.email import (
    EmailService,
    SmtpEmailTransport,
    UnavailableEmailTransport,
)
from .services.lockout import AccountLockout
from .services.matching import MatchingService
from .services.security_alerts import SecurityAlertNotifier
from .services.security_events import SecurityEventService
from .services.verification import (
    CAPTCHAService,
    EmailOTPService,
    LoginOTPChallengeService,
)

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
from .transactions import no_transaction


class AppContainer:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self.database: Database | None = None

        self.users: UserRepository
        self.profiles: ProfileRepository
        self.refresh_tokens: RefreshTokenRepository
        self.conversations: ConversationRepository

        snapshot: SnapshotStore
        if settings.storage_backend == "postgres":
            self.database = Database(settings)
            self.users = SqlUserRepository(self.database)
            self.profiles = SqlProfileRepository(self.database)
            self.refresh_tokens = SqlRefreshTokenRepository(self.database)
            self.conversations = SqlConversationRepository(self.database)
            snapshot = NoopSnapshotStore()
        else:
            if settings.persist_to_file:
                snapshot = JsonSnapshotStore(
                    settings.store_path,
                    settings.snapshot_debounce_seconds,
                )
            else:
                snapshot = NoopSnapshotStore()

            self.users = InMemoryUserRepository(
                on_change=snapshot.schedule
            )
            self.profiles = InMemoryProfileRepository(
                on_change=snapshot.schedule
            )
            self.refresh_tokens = InMemoryRefreshTokenRepository(
                on_change=snapshot.schedule
            )
            self.conversations = InMemoryConversationRepository(
                on_change=snapshot.schedule
            )
            snapshot.register("users", self.users)
            snapshot.register("profiles", self.profiles)
            snapshot.register("refresh_tokens", self.refresh_tokens)
            snapshot.register("conversations", self.conversations)
            snapshot.load()
        self.snapshot = snapshot
        self.transaction = (
            self.database.transaction
            if self.database is not None
            else no_transaction
        )

        self.catalog: Catalog = get_catalog()
        photos: PhotoStorage
        chat_media: ChatMediaStorage
        if settings.persist_to_file or settings.storage_backend == "postgres":
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
        self.account_lockout = AccountLockout(
            settings.login_lockout_attempts,
            settings.login_lockout_seconds,
        )
        self.captcha = CAPTCHAService()
        email_transport = (
            SmtpEmailTransport(settings)
            if settings.smtp_host
            else UnavailableEmailTransport()
        )
        self.email = EmailService(email_transport)
        self.security_alerts = SecurityAlertNotifier(self.email)
        self.security_events = SecurityEventService(
            on_event=self.security_alerts.notify
        )
        self.email_otp = EmailOTPService()
        self.login_otp_challenges = LoginOTPChallengeService()
        self.auth = AuthService(
            users=self.users,
            profiles=self.profiles,
            refresh_tokens=self.refresh_tokens,
            passwords=self.passwords,
            tokens=self.tokens,
            rate_limiter=self.login_rate_limiter,
            catalog=self.catalog,
            transaction=self.transaction,
            account_lockout=self.account_lockout,
            security_events=self.security_events,
            email_service=self.email,
            email_otp=self.email_otp,
            login_otp_challenges=self.login_otp_challenges,
            login_otp_required=settings.login_otp_required,
        )
        self.profile = ProfileService(
            users=self.users,
            profiles=self.profiles,
            catalog=self.catalog,
            photos=self.photos,
            transaction=self.transaction,
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
            transaction=self.transaction,
        )

    def close(self) -> None:
        try:
            self.snapshot.close()
        finally:
            try:
                self.security_alerts.close()
            finally:
                if self.database is not None:
                    self.database.dispose()
