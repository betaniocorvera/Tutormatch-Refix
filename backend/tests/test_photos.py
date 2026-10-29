from __future__ import annotations

from io import BytesIO
from uuid import uuid4

from fastapi.testclient import TestClient
from PIL import Image, PngImagePlugin

from app.config import Settings
from app.main import create_app
from app.services.photo_processing import MAX_UPLOAD_BYTES
from app.storage.photos import LocalPhotoStorage
from tests.registration import registration_payload


def _register(
    client: TestClient,
    *,
    email: str = "student@example.com",
    role: str = "student",
    display_name: str = "Maya Chen",
) -> dict:
    response = client.post(
        "/auth/register",
        json=registration_payload(
            email=email,
            role=role,
            display_name=display_name,
        ),
    )
    assert response.status_code == 201
    return response.json()


def _headers(tokens: dict) -> dict[str, str]:
    return {"Authorization": f"Bearer {tokens['access_token']}"}


def _image_bytes(
    *,
    size: tuple[int, int] = (128, 128),
    image_format: str = "PNG",
    metadata: bool = False,
) -> bytes:
    image = Image.new("RGB", size, (200, 40, 20))
    output = BytesIO()
    if metadata:
        info = PngImagePlugin.PngInfo()
        info.add_text("Comment", "secret camera metadata")
        image.save(output, format=image_format, pnginfo=info)
    else:
        image.save(output, format=image_format)
    return output.getvalue()


def test_upload_reencodes_stores_and_serves_a_photo(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)
    user_id = tokens["user"]["id"]
    original = _image_bytes(metadata=True)

    uploaded = client.post(
        "/profile/photo",
        headers=headers,
        files={"file": ("photo.png", original, "image/png")},
    )

    assert uploaded.status_code == 200
    body = uploaded.json()
    assert body["photo_url"] == f"/users/{user_id}/photo"
    # Name, subjects, and area come from registration; the photo is the fourth.
    assert body["completeness"]["filled"] == 4
    assert "a picture" not in body["completeness"]["missing"]

    served = client.get(f"/users/{user_id}/photo", headers=headers)
    assert served.status_code == 200
    assert served.headers["content-type"] == "image/jpeg"
    assert served.content.startswith(b"\xff\xd8")
    assert served.content != original
    assert b"secret camera metadata" not in served.content
    with Image.open(BytesIO(served.content)) as image:
        assert image.format == "JPEG"

    public = client.get(f"/users/{user_id}", headers=headers)
    assert public.status_code == 200
    assert public.json()["photo_url"] == f"/users/{user_id}/photo"

    other = _register(client, email="other@example.com")
    other_view = client.get(
        f"/users/{user_id}/photo",
        headers=_headers(other),
    )
    assert other_view.status_code == 200


def test_photo_is_scaled_down_and_metadata_is_stripped(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    uploaded = client.post(
        "/profile/photo",
        headers=headers,
        files={
            "file": (
                "large.png",
                _image_bytes(size=(1600, 800), metadata=True),
                "image/png",
            )
        },
    )
    assert uploaded.status_code == 200

    served = client.get(
        f"/users/{tokens['user']['id']}/photo",
        headers=headers,
    )
    with Image.open(BytesIO(served.content)) as image:
        assert image.size == (1024, 512)
        assert "Comment" not in image.info


def test_invalid_image_uploads_are_rejected(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    text = client.post(
        "/profile/photo",
        headers=headers,
        files={"file": ("photo.png", b"not an image", "image/png")},
    )
    assert text.status_code == 422

    tiny = client.post(
        "/profile/photo",
        headers=headers,
        files={
            "file": (
                "tiny.png",
                _image_bytes(size=(8, 8)),
                "image/png",
            )
        },
    )
    assert tiny.status_code == 422


def test_animated_images_are_rejected(client: TestClient) -> None:
    tokens = _register(client)
    headers = _headers(tokens)
    frames = [
        Image.new("RGB", (64, 64), (255, 0, 0)),
        Image.new("RGB", (64, 64), (0, 0, 255)),
    ]
    output = BytesIO()
    frames[0].save(
        output,
        format="GIF",
        save_all=True,
        append_images=frames[1:],
        duration=100,
        loop=0,
    )

    response = client.post(
        "/profile/photo",
        headers=headers,
        files={"file": ("moving.gif", output.getvalue(), "image/gif")},
    )

    assert response.status_code == 422


def test_oversized_upload_is_rejected_with_413(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)

    response = client.post(
        "/profile/photo",
        headers=headers,
        files={
            "file": (
                "huge.jpg",
                b"x" * (MAX_UPLOAD_BYTES + 1),
                "image/jpeg",
            )
        },
    )

    assert response.status_code == 413


def test_delete_photo_removes_the_public_url_and_completeness_gap(
    client: TestClient,
) -> None:
    tokens = _register(client)
    headers = _headers(tokens)
    user_id = tokens["user"]["id"]

    assert (
        client.post(
            "/profile/photo",
            headers=headers,
            files={
                "file": (
                    "photo.png",
                    _image_bytes(),
                    "image/png",
                )
            },
        ).status_code
        == 200
    )

    deleted = client.delete("/profile/photo", headers=headers)
    assert deleted.status_code == 204
    assert deleted.content == b""

    missing = client.get(f"/users/{user_id}/photo", headers=headers)
    assert missing.status_code == 404

    profile = client.get("/profile", headers=headers)
    assert profile.status_code == 200
    assert profile.json()["photo_url"] is None
    assert "a picture" in profile.json()["completeness"]["missing"]


def test_photo_routes_require_authentication_and_exist_for_real_users(
    client: TestClient,
) -> None:
    tokens = _register(client)
    user_id = tokens["user"]["id"]

    assert client.get(f"/users/{user_id}/photo").status_code == 401
    assert (
        client.get(
            f"/users/{uuid4()}/photo",
            headers=_headers(tokens),
        ).status_code
        == 404
    )
    assert (
        client.get(
            f"/users/{user_id}/photo",
            headers=_headers(tokens),
        ).status_code
        == 404
    )


def test_photo_and_profile_survive_a_persistent_restart(tmp_path) -> None:
    settings = Settings(
        app_env="test",
        jwt_secret="photo-persist-secret-" + ("x" * 40),
        persist_to_file=True,
        store_path=tmp_path / "store.json",
        upload_path=tmp_path / "uploads",
        snapshot_debounce_seconds=0.0,
    )
    first_app = create_app(settings)
    with TestClient(first_app) as first_client:
        registered = first_client.post(
            "/auth/register",
            json=registration_payload(email="photo-persist@example.com"),
        )
        assert registered.status_code == 201
        access = registered.json()["access_token"]
        uploaded = first_client.post(
            "/profile/photo",
            headers={"Authorization": f"Bearer {access}"},
            files={
                "file": (
                    "photo.png",
                    _image_bytes(),
                    "image/png",
                )
            },
        )
        assert uploaded.status_code == 200

    assert list((tmp_path / "uploads").iterdir())

    second_app = create_app(settings)
    with TestClient(second_app) as second_client:
        login = second_client.post(
            "/auth/login",
            json={
                "email": "photo-persist@example.com",
                "password": "CorrectHorse1!",
            },
        )
        assert login.status_code == 200
        access = login.json()["access_token"]
        headers = {"Authorization": f"Bearer {access}"}
        user_id = login.json()["user"]["id"]

        profile = second_client.get("/profile", headers=headers)
        assert profile.status_code == 200
        assert profile.json()["photo_url"] == f"/users/{user_id}/photo"

        served = second_client.get(
            f"/users/{user_id}/photo",
            headers=headers,
        )
        assert served.status_code == 200
        assert served.headers["content-type"] == "image/jpeg"


def test_local_photo_storage_round_trip(tmp_path) -> None:
    storage = LocalPhotoStorage(tmp_path / "uploads")

    saved = storage.save("user-1", b"jpeg bytes")
    assert saved.data == b"jpeg bytes"
    assert storage.exists("user-1")
    assert storage.get("user-1").data == b"jpeg bytes"

    files = list((tmp_path / "uploads").iterdir())
    assert len(files) == 1
    assert "user-1" not in files[0].name

    assert storage.delete("user-1") is True
    assert storage.exists("user-1") is False
    assert storage.delete("user-1") is False
