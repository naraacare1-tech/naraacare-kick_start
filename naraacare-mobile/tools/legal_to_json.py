"""Converts the owner's legal PDFs into the app's in-app text (owner 2026-11-24: show the Terms and
Privacy Policy inside the app).

Output: assets/legal/<name>.json = {"title": str, "blocks": [...]}, one block per element:
  {"type": "heading", "text": str}                 section title (13.5 pt bold)
  {"type": "summary", "spans": [...]}              the italic "In short" line
  {"type": "paragraph", "spans": [...]}            body text, bold run-in labels kept as spans
  {"type": "bullet", "spans": [...]}               bullet point
  {"type": "item", "spans": [...]}                 numbered list item ("1. ...")
  {"type": "table", "rows": [[str, ...], ...]}     first row = header
A span is {"t": text, "b": true|false}. Plain text only: the app renders it with Text widgets, so
nothing in it can act as markup or a link.

Usage (from naraacare-mobile; pdfplumber is MIT):
  uv run --no-project --with pdfplumber==0.11.7 python -I tools/legal_to_json.py \
      "<Terms>.pdf" assets/legal/terms.json "<Privacy>.pdf" assets/legal/privacy.json
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pdfplumber

TITLE_SIZE = 20.0
HEADING_SIZE = 13.5
PARA_GAP = 0.8  # a blank gap taller than this many line heights starts a new paragraph
INDENT = 8.0  # points right of the body margin = a list item
# A numbered clause ("2.3 Security. ...") starts a paragraph; "7.0 or later" in a sentence does not.
NUMBERED = re.compile(r"^\d+\.\d+\s+[A-Z]")
LIST_ITEM = re.compile(r"^\d+\.\s")  # "1. ..." inside a clause is a list item


def _bold(font: str) -> bool:
    return "Bold" in font


def _italic(font: str) -> bool:
    return "Oblique" in font or "Italic" in font


def _clean(text: str) -> str:
    return (
        text.replace("ﬁ", "fi")
        .replace("ﬂ", "fl")
        .replace("ﬀ", "ff")
        .replace("ﬃ", "ffi")
        .replace("ﬄ", "ffl")
    )


def _in_any(box: tuple[float, float, float, float], boxes: list[tuple[float, ...]]) -> bool:
    x0, top, x1, bottom = box
    return any(b[0] - 1 <= x0 and x1 <= b[2] + 1 and b[1] - 1 <= top and bottom <= b[3] + 1 for b in boxes)


def _lines(page: pdfplumber.page.Page, skip: list[tuple[float, ...]]) -> list[dict]:
    """Text lines outside the tables, each with its spans (bold runs), size, x0 and top. Built from
    characters: a space is added only where the PDF has a real gap (a font change, such as a bold
    word after a quote mark, is not a space)."""
    out = []
    # The bullet dots are drawn as small curves, not characters.
    dots = [
        ((c["x0"] + c["x1"]) / 2, (c["top"] + c["bottom"]) / 2)
        for c in page.curves
        if c["x1"] - c["x0"] < 8 and c["bottom"] - c["top"] < 8
    ]
    for line in page.extract_text_lines(return_chars=True):
        chars = []
        for c in line["chars"]:
            if _in_any((c["x0"], c["top"], c["x1"], c["bottom"]), skip):
                continue
            # This PDF repeats each ligature glyph at the same position ("fl" twice).
            if chars and chars[-1]["text"] == c["text"] and abs(chars[-1]["x0"] - c["x0"]) < 0.01:
                continue
            chars.append(c)
        if not chars:
            continue
        spans: list[dict] = []
        prev = None
        for c in chars:
            text = c["text"]
            bold = _bold(c["fontname"])
            space = (
                prev is not None
                and text != " "
                and not (spans and spans[-1]["t"].endswith(" "))
                and c["x0"] - prev["x1"] > 0.2 * c["size"]
            )
            if spans and spans[-1]["b"] == bold:
                spans[-1]["t"] += (" " if space else "") + text
            else:
                if space and spans:
                    spans[-1]["t"] += " "
                spans.append({"t": text, "b": bold})
            prev = c
        for s in spans:
            s["t"] = _clean(s["t"])
        first = chars[0]
        middle = (first["top"] + first["bottom"]) / 2
        out.append(
            {
                "spans": spans,
                "text": "".join(s["t"] for s in spans),
                "size": round(first["size"], 1),
                "italic": _italic(first["fontname"]),
                "x0": first["x0"],
                "top": first["top"],
                "height": first["bottom"] - first["top"],
                "dot": any(x < first["x0"] and abs(y - middle) < 6 for x, y in dots),
            }
        )
    return out


def _merge(spans: list[dict], more: list[dict]) -> list[dict]:
    if not spans:
        return [dict(s) for s in more]
    spans = [dict(s) for s in spans]
    for i, s in enumerate(more):
        prev = spans[-1]["t"]
        # Joining two lines adds a space, except after an opening quote ('the "' + 'Service') or a
        # hyphen at the line end ('non-' + 'exclusive').
        needs_space = i == 0 and not prev.endswith((" ", ' "', '("', "-")) and prev != '"'
        if spans[-1]["b"] == s["b"]:
            spans[-1]["t"] += (" " if needs_space else "") + s["t"]
        else:
            if needs_space:
                spans[-1]["t"] += " "
            spans.append(dict(s))
    return spans


def convert(pdf_path: Path) -> dict:
    blocks: list[dict] = []
    title = ""
    with pdfplumber.open(pdf_path) as pdf:
        margin = min(
            (w["x0"] for p in pdf.pages for w in p.extract_words()[:50]),
            default=0.0,
        )
        for page in pdf.pages:
            tables = page.find_tables()
            boxes = [t.bbox for t in tables]
            items: list[tuple[float, str, object]] = [(t.bbox[1], "table", t) for t in tables]
            items += [(ln["top"], "line", ln) for ln in _lines(page, boxes)]
            items.sort(key=lambda it: it[0])
            last_bottom: float | None = None
            new_page = True
            for _, kind, item in items:
                if kind == "table":
                    rows = [
                        [_clean(" ".join((c or "").split())).replace("- ", "-") for c in row]
                        for row in item.extract()  # type: ignore[attr-defined]
                    ]
                    rows = [r for r in rows if any(r)]
                    prev_block = blocks[-1] if blocks else None
                    if (
                        rows
                        and new_page
                        and prev_block is not None
                        and prev_block["type"] == "table"
                        and len(prev_block["rows"][0]) == len(rows[0])
                    ):
                        # The same table continued on the next page.
                        prev_block["rows"].extend(rows)
                    elif rows:
                        blocks.append({"type": "table", "rows": rows})
                    new_page = False
                    last_bottom = None
                    continue
                ln = item  # type: ignore[assignment]
                text = ln["text"].strip()
                if not text or text.startswith("NaraaCare Product Reference"):
                    continue
                if ln["size"] >= TITLE_SIZE - 0.5:
                    title = (title + " " + text).strip()
                    last_bottom = None
                    continue
                if ln["size"] >= HEADING_SIZE - 0.5:
                    if blocks and blocks[-1]["type"] == "heading" and last_bottom is not None:
                        blocks[-1]["text"] += " " + text
                    else:
                        blocks.append({"type": "heading", "text": text})
                    new_page = False
                    last_bottom = ln["top"] + ln["height"]
                    continue
                indented = ln["x0"] > margin + INDENT
                gap = None if last_bottom is None else ln["top"] - last_bottom
                summary = ln["italic"] and text.startswith("In short")
                item = LIST_ITEM.match(text) is not None
                kind_name: str | None = None  # None = this line continues the previous block
                if summary:
                    kind_name = "summary"
                elif ln["dot"]:
                    kind_name = "bullet"
                elif item:
                    kind_name = "item"
                elif (
                    new_page
                    and blocks
                    and blocks[-1]["type"] in ("paragraph", "bullet", "item", "summary")
                    and not blocks[-1]["spans"][-1]["t"].rstrip().endswith((".", ":", ";", "!", "?"))
                ):
                    kind_name = None  # the sentence carries on from the previous page
                elif (
                    not blocks
                    or blocks[-1]["type"] in ("heading", "table")
                    or gap is None
                    or gap > ln["height"] * PARA_GAP
                    or NUMBERED.match(text) is not None
                    # back at the margin after a list: a new paragraph
                    or (not indented and blocks[-1]["type"] in ("bullet", "item"))
                ):
                    kind_name = "paragraph"
                if kind_name is None:
                    blocks[-1]["spans"] = _merge(blocks[-1]["spans"], ln["spans"])
                else:
                    blocks.append({"type": kind_name, "spans": [dict(s) for s in ln["spans"]]})
                new_page = False
                last_bottom = ln["top"] + ln["height"]
    for b in blocks:
        for s in b.get("spans", []):
            s["t"] = re.sub(r"\s+", " ", s["t"])
        if "spans" in b and b["spans"]:
            b["spans"][-1]["t"] = b["spans"][-1]["t"].rstrip()
    return {"title": title, "blocks": blocks}


def main(args: list[str]) -> None:
    for src, dst in zip(args[::2], args[1::2], strict=True):
        doc = convert(Path(src))
        out = Path(dst)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(doc, ensure_ascii=False, indent=1), encoding="utf-8")
        kinds: dict[str, int] = {}
        for b in doc["blocks"]:
            kinds[b["type"]] = kinds.get(b["type"], 0) + 1
        print(out.name, doc["title"], kinds)


if __name__ == "__main__":
    main(sys.argv[1:])
