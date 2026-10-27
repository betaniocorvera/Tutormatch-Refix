"""Storage for chat images and voice notes.

The message row keeps the content type and display metadata; this layer only
stores bytes under a caller-generated, opaque key. The local implementation
hashes the key before building a path, so a message id can never escape the
upload directory.
"""

from __future__ import annotations

import hashlib
import os
import threading
from abc import ABC, abstractmethod
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4


@dataclass(frozen=True, slots=True)
class StoredChatMedia:
    data: bytes
    updated_at: datetime


class ChatMediaStorage(ABC):
    @abstractmethod
    def save(self, key: str, data: bytes) -> StoredChatMedia:
        raise NotImplementedError

    @abstractmethod
    def get(self, key: str) -> StoredChatMedia | None:
        raise NotImplementedError

    @abstractmethod
    def exists(self, key: str) -> bool:
        raise NotImplementedError

    @abstractmethod
    def delete(self, key: str) -> bool:
        raise NotImplementedError


class InMemoryChatMediaStorage(ChatMediaStorage):
    def __init__(self) -> None:
        self._media: dict[str, StoredChatMedia] = {}
        self._lock = threading.RLock()

    def save(self, key: str, data: bytes) -> StoredChatMedia:
        stored = StoredChatMedia(
            data=data,
            updated_at=datetime.now(timezone.utc),
        )
        with self._lock:
            self._media[key] = stored
        return stored

    def get(self, key: str) -> StoredChatMedia | None:
        with self._lock:
            return self._media.get(key)

    def exists(self, key: str) -> bool:
        with self._lock:
            return key in self._media

    def delete(self, key: str) -> bool:
        with self._lock:
            return self._media.pop(key, None) is not None


class LocalChatMediaStorage(ChatMediaStorage):
    def __init__(self, root: Path) -> None:
        self._root = Path(root)
        self._lock = threading.RLock()

    def _path(self, key: str) -> Path:
        digest = hashlib.sha256(key.encode("utf-8")).hexdigest()
        return self._root / f"{digest}.bin"

    def save(self, key: str, data: bytes) -> StoredChatMedia:
        path = self._path(key)
        with self._lock:
            self._root.mkdir(parents=True, exist_ok=True)
            temp_path = path.with_name(
                f".{path.name}.{uuid4().hex}.tmp"
            )
            try:
                temp_path.write_bytes(data)
                os.replace(temp_path, path)
            finally:
                temp_path.unlink(missing_ok=True)
        return StoredChatMedia(
            data=data,
            updated_at=datetime.now(timezone.utc),
        )

    def get(self, key: str) -> StoredChatMedia | None:
        path = self._path(key)
        with self._lock:
            try:
                data = path.read_bytes()
                updated_at = datetime.fromtimestamp(
                    path.stat().st_mtime,
                    tz=timezone.utc,
                )
            except OSError:
                return None
        return StoredChatMedia(data=data, updated_at=updated_at)

    def exists(self, key: str) -> bool:
        with self._lock:
            return self._path(key).is_file()

    def delete(self, key: str) -> bool:
        with self._lock:
            path = self._path(key)
            existed = path.is_file()
            path.unlink(missing_ok=True)
            return existed
