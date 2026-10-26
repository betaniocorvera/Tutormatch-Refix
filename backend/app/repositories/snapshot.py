"""Optional, atomic JSON snapshots for the in-memory repositories.

Disabled by default. When enabled, mutations schedule a debounced write and the
app flushes one final snapshot on shutdown. A temp file plus ``os.replace``
keeps a half-written file from replacing the previous good snapshot.
"""

from __future__ import annotations

import json
import logging
import os
import threading
from pathlib import Path
from typing import Any, Protocol

logger = logging.getLogger(__name__)


class SnapshotRepository(Protocol):
    def export_state(self) -> Any:
        ...

    def import_state(self, state: Any) -> None:
        ...


class SnapshotStore(Protocol):
    def register(self, name: str, repo: SnapshotRepository) -> None:
        ...

    def schedule(self) -> None:
        ...

    def load(self) -> None:
        ...

    def flush(self) -> None:
        ...

    def close(self) -> None:
        ...


class NoopSnapshotStore:
    def register(self, name: str, repo: SnapshotRepository) -> None:
        return None

    def schedule(self) -> None:
        return None

    def load(self) -> None:
        return None

    def flush(self) -> None:
        return None

    def close(self) -> None:
        return None


class JsonSnapshotStore:
    def __init__(
        self,
        path: Path,
        debounce_seconds: float = 0.5,
    ) -> None:
        self._path = Path(path)
        self._debounce_seconds = max(0.0, debounce_seconds)
        self._repos: dict[str, SnapshotRepository] = {}
        self._timer: threading.Timer | None = None
        self._lock = threading.RLock()
        self._closed = False

    def register(self, name: str, repo: SnapshotRepository) -> None:
        with self._lock:
            self._repos[name] = repo

    def schedule(self) -> None:
        with self._lock:
            if self._closed:
                return
            if self._timer is not None:
                self._timer.cancel()
            timer = threading.Timer(
                self._debounce_seconds,
                self._flush_from_timer,
            )
            timer.daemon = True
            self._timer = timer
            timer.start()

    def load(self) -> None:
        with self._lock:
            if not self._path.exists():
                return
            try:
                payload = json.loads(
                    self._path.read_text(encoding="utf-8")
                )
            except (OSError, json.JSONDecodeError) as exc:
                raise RuntimeError(
                    f"Could not read the data snapshot at {self._path}."
                ) from exc
            if not isinstance(payload, dict):
                raise RuntimeError(
                    f"The data snapshot at {self._path} is not a JSON object."
                )
            for name, repo in self._repos.items():
                state = payload.get(name)
                if state is not None:
                    repo.import_state(state)

    def flush(self) -> None:
        with self._lock:
            self._cancel_timer()
            self._write()

    def close(self) -> None:
        with self._lock:
            if self._closed:
                return
            self._closed = True
            self._cancel_timer()
            self._write()

    def _cancel_timer(self) -> None:
        if self._timer is not None:
            self._timer.cancel()
            self._timer = None

    def _flush_from_timer(self) -> None:
        with self._lock:
            self._timer = None
            if self._closed:
                return
            try:
                self._write()
            except Exception:
                # A background save failure must not kill the request process;
                # the next mutation or shutdown will retry.
                logger.exception("Could not write the data snapshot.")

    def _write(self) -> None:
        payload = {
            name: repo.export_state()
            for name, repo in self._repos.items()
        }
        self._path.parent.mkdir(parents=True, exist_ok=True)
        temp_path = self._path.with_name(self._path.name + ".tmp")
        text = json.dumps(
            payload,
            ensure_ascii=False,
            indent=2,
            sort_keys=True,
        )
        temp_path.write_text(text, encoding="utf-8")
        os.replace(temp_path, self._path)
