from __future__ import annotations

from io import BytesIO
import wave

from fastapi.testclient import TestClient
from PIL import Image, PngImagePlugin

from app.services.chat_media import (
    MAX_CHAT_IMAGE_BYTES,
    MAX_CHAT_VOICE_BYTES,
)
from tests.chat_helpers import (
    accepted_conversation,
    create_pair,
    create_request,
    headers,
    third_user,
)


def _image_bytes() -> bytes:
    output = BytesIO()
    metadata = PngImagePlugin.PngInfo()
    metadata.add_text("Comment", "should be stripped")
    Image.new("RGB", (80, 48), (30, 120, 200)).save(
        output,
        format="PNG",
        pnginfo=metadata,
    )
    return output.getvalue()


def _wav_bytes(seconds: int = 2) -> bytes:
    output = BytesIO()
    with wave.open(output, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(8000)
        audio.writeframes(b"\x00\x00" * (8000 * seconds))
    return output.getvalue()


def test_image_upload_is_reencoded_and_served_only_to_participants(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    response = client.post(
        f"/conversations/{conversation_id}/messages/image",
        files={"file": ("photo.png", _image_bytes(), "image/png")},
        headers=headers(student),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["kind"] == "image"
    assert body["text"] == "Photo"
    assert body["from_me"] is True
    assert body["media_url"].endswith("/media")
    assert body["media_content_type"] == "image/jpeg"
    assert body["image_width"] == 80
    assert body["image_height"] == 48

    media = client.get(
        body["media_url"],
        headers=headers(tutor),
    )
    assert media.status_code == 200
    assert media.headers["content-type"].startswith("image/jpeg")
    assert media.content.startswith(b"\xff\xd8")
    with Image.open(BytesIO(media.content)) as image:
        assert image.size == (80, 48)
        assert "Comment" not in image.info

    outsider = third_user(client, role="tutor", tag="-media")
    assert (
        client.get(
            body["media_url"],
            headers=headers(outsider),
        ).status_code
        == 404
    )


def test_image_upload_validation_and_locked_chat(
    client: TestClient,
) -> None:
    student, tutor = create_pair(client)
    request = create_request(client, student, tutor)
    conversation_id = request["conversation_id"]

    pending = client.post(
        f"/conversations/{conversation_id}/messages/image",
        files={"file": ("photo.png", _image_bytes(), "image/png")},
        headers=headers(student),
    )
    assert pending.status_code == 409

    assert (
        client.post(
            f"/requests/{conversation_id}/accept",
            headers=headers(tutor),
        ).status_code
        == 200
    )

    invalid = client.post(
        f"/conversations/{conversation_id}/messages/image",
        files={"file": ("photo.png", b"not an image", "image/png")},
        headers=headers(student),
    )
    assert invalid.status_code == 422

    too_large = client.post(
        f"/conversations/{conversation_id}/messages/image",
        files={
            "file": (
                "photo.png",
                b"x" * (MAX_CHAT_IMAGE_BYTES + 1),
                "image/png",
            )
        },
        headers=headers(student),
    )
    assert too_large.status_code == 413


def test_voice_upload_validates_header_size_and_duration(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    audio = _wav_bytes(seconds=2)
    response = client.post(
        f"/conversations/{conversation_id}/messages/voice",
        files={"file": ("voice.wav", audio, "audio/wav")},
        data={"duration_seconds": "2"},
        headers=headers(student),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["kind"] == "voice"
    assert body["voice_seconds"] == 2
    assert body["text"] == "Voice note · 0:02"
    assert body["media_content_type"] == "audio/wav"

    media = client.get(body["media_url"], headers=headers(tutor))
    assert media.status_code == 200
    assert media.headers["content-type"].startswith("audio/wav")
    assert media.content == audio

    invalid = client.post(
        f"/conversations/{conversation_id}/messages/voice",
        files={"file": ("voice.wav", b"not audio", "audio/wav")},
        data={"duration_seconds": "2"},
        headers=headers(student),
    )
    assert invalid.status_code == 422

    mismatch = client.post(
        f"/conversations/{conversation_id}/messages/voice",
        files={"file": ("voice.wav", audio, "audio/wav")},
        data={"duration_seconds": "20"},
        headers=headers(student),
    )
    assert mismatch.status_code == 422

    too_long = client.post(
        f"/conversations/{conversation_id}/messages/voice",
        files={"file": ("voice.wav", audio, "audio/wav")},
        data={"duration_seconds": "301"},
        headers=headers(student),
    )
    assert too_long.status_code == 422

    too_large = client.post(
        f"/conversations/{conversation_id}/messages/voice",
        files={
            "file": (
                "voice.wav",
                b"x" * (MAX_CHAT_VOICE_BYTES + 1),
                "audio/wav",
            )
        },
        data={"duration_seconds": "2"},
        headers=headers(student),
    )
    assert too_large.status_code == 413


def test_simulated_voice_note_keeps_the_prototype_flow(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    response = client.post(
        f"/conversations/{conversation_id}/messages/voice-note",
        json={"duration_seconds": 18},
        headers=headers(student),
    )
    assert response.status_code == 201, response.text
    body = response.json()
    assert body["kind"] == "voice"
    assert body["voice_seconds"] == 18
    assert body["text"] == "Voice note · 0:18"
    assert body["media_url"] is None

    invalid = client.post(
        f"/conversations/{conversation_id}/messages/voice-note",
        json={"duration_seconds": 0},
        headers=headers(student),
    )
    assert invalid.status_code == 422


def test_media_requires_a_message_with_an_attachment(
    client: TestClient,
) -> None:
    student, tutor, conversation_id = accepted_conversation(client)
    sent = client.post(
        f"/conversations/{conversation_id}/messages",
        json={"text": "No attachment here."},
        headers=headers(student),
    )
    assert sent.status_code == 201
    message_id = sent.json()["id"]

    assert (
        client.get(
            f"/conversations/{conversation_id}/messages/{message_id}/media",
            headers=headers(tutor),
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/conversations/{conversation_id}/messages/missing/media",
            headers=headers(tutor),
        ).status_code
        == 404
    )
