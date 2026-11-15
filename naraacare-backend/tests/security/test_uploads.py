"""Upload attacks (Session 16, doc 07 T21, OQ-51): the support screenshot is the only upload.

Unit level (``sanitize_screenshot``): only real PNG/JPEG decode; polyglots, other formats, bombs,
truncated and oversized files are refused with a fixed reason; the stored image is re-encoded with
no EXIF/GPS, text chunks or trailing bytes. HTTP level (real database): the route enforces the same
plus the 10 MB cap, a validated file name and no extra form fields.
"""

from __future__ import annotations

import io
import struct
import uuid
import zlib
from collections.abc import Iterator
from pathlib import Path

import pytest
from PIL import Image, PngImagePlugin

from app.domain.support.uploads import (
    MAX_BYTES,
    UploadRejectedError,
    sanitize_screenshot,
)
from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, DB_URL, Flow, make_flow
from tests.integration.users import User, sql

TICKETS = "/api/v1/support/tickets"


def png(width: int = 40, height: int = 30, **info: str) -> bytes:
    meta = PngImagePlugin.PngInfo()
    for key, value in info.items():
        meta.add_text(key, value)
    out = io.BytesIO()
    Image.new("RGBA", (width, height), (10, 120, 200, 255)).save(out, "PNG", pnginfo=meta)
    return out.getvalue()


def jpeg_with_gps() -> bytes:
    exif = Image.Exif()
    exif[0x010F] = "PhoneMaker"  # Make
    exif[0x0110] = "Phone 15"  # Model
    gps = {1: "N", 2: (28.0, 36.0, 50.0), 3: "E", 4: (77.0, 12.0, 30.0)}
    exif[0x8825] = gps  # GPSInfo
    out = io.BytesIO()
    Image.new("RGB", (32, 32), (200, 20, 20)).save(out, "JPEG", exif=exif.tobytes())
    return out.getvalue()


def png_bomb(side: int = 20_000) -> bytes:
    """A tiny file that declares side x side pixels (a decompression bomb)."""

    def chunk(kind: bytes, data: bytes) -> bytes:
        body = kind + data
        return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body))

    header = struct.pack(">IIBBBBB", side, side, 1, 0, 0, 0, 0)  # 1-bit greyscale
    rows = zlib.compress(b"\x00" * (side // 8 + 1) * 64)  # far fewer rows than declared
    return (
        b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header) + chunk(b"IDAT", rows) + chunk(b"IEND", b"")
    )


SVG = b'<svg xmlns="http://www.w3.org/2000/svg" onload="alert(1)"><script>alert(1)</script></svg>'
HTML = b"<!doctype html><script>alert(document.cookie)</script>"
GIF = b"GIF89a\x01\x00\x01\x00\x80\x00\x00\x00\x00\x00\xff\xff\xff!\xf9\x04\x01\x00\x00\x00\x00,"

REFUSED = {
    "empty": (b"", "empty"),
    "svg with script": (SVG, "not_png_or_jpeg"),
    "html": (HTML, "not_png_or_jpeg"),
    "gif": (GIF, "not_png_or_jpeg"),
    "pdf": (b"%PDF-1.7\n1 0 obj<<>>endobj", "not_png_or_jpeg"),
    "zip": (b"PK\x03\x04" + b"\x00" * 30, "not_png_or_jpeg"),
    "png magic then html": (b"\x89PNG\r\n\x1a\n" + HTML, "undecodable"),
    "jpeg magic then script": (b"\xff\xd8\xff\xe0" + HTML, "undecodable"),
    "truncated png": (png()[:60], "undecodable"),
    "decompression bomb": (png_bomb(), "too_many_pixels"),
    "over 10 MB": (b"\x89PNG\r\n\x1a\n" + b"\x00" * MAX_BYTES, "too_large"),
}


@pytest.mark.parametrize("case", REFUSED)
def test_bad_files_are_refused_with_a_fixed_reason(case: str) -> None:
    data, reason = REFUSED[case]
    with pytest.raises(UploadRejectedError) as info:
        sanitize_screenshot(data)
    assert info.value.reason == reason
    assert data[:20].decode("latin-1") not in str(info.value) or not data


def test_png_is_re_encoded_without_text_chunks_or_trailing_data() -> None:
    original = png(Comment="<script>alert(1)</script>", Author="Priya")
    polyglot = original + HTML  # valid PNG with an HTML page appended
    clean = sanitize_screenshot(polyglot)
    assert clean.extension == "png"
    assert b"<script>" not in clean.data
    assert b"Priya" not in clean.data
    assert b"tEXt" not in clean.data and b"iTXt" not in clean.data
    with Image.open(io.BytesIO(clean.data)) as image:
        assert image.size == (40, 30)


def test_jpeg_loses_exif_and_gps() -> None:
    clean = sanitize_screenshot(jpeg_with_gps())
    assert clean.extension == "jpg"
    with Image.open(io.BytesIO(clean.data)) as image:
        assert dict(image.getexif()) == {}
    assert b"PhoneMaker" not in clean.data
    assert b"Exif" not in clean.data


# --------------------------------------------------------------------------- over HTTP
db = pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")


@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory)


def post(flow: Flow, user: User, files: dict[str, object], **form: str) -> object:
    return flow.client.post(
        TICKETS,
        headers=user.headers,
        data={"category": "app_crash", "description": "The app closes when I open reports", **form},
        files=files,
    )


@pytest.mark.db
@db
async def test_valid_screenshot_is_stored_clean(flow: Flow, tmp_path: Path) -> None:
    user = User(flow)
    response = post(flow, user, {"screenshot": ("shot.jpg", jpeg_with_gps(), "image/jpeg")})
    assert response.status_code == 201, response.text  # type: ignore[attr-defined]
    rows = await sql("SELECT screenshot_key FROM support.ticket WHERE user_id = $1", user.id)
    key = rows[0]["screenshot_key"]
    assert key.startswith("support/") and key.endswith(".jpg") and "shot" not in key
    stored = next(tmp_path.rglob(key.split("/", 1)[1]))  # noqa: ASYNC240 - test file check
    assert b"PhoneMaker" not in stored.read_bytes()


@pytest.mark.db
@db
@pytest.mark.parametrize(
    ("case", "status"),
    [
        ("svg disguised as png", 422),
        ("html file", 422),
        ("script in file name", 422),
        ("path traversal name", 422),
        ("unknown form field", 422),
        ("second file field", 422),
        ("11 MB", 413),
    ],
)
def test_bad_uploads_are_refused(flow: Flow, case: str, status: int) -> None:
    user = User(flow)
    files: dict[str, object] = {"screenshot": ("shot.png", png(), "image/png")}
    form: dict[str, str] = {}
    if case == "svg disguised as png":
        files = {"screenshot": ("shot.png", SVG, "image/png")}
    elif case == "html file":
        files = {"screenshot": ("page.html", HTML, "text/html")}
    elif case == "script in file name":
        files = {"screenshot": ("<script>alert(1)</script>.png", png(), "image/png")}
    elif case == "path traversal name":
        files = {"screenshot": ("../../etc/passwd.png", png(), "image/png")}
    elif case == "unknown form field":
        form = {"user_id": str(uuid.uuid4())}
    elif case == "second file field":
        files = {**files, "attachment": ("x.png", png(), "image/png")}
    else:
        files = {"screenshot": ("big.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * (11 * 1024 * 1024), "")}
    response = post(flow, user, files, **form)
    assert response.status_code == status, response.text  # type: ignore[attr-defined]
