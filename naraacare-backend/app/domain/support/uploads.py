"""Support screenshot hardening (doc 07 T21, OQ-51).

Every check runs before anything is stored, and the original bytes are never stored:
1. Size: at most 10 MB (the body-size middleware already caps the request).
2. Magic bytes: PNG or JPEG signatures only; the client's content type and file name are ignored
   for this decision (the name is validated as ``SafeFileName`` and then dropped).
3. Decode with Pillow under a pixel cap (``MAX_IMAGE_PIXELS``; a larger image is treated as a
   decompression bomb) and fully load it, so truncated or polyglot files fail here.
4. Re-encode from pixels only into a fresh PNG / JPEG: EXIF (location, device), ICC and any trailing
   or embedded data are gone. The stored key is random (``support/<uuid>.png|jpg``).
"""

from __future__ import annotations

import io
import warnings
from dataclasses import dataclass

from PIL import Image, ImageOps

MAX_BYTES = 10 * 1024 * 1024
MAX_PIXELS = 40_000_000  # e.g. 8000 x 5000; phone screenshots are far below this
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"
JPEG_MAGIC = b"\xff\xd8\xff"


class UploadRejectedError(ValueError):
    """The file is not an acceptable image (the reason is a fixed code, never file content)."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True, slots=True)
class CleanImage:
    data: bytes
    extension: str  # png | jpg


def _kind(data: bytes) -> str:
    if data.startswith(PNG_MAGIC):
        return "png"
    if data.startswith(JPEG_MAGIC):
        return "jpg"
    raise UploadRejectedError("not_png_or_jpeg")


def sanitize_screenshot(data: bytes) -> CleanImage:
    if not data:
        raise UploadRejectedError("empty")
    if len(data) > MAX_BYTES:
        raise UploadRejectedError("too_large")
    kind = _kind(data)
    try:
        with warnings.catch_warnings():
            warnings.simplefilter("error", Image.DecompressionBombWarning)
            Image.MAX_IMAGE_PIXELS = MAX_PIXELS
            with Image.open(io.BytesIO(data), formats=["PNG", "JPEG"]) as image:
                if image.width * image.height > MAX_PIXELS:
                    raise UploadRejectedError("too_many_pixels")
                image.load()
                upright = ImageOps.exif_transpose(image)
                pixels = upright.convert("RGB" if kind == "jpg" else "RGBA")
    except UploadRejectedError:
        raise
    except (Image.DecompressionBombError, Image.DecompressionBombWarning) as exc:
        raise UploadRejectedError("too_many_pixels") from exc
    except Exception as exc:  # any decoder failure means "not a valid image"
        raise UploadRejectedError("undecodable") from exc

    pixels.info = {}  # no EXIF / ICC / text chunks carried into the new file
    out = io.BytesIO()
    if kind == "jpg":
        pixels.save(out, format="JPEG", quality=85, optimize=True)
    else:
        pixels.save(out, format="PNG", optimize=True)
    return CleanImage(out.getvalue(), kind)
