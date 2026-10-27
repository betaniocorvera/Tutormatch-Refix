from __future__ import annotations

from io import BytesIO
import json

from fastapi.testclient import TestClient
from PIL import Image

from app.config import Settings
from app.main import create_app
from tests.chat_helpers import (
    accept_request,
    create_pair,
    create_request,
    headers,
)


def test_snapshot_round_trip_preserves_conversations(tmp_path) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="chat-snapshot-secret-" + ("x" * 40),
        persist_to_file=True,
        store_path=tmp_path / "store.json",
        upload_path=tmp_path / "uploads",
        snapshot_debounce_seconds=0.0,
    )
    first_app = create_app(settings)
    with TestClient(first_app) as first_client:
        student, tutor = create_pair(first_client)
        request = create_request(first_client, student, tutor)
        conversation_id = request["conversation_id"]
        accept_request(first_client, tutor, conversation_id)
        image_output = BytesIO()
        Image.new("RGB", (48, 48), (30, 120, 200)).save(
            image_output,
            format="PNG",
        )
        image = first_client.post(
            f"/conversations/{conversation_id}/messages/image",
            files={
                "file": (
                    "photo.png",
                    image_output.getvalue(),
                    "image/png",
                )
            },
            headers=headers(student),
        )
        assert image.status_code == 201, image.text
        media_url = image.json()["media_url"]
        sent = first_client.post(
            f"/conversations/{conversation_id}/messages",
            json={"text": "This should survive a restart."},
            headers=headers(student),
        )
        assert sent.status_code == 201

    payload = json.loads(settings.store_path.read_text(encoding="utf-8"))
    assert "conversations" in payload
    assert len(payload["conversations"]) == 1
    stored = payload["conversations"][0]
    assert stored["id"] == conversation_id
    assert stored["status"] == "accepted"
    assert stored["messages"][-1]["text"] == "This should survive a restart."
    assert stored["events"]

    second_app = create_app(settings)
    with TestClient(second_app) as second_client:
        detail = second_client.get(
            f"/conversations/{conversation_id}",
            headers=headers(student),
        )
        assert detail.status_code == 200, detail.text
        body = detail.json()
        assert body["status"] == "accepted"
        assert body["last_message"]["text"] == "This should survive a restart."

        messages = second_client.get(
            f"/conversations/{conversation_id}/messages",
            headers=headers(tutor),
        )
        assert messages.status_code == 200
        assert messages.json()["messages"][-1]["text"] == (
            "This should survive a restart."
        )
        assert messages.json()["unread_count"] == 2

        media = second_client.get(media_url, headers=headers(tutor))
        assert media.status_code == 200, media.text
        assert media.content.startswith(b"\xff\xd8")
