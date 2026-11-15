"""Data export ZIP (right to access, doc 07 SEC-7.3, Session 15).

* Input: ``ops.fn_export_user`` -> ``{"schema.table": [rows]}`` (catalog-driven in the database,
  secrets already removed). Pure function: no database access, no network, easy to test.
* ``README.txt`` explains the files; ``json/<schema.table>.json`` holds every table exactly as
  stored (serialised by ``json.dumps``, never by string concatenation); ``csv/<schema.table>.csv``
  gives the same rows for spreadsheets.
* CSV formula-injection guard (OWASP): a text cell starting with ``= + - @``, tab or carriage
  return, also after leading whitespace (some spreadsheets trim before evaluating), gets a leading
  apostrophe, so a spreadsheet shows it as text instead of running it.
  Nested values (JSON columns, arrays) are written as compact JSON text.
"""

from __future__ import annotations

import csv
import io
import json
import zipfile
from collections.abc import Mapping, Sequence
from datetime import datetime
from typing import Any

FORMULA_START = ("=", "+", "-", "@", "\t", "\r")
BOM = chr(0xFEFF)  # so spreadsheet apps open the UTF-8 CSV with the right encoding

README = """NaraaCare data export
=====================

Created: {created} (UTC)

This archive holds the personal data NaraaCare keeps about your account, one file per table:

  json/  the data exactly as stored (best for reading or moving to another service)
  csv/   the same rows as spreadsheets

Times are in UTC (ISO 8601). Codes such as drink_code, meal_type or status are the app's own short
names. Secrets (password and session hashes, sign-in and store tokens, one-time codes) are never
included. Data about other people is limited to ids where a record links you with them (for
example a connection or a circle you share).

Files in this export:
{files}

Questions: use Help & Support in the app.
"""


def _cell(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, bool | int | float):
        return json.dumps(value)  # numbers cannot carry a formula (-100 stays a number)
    text = value if isinstance(value, str) else json.dumps(value, ensure_ascii=False, default=str)
    risky = text.startswith(FORMULA_START) or text.lstrip().startswith(FORMULA_START)
    return "'" + text if risky else text


def table_csv(rows: Sequence[Mapping[str, Any]]) -> str:
    columns: list[str] = []
    for row in rows:
        for key in row:
            if key not in columns:
                columns.append(key)
    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\r\n")
    writer.writerow([_cell(c) for c in columns])
    for row in rows:
        writer.writerow([_cell(row.get(c)) for c in columns])
    return out.getvalue()


def build_zip(data: Mapping[str, Sequence[Mapping[str, Any]]], created: datetime) -> bytes:
    names = sorted(data)
    listing = "\n".join(f"  {n}  ({len(data[n])} rows)" for n in names)
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        archive.writestr(
            "README.txt", README.format(created=created.strftime("%Y-%m-%d %H:%M"), files=listing)
        )
        for name in names:
            rows = list(data[name])
            archive.writestr(
                f"json/{name}.json",
                json.dumps(rows, ensure_ascii=False, indent=2, default=str, sort_keys=True),
            )
            if rows:
                archive.writestr(f"csv/{name}.csv", BOM + table_csv(rows))
    return buffer.getvalue()
