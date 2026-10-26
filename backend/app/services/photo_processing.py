"""Image validation and re-encoding.

The uploaded bytes are treated as hostile. Pillow decodes them, rejects
oversized or animated inputs, applies EXIF orientation, strips all metadata,
and writes a fresh JPEG. The stored file is therefore never the original
upload.
"""

from __future__ import annotations

import warnings
from io import BytesIO

from PIL import Image, ImageOps, UnidentifiedImageError

from ..errors import InvalidPhoto, PhotoTooLarge

MAX_UPLOAD_BYTES = 5 * 1024 * 1024
MAX_PIXELS = 25_000_000
MIN_DIMENSION = 32
MAX_OUTPUT_DIMENSION = 1024
ALLOWED_FORMATS = frozenset({"JPEG", "PNG", "WEBP"})
OUTPUT_CONTENT_TYPE = "image/jpeg"


def reencode_photo(data: bytes) -> bytes:
    """Return a metadata-free JPEG, or raise a generic validation error."""

    if not data:
        raise InvalidPhoto()
    if len(data) > MAX_UPLOAD_BYTES:
        raise PhotoTooLarge()

    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            with Image.open(BytesIO(data)) as opened:
                if opened.format not in ALLOWED_FORMATS:
                    raise InvalidPhoto()
                if getattr(opened, "is_animated", False):
                    raise InvalidPhoto()

                width, height = opened.size
                if width < MIN_DIMENSION or height < MIN_DIMENSION:
                    raise InvalidPhoto()
                if width * height > MAX_PIXELS:
                    raise InvalidPhoto()

                opened.load()
                image = ImageOps.exif_transpose(opened)

                if image.mode in {"RGBA", "LA"} or (
                    image.mode == "P" and "transparency" in image.info
                ):
                    rgba = image.convert("RGBA")
                    background = Image.new(
                        "RGB",
                        rgba.size,
                        (255, 255, 255),
                    )
                    background.paste(rgba, mask=rgba.getchannel("A"))
                    image = background
                else:
                    image = image.convert("RGB")

                image.thumbnail(
                    (MAX_OUTPUT_DIMENSION, MAX_OUTPUT_DIMENSION),
                    Image.Resampling.LANCZOS,
                )

                output = BytesIO()
                image.save(
                    output,
                    format="JPEG",
                    quality=85,
                    optimize=True,
                )
                encoded = output.getvalue()
    except InvalidPhoto:
        raise
    except (
        UnidentifiedImageError,
        Image.DecompressionBombError,
        Image.DecompressionBombWarning,
        OSError,
        ValueError,
    ) as exc:
        raise InvalidPhoto() from exc

    if not encoded:
        raise InvalidPhoto()
    return encoded
