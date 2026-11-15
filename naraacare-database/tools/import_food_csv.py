#!/usr/bin/env python3
"""Validated import of the nutritionist's food CSV (Session 08, OQ-42).

Reads the CSV, validates every row, and writes ONE transactional SQL script that calls
``nutrition.pr_admin_upsert_food`` as the nutritionist (the procedure re-checks the role, the safe
text rules and the numeric ranges, and the audit trigger records each change). Nothing is
written to the database by this tool; you run the script with psql:

    python tools/import_food_csv.py foods.csv --actor <nutritionist user uuid> > import.sql
    psql -X -v ON_ERROR_STOP=1 -d naraacare -f import.sql      # as app_rw, in one transaction

Rows with problems are reported to stderr by line number and column name only (values are never
echoed), and the tool exits with status 1 without producing SQL, so a bad file imports nothing.

CSV columns (header required, UTF-8):
  name, category_code, basis (g|ml), density_g_per_ml (optional, default 1), is_cooked (true|false),
  source_ref, the 17 nutrients per 100 g/ml (calories, protein, carbohydrates, fat, dietary_fiber,
  total_sugar, saturated_fat, polyunsaturated_fat, monounsaturated_fat, trans_fat, cholesterol,
  sodium, potassium, calcium, iron, vitamin_a, vitamin_c; empty = 0),
  aliases (optional, "|"-separated, max 20), alias_language (en|hi|hinglish, default hinglish).
Re-running the same file creates duplicates: the import is for new foods (food_id NULL); edits go
through PATCH /admin/foods/{id}.
"""

from __future__ import annotations

import argparse
import csv
import json
import re
import sys
import unicodedata
import uuid
from decimal import Decimal, InvalidOperation
from pathlib import Path

NUTRIENT_MAX = {
    "calories": Decimal(900), "protein": Decimal(100), "carbohydrates": Decimal(100), "fat": Decimal(100),
    "dietary_fiber": Decimal(100), "total_sugar": Decimal(100), "saturated_fat": Decimal(100),
    "polyunsaturated_fat": Decimal(100), "monounsaturated_fat": Decimal(100), "trans_fat": Decimal(100),
    "cholesterol": Decimal(100000), "sodium": Decimal(100000), "potassium": Decimal(100000),
    "calcium": Decimal(100000), "iron": Decimal(100000), "vitamin_a": Decimal(100000),
    "vitamin_c": Decimal(100000),
}
REQUIRED = ["name", "category_code", "basis", "is_cooked", "source_ref", *NUTRIENT_MAX]
CODE = re.compile(r"^[a-z][a-z0-9_]{0,39}$")
# Mirrors the common.safe_text domain closely enough to fail early; the database stays the authority.
UNSAFE = re.compile(
    r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f​-‏‪-‮⁦-⁩﻿<>＜＞﹤﹥‹›]"
    r"|(java|vb|live)\s*script\s*:|data\s*:\s*[a-z]+/|(^|[^a-z0-9_])on[a-z]+\s*=|(expression|url)\s*\(|@import"
    r"|\{\{|\}\}|\$\{|<%|%>|#\{|%[0-9a-f]{2}|&#?[a-z0-9]+;?",
    re.IGNORECASE,
)


class RowError(ValueError):
    """A problem with one column of one row; the message names the column, never the value."""


def text(row: dict[str, str], column: str, max_len: int, *, required: bool = True) -> str | None:
    raw = (row.get(column) or "").strip()
    if not raw:
        if required:
            raise RowError(f"{column}: required")
        return None
    value = unicodedata.normalize("NFKC", raw)
    if len(value) > max_len:
        raise RowError(f"{column}: longer than {max_len}")
    if UNSAFE.search(value):
        raise RowError(f"{column}: characters that are not allowed")
    return value


def number(row: dict[str, str], column: str, maximum: Decimal, *, default: Decimal) -> Decimal:
    raw = (row.get(column) or "").strip()
    if not raw:
        return default
    try:
        value = Decimal(raw)
    except InvalidOperation as exc:
        raise RowError(f"{column}: not a number") from exc
    if not value.is_finite() or not Decimal(0) <= value <= maximum:
        raise RowError(f"{column}: outside 0..{maximum}")
    return value.quantize(Decimal("0.001"))


def parse_row(row: dict[str, str]) -> dict[str, object]:
    category = (row.get("category_code") or "").strip()
    if not CODE.match(category):
        raise RowError("category_code: invalid code")
    basis = (row.get("basis") or "").strip()
    if basis not in {"g", "ml"}:
        raise RowError("basis: must be g or ml")
    cooked = (row.get("is_cooked") or "").strip().lower()
    if cooked not in {"true", "false"}:
        raise RowError("is_cooked: must be true or false")
    language = (row.get("alias_language") or "hinglish").strip()
    if language not in {"en", "hi", "hinglish"}:
        raise RowError("alias_language: must be en, hi or hinglish")
    nutrients = {k: number(row, k, m, default=Decimal(0)) for k, m in NUTRIENT_MAX.items()}
    if nutrients["protein"] + nutrients["carbohydrates"] + nutrients["fat"] > 100:
        raise RowError("protein + carbohydrates + fat: more than 100 g per 100 g")
    density = number(row, "density_g_per_ml", Decimal(3), default=Decimal(1))
    if density <= 0:
        raise RowError("density_g_per_ml: must be above 0")
    parts = [a for a in (row.get("aliases") or "").split("|") if a.strip()]
    if len(parts) > 20:
        raise RowError("aliases: more than 20")
    aliases = [str(text({"aliases": a}, "aliases", 60)) for a in parts]
    return {
        "name": text(row, "name", 120),
        "category_code": category,
        "basis": basis,
        "density": density,
        "is_cooked": cooked == "true",
        "source_ref": text(row, "source_ref", 120),
        "nutrients": {k: float(v) for k, v in nutrients.items()},
        "aliases": aliases,
        "alias_language": language,
    }


def sql_literal(value: str) -> str:
    """Standard SQL string literal. Values were validated above (no control characters)."""
    return "'" + value.replace("'", "''") + "'"


def to_sql(actor: uuid.UUID, rows: list[dict[str, object]]) -> str:
    out = [
        "-- Generated by tools/import_food_csv.py; run with psql -v ON_ERROR_STOP=1 (one transaction).",
        "BEGIN;",
        f"SELECT set_config('app.user_id', {sql_literal(str(actor))}, TRUE);",
    ]
    for r in rows:
        out.append(
            "CALL nutrition.pr_admin_upsert_food("
            f"{sql_literal(str(actor))}, NULL, {sql_literal(str(r['name']))}, "
            f"{sql_literal(str(r['category_code']))}, {sql_literal(str(r['basis']))}, {r['density']}, "
            f"{'TRUE' if r['is_cooked'] else 'FALSE'}, {sql_literal(str(r['source_ref']))}, "
            f"{sql_literal(json.dumps(r['nutrients']))}::jsonb, "
            f"{sql_literal(json.dumps(r['aliases'], ensure_ascii=False))}::jsonb, "
            f"{sql_literal(str(r['alias_language']))}, NULL);"
        )
    out.append("COMMIT;")
    return "\n".join(out) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("csv_path", type=Path)
    parser.add_argument("--actor", required=True, type=uuid.UUID, help="nutritionist user id")
    args = parser.parse_args(argv)

    errors: list[str] = []
    rows: list[dict[str, object]] = []
    with args.csv_path.open(encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [c for c in REQUIRED if c not in (reader.fieldnames or [])]
        if missing:
            print(f"missing columns: {', '.join(missing)}", file=sys.stderr)
            return 1
        for line_no, row in enumerate(reader, start=2):
            try:
                rows.append(parse_row(row))
            except RowError as exc:
                errors.append(f"line {line_no}: {exc}")
    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"{len(errors)} row(s) rejected; nothing generated", file=sys.stderr)
        return 1
    sys.stdout.write(to_sql(args.actor, rows))
    print(f"{len(rows)} food(s) ready to import", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
