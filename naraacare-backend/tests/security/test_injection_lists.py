"""SQL injection, path traversal and CSV formula injection (Session 16, doc 07 T5 / T21, API8).

Markup is refused everywhere (payload sweep). SQL-looking text, on the other hand, is ordinary
text in free-text fields ("O'Brien's dal"): safety comes from bound parameters, so the tests prove
that such strings never cause a server error, never widen a search, and round-trip unchanged.
Traversal strings never reach the file system, and exported CSV cells never start a formula.
"""

from __future__ import annotations

import csv
import hashlib
import io
import uuid
from collections.abc import Iterator
from pathlib import Path

import httpx2
import pytest

from app.domain.privacy.export import FORMULA_START, _cell, table_csv
from app.integrations.storage import FilesystemStorage
from tests.conftest import AppFactory
from tests.integration.flows import ADMIN_URL, DB_URL, Flow, make_flow
from tests.integration.users import User
from tests.security.payloads import PAYLOAD_FILE, load_payloads

SQLI = load_payloads("sqli.txt")
TRAVERSAL = load_payloads("path_traversal.txt")
CSV = load_payloads("csv_injection.txt")
REPOS = Path(__file__).resolve().parents[3]


# --------------------------------------------------------------------------- the lists
@pytest.mark.parametrize(
    ("name", "minimum"), [("sqli.txt", 60), ("path_traversal.txt", 40), ("csv_injection.txt", 25)]
)
def test_lists_are_versioned_unique_and_large(name: str, minimum: int) -> None:
    text = PAYLOAD_FILE.with_name(name).read_text(encoding="utf-8")
    assert text.startswith("# payload-list-version: 1.")
    vectors = load_payloads(name)
    assert len(vectors) >= minimum
    assert len(vectors) == len(set(vectors))


@pytest.mark.parametrize(
    "copy",
    [
        "naraacare-mobile/test/security/payloads/xss.txt",
        "naraacare-database/tests/payloads/xss.txt",
    ],
)
def test_shared_xss_list_is_identical_in_every_repo(copy: str) -> None:
    other = REPOS / copy
    if not other.exists():
        pytest.skip(f"{copy} not checked out next to the backend")
    digest = hashlib.sha256(PAYLOAD_FILE.read_bytes()).hexdigest()
    assert hashlib.sha256(other.read_bytes()).hexdigest() == digest


# --------------------------------------------------------------------------- CSV
@pytest.mark.parametrize("vector", CSV)
def test_export_cells_never_start_a_formula(vector: str) -> None:
    cell = _cell(vector)
    assert not cell.lstrip().startswith(FORMULA_START) or cell.startswith("'")
    assert cell in {vector, "'" + vector}  # the user's text is kept, only neutralised


def test_formula_guard_survives_the_csv_writer() -> None:
    text = table_csv([{"note": v} for v in CSV]).lstrip(chr(0xFEFF))
    values = [row[0] for row in csv.reader(io.StringIO(text))][1:]
    assert len(values) == len(CSV)
    for value in values:
        assert not value.lstrip().startswith(FORMULA_START) or value.startswith("'"), value


def test_numbers_stay_numbers() -> None:
    assert _cell(-100) == "-100" and _cell(2.5) == "2.5"


# --------------------------------------------------------------------------- traversal
@pytest.mark.parametrize("vector", TRAVERSAL)
def test_storage_keys_cannot_escape_the_storage_root(tmp_path: Path, vector: str) -> None:
    storage = FilesystemStorage(tmp_path / "root", {"reports": "r", "support": "s"})
    for key in (vector, f"reports/{vector}", f"support/{vector}"):
        try:
            path = storage._path(key)
        except ValueError:
            continue
        assert (tmp_path / "root").resolve() in path.parents, key


def test_traversal_in_path_parameters_never_reaches_a_handler(app_factory: AppFactory) -> None:
    harness = app_factory()
    from tests.integration.flows import NoLimits  # noqa: PLC0415

    harness.app.state.rate_limiter = NoLimits()
    token = harness.app.state.tokens.issue_access(
        user_id=uuid.uuid4(), role="user", session_id=uuid.uuid4(), tier_hint="star"
    )
    headers = {"Authorization": f"Bearer {token}"}
    routes = [
        "/api/v1/reports/{}/file",
        "/api/v1/privacy/exports/{}/file",
        "/api/v1/foods/{}",
        "/api/v1/foods/barcode/{}",
        "/api/v1/circles/{}",
    ]
    for template in routes:
        for vector in TRAVERSAL:
            try:
                response = harness.client.get(template.format(vector), headers=headers)
            except (UnicodeEncodeError, ValueError, httpx2.InvalidURL):
                continue  # not even sendable
            assert response.status_code in {404, 405, 422}, (template, vector, response.text)


# --------------------------------------------------------------------------- SQL (database)
@pytest.fixture
def flow(app_factory: AppFactory) -> Iterator[Flow]:
    yield make_flow(app_factory)


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
def test_sql_strings_in_searches_never_cause_a_server_error(flow: Flow) -> None:
    user = User(flow)
    name = f"u{uuid.uuid4().hex[:10]}"
    flow.client.put("/api/v1/me/username", headers=user.headers, json={"username": name})
    searches = [
        ("/api/v1/foods/search", "q"),
        ("/api/v1/people/search", "q"),
        ("/api/v1/usernames/availability", "username"),
    ]
    for path, param in searches:
        for vector in SQLI:
            response = flow.client.get(path, params={param: vector}, headers=user.headers)
            assert response.status_code in {200, 422}, (path, vector, response.text)


@pytest.mark.db
@pytest.mark.skipif(DB_URL is None or ADMIN_URL is None, reason="needs the test database URLs")
def test_sql_strings_round_trip_unchanged_as_plain_text(flow: Flow) -> None:
    user = User(flow)
    stored = 0
    for vector in SQLI:
        response = flow.client.post(
            "/api/v1/saved-meals",
            headers=user.headers,
            json={
                "name": vector[:60],
                "items": [
                    {
                        "food_id": "0192f000-0000-7000-8000-000000000001",
                        "quantity": 1,
                        "unit_code": "piece",
                    }
                ],
            },
        )
        assert response.status_code in {201, 409, 422}, (vector, response.text)
        if response.status_code == 201:
            stored += 1
            listed = flow.client.get("/api/v1/saved-meals", headers=user.headers).json()
            assert vector[:60] in [m["name"] for m in listed["saved_meals"]]
            flow.client.delete(
                f"/api/v1/saved-meals/{response.json()['saved_meal_id']}", headers=user.headers
            )
    assert stored >= 10  # plenty of SQL-looking names are legal text and must survive intact
