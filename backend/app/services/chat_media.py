"""Validation and preparation for chat image and voice uploads.

Images are decoded and re-encoded by the same metadata-stripping pipeline used
for profile photos. Voice notes are checked for a known container signature,
size, and a bounded duration. WAV duration is read from the file; compressed
formats are not decoded here, so their duration is the bounded client value.
"""

from __future__ import annotations

import wave
from dataclasses import dataclass
from datetime import datetime
from io import BytesIO

from PIL import Image, UnidentifiedImageError

from ..errors import (
    AttachmentTooLarge,
    InvalidAttachment,
    InvalidPhoto,
    PhotoTooLarge,
)
from ..models.chat import MAX_VOICE_SECONDS, CallKind
from .photo_processing import reencode_photo

MAX_CHAT_IMAGE_BYTES = 5 * 1024 * 1024
MAX_CHAT_VOICE_BYTES = 10 * 1024 * 1024

_AUDIO_ALIASES = {
    "audio/wav": "wav",
    "audio/wave": "wav",
    "audio/x-wav": "wav",
    "audio/ogg": "ogg",
    "audio/webm": "webm",
    "audio/mpeg": "mp3",
    "audio/mp3": "mp3",
    "audio/mp4": "mp4",
    "audio/m4a": "mp4",
    "audio/x-m4a": "mp4",
    "audio/aac": "aac",
}

_DAY_NAMES = (
    "Mon",
    "Tue",
    "Wed",
    "Thu",
    "Fri",
    "Sat",
    "Sun",
)
_MONTH_NAMES = (
    "Jan",
    "Feb",
    "Mar",
    "Apr",
    "May",
    "Jun",
    "Jul",
    "Aug",
    "Sep",
    "Oct",
    "Nov",
    "Dec",
)


@dataclass(frozen=True, slots=True)
class PreparedImage:
    data: bytes
    content_type: str
    filename: str
    width: int
    height: int


@dataclass(frozen=True, slots=True)
class PreparedVoice:
    data: bytes
    content_type: str
    filename: str
    seconds: int


def prepare_image(data: bytes) -> PreparedImage:
    if not data:
        raise InvalidAttachment()
    if len(data) > MAX_CHAT_IMAGE_BYTES:
        raise AttachmentTooLarge("That image is too large. Choose one under 5 MB.")
    try:
        encoded = reencode_photo(data)
    except PhotoTooLarge as exc:
        raise AttachmentTooLarge(
            "That image is too large. Choose one under 5 MB."
        ) from exc
    except InvalidPhoto as exc:
        raise InvalidAttachment("That image is not a supported image.") from exc

    try:
        with Image.open(BytesIO(encoded)) as image:
            width, height = image.size
    except (UnidentifiedImageError, OSError, ValueError) as exc:
        raise InvalidAttachment("That image is not a supported image.") from exc

    return PreparedImage(
        data=encoded,
        content_type="image/jpeg",
        filename="photo.jpg",
        width=width,
        height=height,
    )


def prepare_voice(
    data: bytes,
    *,
    content_type: str,
    duration_seconds: int,
) -> PreparedVoice:
    if not data:
        raise InvalidAttachment("Choose an audio file first.")
    if len(data) > MAX_CHAT_VOICE_BYTES:
        raise AttachmentTooLarge(
            "That voice note is too large. Choose one under 10 MB."
        )
    if not 1 <= duration_seconds <= MAX_VOICE_SECONDS:
        raise InvalidAttachment(
            f"Voice notes must be between 1 and {MAX_VOICE_SECONDS} seconds."
        )

    detected = _detect_audio(data)
    if detected is None:
        raise InvalidAttachment("That file is not a supported voice note.")

    detected_type, extension = detected
    declared = (content_type or "").split(";", 1)[0].strip().lower()
    if declared and declared not in {"", "application/octet-stream"}:
        declared_family = _AUDIO_ALIASES.get(declared)
        if declared_family is None or declared_family != _AUDIO_ALIASES[detected_type]:
            raise InvalidAttachment(
                "The audio file does not match its declared type."
            )

    if detected_type == "audio/wav":
        actual = _wav_duration(data)
        if actual is None or actual < 1 or actual > MAX_VOICE_SECONDS:
            raise InvalidAttachment("That voice note is not a valid duration.")
        rounded = int(actual + 0.5)
        if abs(actual - duration_seconds) > 2:
            raise InvalidAttachment(
                "The voice note duration does not match the file."
            )
        seconds = max(1, rounded)
    else:
        seconds = duration_seconds

    return PreparedVoice(
        data=data,
        content_type=detected_type,
        filename=f"voice.{extension}",
        seconds=seconds,
    )


def format_voice_text(seconds: int) -> str:
    return f"Voice note · {seconds // 60}:{seconds % 60:02d}"


def format_call_text(
    kind: CallKind,
    *,
    connected: bool,
    duration_seconds: int,
) -> str:
    if not connected:
        return "Missed call"
    label = "Video call" if kind is CallKind.video else "Voice call"
    return (
        f"{label} · {duration_seconds // 60}:{duration_seconds % 60:02d}"
    )


def format_session_text(proposed_for: datetime) -> str:
    return (
        "Session proposed · "
        f"{_DAY_NAMES[proposed_for.weekday()]} {proposed_for.day:02d} "
        f"{_MONTH_NAMES[proposed_for.month - 1]} · "
        f"{proposed_for:%H:%M}"
    )


def _detect_audio(data: bytes) -> tuple[str, str] | None:
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WAVE":
        return "audio/wav", "wav"
    if data[:4] == b"OggS":
        return "audio/ogg", "ogg"
    if data[:4] == b"\x1aE\xdf\xa3":
        return "audio/webm", "webm"
    if data[:3] == b"ID3" or data[:2] in {
        b"\xff\xfb",
        b"\xff\xf3",
        b"\xff\xf2",
        b"\xff\xfa",
    }:
        return "audio/mpeg", "mp3"
    if len(data) >= 12 and data[4:8] == b"ftyp":
        return "audio/mp4", "m4a"
    if (
        len(data) >= 2
        and data[0] == 0xFF
        and (data[1] & 0xF6) == 0xF0
    ):
        return "audio/aac", "aac"
    return None


def _wav_duration(data: bytes) -> float | None:
    try:
        with wave.open(BytesIO(data), "rb") as audio:
            frames = audio.getnframes()
            rate = audio.getframerate()
            if frames <= 0 or rate <= 0:
                return None
            return frames / float(rate)
    except (wave.Error, EOFError, OSError, ValueError):
        return None
