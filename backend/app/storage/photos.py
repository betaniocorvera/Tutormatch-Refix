"""Photo storage behind a small interface.

The profile service only knows about this contract. Tests use the in-memory
implementation; a persistent deployment uses the local implementation, whose
file name is a hash of the user id rather than a caller-supplied path.
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
class StoredPhoto:
    data: bytes
    content_type: str
    updated_at: datetime


class PhotoStorage(ABC):
    @abstractmethod
    def save(
        self,
        user_id: str,
        data: bytes,
        *,
        content_type: str = "image/jpeg",
    ) -> StoredPhoto:
        raise NotImplementedError

    @abstractmethod
    def get(self, user_id: str) -> StoredPhoto | None:
        raise NotImplementedError

    @abstractmethod
    def exists(self, user_id: str) -> bool:
        raise NotImplementedError

    @abstractmethod
    def delete(self, user_id: str) -> bool:
        raise NotImplementedError


class InMemoryPhotoStorage(PhotoStorage):
    def __init__(self) -> None:
        self._photos: dict[str, StoredPhoto] = {}
        self._lock = threading.RLock()

    def save(
        self,
        user_id: str,
        data: bytes,
        *,
        content_type: str = "image/jpeg",
    ) -> StoredPhoto:
        photo = StoredPhoto(
            data=data,
            content_type=content_type,
            updated_at=datetime.now(timezone.utc),
        )
        with self._lock:
            self._photos[user_id] = photo
        return photo

    def get(self, user_id: str) -> StoredPhoto | None:
        with self._lock:
            return self._photos.get(user_id)

    def exists(self, user_id: str) -> bool:
        with self._lock:
            return user_id in self._photos

    def delete(self, user_id: str) -> bool:
        with self._lock:
            return self._photos.pop(user_id, None) is not None


class LocalPhotoStorage(PhotoStorage):
    def __init__(self, root: Path) -> None:
        self._root = Path(root)
        self._lock = threading.RLock()

    def _path(self, user_id: str) -> Path:
        digest = hashlib.sha256(user_id.encode("utf-8")).hexdigest()
        return self._root / f"{digest}.jpg"

    def save(
        self,
        user_id: str,
        data: bytes,
        *,
        content_type: str = "image/jpeg",
    ) -> StoredPhoto:
        path = self._path(user_id)
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
        return StoredPhoto(
            data=data,
            content_type=content_type,
            updated_at=datetime.now(timezone.utc),
        )

    def get(self, user_id: str) -> StoredPhoto | None:
        path = self._path(user_id)
        with self._lock:
            try:
                data = path.read_bytes()
                updated_at = datetime.fromtimestamp(
                    path.stat().st_mtime,
                    tz=timezone.utc,
                )
            except OSError:
                return None
        return StoredPhoto(
            data=data,
            content_type="image/jpeg",
            updated_at=updated_at,
        )

    def exists(self, user_id: str) -> bool:
        with self._lock:
            return self._path(user_id).is_file()

    def delete(self, user_id: str) -> bool:
        with self._lock:
            path = self._path(user_id)
            existed = path.is_file()
            path.unlink(missing_ok=True)
            return existed
