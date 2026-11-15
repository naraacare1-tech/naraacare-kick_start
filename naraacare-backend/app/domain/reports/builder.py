"""PDF report builder (Session 14, doc 04 section 2.11, doc 07 SEC-2.5; layout: owner's Figma
report, 2026-11-08).

* Drawn with the ReportLab canvas and native ReportLab graphics only: ``drawString`` never parses
  markup, and no HTML/XML (Paragraph mini-markup) is used anywhere, so a user's name or a model
  sentence cannot become markup. Every string is also passed through ``_plain`` (control characters
  removed, Latin-1 for the built-in fonts) before it is drawn.
* Inputs are the job metadata, the daily aggregates of ``ops.fn_report_days``, the page extras of
  ``ops.fn_report_extras`` (previous-period averages, meal shares, counts, targets) and the already
  validated insight sentences. No database access and no network here: a pure function.
* Pages: a cover (period, who, what is included, goal achievement per section, highlights), one
  page per section (overview tiles, a daily bar chart, section details, basic insights) and, for
  STAR, "Advanced insights" (trend vs the previous period per section, the overall trend and
  recommendations). The disclaimer closes the last page.
"""

from __future__ import annotations

import io
import math
import unicodedata
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, field
from datetime import date
from decimal import Decimal
from typing import Any

from reportlab.graphics import renderPDF
from reportlab.graphics.charts.barcharts import VerticalBarChart
from reportlab.graphics.shapes import Drawing
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.utils import simpleSplit
from reportlab.pdfgen.canvas import Canvas

PAGE_W, PAGE_H = A4
MARGIN = 40
CONTENT_W = PAGE_W - 2 * MARGIN
BOTTOM = 60  # content stops above the footer line
BRAND = colors.HexColor("#2BA8E8")
INK = colors.HexColor("#1F2933")
MUTED = colors.HexColor("#6B7785")
LINE = colors.HexColor("#E6EAF0")
TILE = colors.HexColor("#F4F7FB")
SECTION_COLOURS = {
    "hydration": colors.HexColor("#2F7DF6"),
    "nutrition": colors.HexColor("#22A36B"),
    "sleep": colors.HexColor("#7B4DE0"),
    "insights": colors.HexColor("#7B4DE0"),
}
SECTION_TINTS = {
    "hydration": colors.HexColor("#EEF4FF"),
    "nutrition": colors.HexColor("#EAF7F0"),
    "sleep": colors.HexColor("#F2EEFD"),
    "insights": colors.HexColor("#F2EEFD"),
}
SECTION_TITLES = {
    "hydration": "Hydration",
    "nutrition": "Nutrition",
    "sleep": "Sleep",
    "insights": "Advanced Insights",
}
QUALITY_COLOURS = (
    colors.HexColor("#7B4DE0"),
    colors.HexColor("#22A36B"),
    colors.HexColor("#E5484D"),
)
# Guideline thresholds for the basic (rule-based) insights. Sources: WHO healthy diet fact sheet
# (free sugars under 10 % of energy, about 50 g; sodium under 2,000 mg); ICMR-NIN dietary
# guidelines (fibre about 25-30 g a day; protein at least 15 % of energy for most adults). Product
# to confirm (OQ-76).
PROTEIN_MIN_KCAL_PCT = 15
FIBRE_MIN_G = 25
SUGAR_MAX_G = 50
SODIUM_MAX_MG = 2000
HYDRATION_GOOD_PCT = 70  # goal met on at least this share of logged days
CALORIE_BAND_PCT = 10  # a nutrition "goal day" is within +/- this of the calorie allowance
TREND_STEP_PCT = 5  # a change smaller than this is "steady"
TREND_MIN_DAYS = 4  # fewer logged days than this are too few to call a trend
MEAL_NAMES = {"breakfast": "Breakfast", "lunch": "Lunch", "dinner": "Dinner", "snack": "Snacks"}

DISCLAIMER = (
    "This report summarises the information you logged in NaraaCare. It is for general "
    "wellness only and is not medical advice, a diagnosis or a treatment plan. Targets are "
    "estimates based on the details you entered. Talk to a qualified health professional before "
    "making changes to your diet, fluid intake or sleep, especially if you have a medical "
    "condition."
)


@dataclass(frozen=True, slots=True)
class ReportMeta:
    full_name: str | None
    username: str | None
    period_from: date
    period_to: date
    sections: Sequence[str]
    generated_on: date
    insights: bool = False  # STAR: the Advanced insights page


@dataclass(slots=True)
class Summary:
    """Numbers shown in the report (also the only input of the AI insights)."""

    days: int
    hydration: dict[str, Any] = field(default_factory=dict)
    nutrition: dict[str, Any] = field(default_factory=dict)
    sleep: dict[str, Any] = field(default_factory=dict)
    vs_previous: dict[str, Any] = field(default_factory=dict)


@dataclass(frozen=True, slots=True)
class AdvancedInsights:
    """STAR: the overall trend and recommendations (AI, from the summary only)."""

    trend: str
    recommendations: Sequence[str]


def _plain(value: object, limit: int = 200) -> str:
    """Drawable text: no control/format characters, Latin-1 only (built-in PDF fonts)."""
    text = unicodedata.normalize("NFKC", str(value))
    text = "".join(ch for ch in text if unicodedata.category(ch)[0] != "C")
    text = text.encode("latin-1", "replace").decode("latin-1")
    return text[:limit]


def _num(value: Any) -> float | None:
    if value is None:
        return None
    return float(value) if isinstance(value, int | float | Decimal) else None


def _avg(values: Sequence[float]) -> float | None:
    return sum(values) / len(values) if values else None


def _pct(part: float, whole: float) -> int:
    return round(100 * part / whole) if whole else 0


def _change(now: float | None, before: float | None) -> int | None:
    if not now or not before:
        return None
    return round(100 * (now - before) / before)


def _halves(values: Sequence[float]) -> dict[str, Any]:
    """Average of the first and second half of the logged days and the change in percent."""
    if len(values) < TREND_MIN_DAYS:
        return {"first_half": None, "second_half": None, "change_pct": None}
    mid = len(values) // 2
    first, second = _avg(values[:mid]) or 0, _avg(values[mid:]) or 0
    change = round(100 * (second - first) / first) if first else None
    return {"first_half": round(first, 1), "second_half": round(second, 1), "change_pct": change}


def _hydration_summary(days: Sequence[dict[str, Any]]) -> dict[str, Any]:
    logged = [d for d in days if (_num(d.get("water_ml")) or 0) > 0]
    met = sum(1 for d in logged if d.get("hydration_goal_met"))
    best = max(logged, key=lambda d: _num(d["water_ml"]) or 0, default=None)
    return {
        "days_logged": len(logged),
        "goal_met_days": met,
        "goal_met_pct": _pct(met, len(logged)),
        "avg_ml": round(_avg([_num(d["water_ml"]) or 0 for d in logged]) or 0),
        "avg_need_ml": round(
            _avg([v for d in logged if (v := _num(d.get("need_ml"))) is not None]) or 0
        ),
        "total_ml": round(sum(_num(d["water_ml"]) or 0 for d in logged)),
        "best_ml": round(_num(best["water_ml"]) or 0) if best else 0,
        "best_date": best["local_date"].isoformat() if best else None,
        "trend": _halves([_num(d["water_ml"]) or 0 for d in logged]),
    }


def _nutrition_summary(days: Sequence[dict[str, Any]]) -> dict[str, Any]:
    logged = [d for d in days if (_num(d.get("kcal")) or 0) > 0]
    pct = [
        100 * (_num(d["kcal"]) or 0) / a
        for d in logged
        if (a := _num(d.get("allowance_kcal"))) and a > 0
    ]
    on_target = sum(1 for p in pct if abs(p - 100) <= CALORIE_BAND_PCT)

    def avg(key: str, digits: int = 1) -> float:
        return round(_avg([_num(d.get(key)) or 0 for d in logged]) or 0, digits)

    out: dict[str, Any] = {
        "days_logged": len(logged),
        "goal_met_days": on_target,
        "goal_met_pct": _pct(on_target, len(logged)),
        "avg_kcal": round(_avg([_num(d["kcal"]) or 0 for d in logged]) or 0),
        "avg_target_pct": round(_avg(pct) or 0),
        "avg_protein_g": avg("protein_g"),
        "avg_carbs_g": avg("carbs_g"),
        "avg_fat_g": avg("fat_g"),
        "avg_fiber_g": avg("fiber_g"),
        "avg_sugar_g": avg("sugar_g"),
        "avg_sodium_mg": round(avg("sodium_mg")),
        "trend": _halves([_num(d["kcal"]) or 0 for d in logged]),
    }
    out["protein_kcal_pct"] = _pct(out["avg_protein_g"] * 4, out["avg_kcal"])
    return out


def _sleep_summary(days: Sequence[dict[str, Any]], extras: Mapping[str, Any]) -> dict[str, Any]:
    logged = [d for d in days if (_num(d.get("sleep_min")) or 0) > 0]
    met = sum(
        1
        for d in logged
        if (g := _num(d.get("sleep_goal_min"))) and (_num(d["sleep_min"]) or 0) >= g
    )
    good_from = _num(extras.get("sleep_good_from_pct")) or 90
    fair_from = _num(extras.get("sleep_fair_from_pct")) or 70
    scores = [_num(d.get("sleep_score_pct")) or 0 for d in logged]
    longest = max(logged, key=lambda d: _num(d["sleep_min"]) or 0, default=None)
    return {
        "nights_logged": len(logged),
        "goal_met_days": met,
        "goal_met_pct": _pct(met, len(logged)),
        "avg_min": round(_avg([_num(d["sleep_min"]) or 0 for d in logged]) or 0),
        "avg_score_pct": round(_avg(scores) or 0),
        "avg_goal_min": round(
            _avg([v for d in logged if (v := _num(d.get("sleep_goal_min"))) is not None]) or 0
        ),
        "longest_min": round(_num(longest["sleep_min"]) or 0) if longest else 0,
        "good_nights": sum(1 for s in scores if s >= good_from),
        "fair_nights": sum(1 for s in scores if fair_from <= s < good_from),
        "low_nights": sum(1 for s in scores if s < fair_from),
        "trend": _halves([_num(d["sleep_min"]) or 0 for d in logged]),
    }


def summarise(
    days: Sequence[dict[str, Any]],
    sections: Sequence[str],
    extras: Mapping[str, Any] | None = None,
) -> Summary:
    extras = extras or {}
    summary = Summary(days=len(days))
    prev_days = extras.get("prev_days", len(days))
    if "hydration" in sections:
        summary.hydration = _hydration_summary(days)
        summary.vs_previous["water_change_pct"] = _change(
            summary.hydration["avg_ml"], _num(extras.get("prev_water_ml"))
        )
    if "nutrition" in sections:
        summary.nutrition = _nutrition_summary(days)
        summary.vs_previous["calories_change_pct"] = _change(
            summary.nutrition["avg_kcal"], _num(extras.get("prev_kcal"))
        )
        summary.vs_previous["protein_change_pct"] = _change(
            summary.nutrition["avg_protein_g"], _num(extras.get("prev_protein_g"))
        )
    if "sleep" in sections:
        summary.sleep = _sleep_summary(days, extras)
        prev_sleep = _num(extras.get("prev_sleep_min"))
        summary.vs_previous["sleep_change_min"] = (
            round(summary.sleep["avg_min"] - prev_sleep)
            if prev_sleep and summary.sleep["avg_min"]
            else None
        )
    if summary.vs_previous:
        summary.vs_previous["previous_days"] = prev_days
    return summary


def _trend_words(trend: dict[str, Any], up: str, down: str) -> str | None:
    change = trend.get("change_pct")
    if change is None:
        return None
    if change >= TREND_STEP_PCT:
        return up
    if change <= -TREND_STEP_PCT:
        return down
    return "It stayed steady through the period."


def _hydration_notes(h: dict[str, Any]) -> list[str]:
    if not h["days_logged"]:
        return ["No drinks were logged in this period. Log water to see your progress."]
    lines = [f"You hit your goal on {h['goal_met_days']} of {h['days_logged']} logged days."]
    if h["best_date"]:
        best = date.fromisoformat(h["best_date"])
        lines.append(f"Your best day was {h['best_ml'] / 1000:.1f} L on {best:%d %b}.")
    if h["goal_met_pct"] < HYDRATION_GOOD_PCT:
        lines.append("Try to increase intake on low days by spreading drinks through the day.")
    trend = _trend_words(
        h["trend"],
        "Your water intake went up in the second half.",
        "Your water intake dropped in the second half.",
    )
    return [*lines, trend] if trend else lines


def _nutrition_notes(n: dict[str, Any]) -> list[str]:
    if not n["days_logged"]:
        return ["No meals were logged in this period. Log meals to see your progress."]
    lines = [f"On average you ate {n['avg_target_pct']}% of your daily calorie target."]
    if n["protein_kcal_pct"] < PROTEIN_MIN_KCAL_PCT:
        lines.append(
            f"Protein gave {n['protein_kcal_pct']}% of your calories. Consider adding protein "
            "foods such as dal, paneer, eggs, curd or sprouts."
        )
    if n["avg_fiber_g"] < FIBRE_MIN_G:
        lines.append(
            f"Fibre averaged {n['avg_fiber_g']} g a day; more vegetables, fruit and whole grains "
            "would help reach about 25 g."
        )
    if n["avg_sugar_g"] > SUGAR_MAX_G:
        lines.append(f"Sugar averaged {n['avg_sugar_g']} g a day; try cutting sweet drinks.")
    if n["avg_sodium_mg"] > SODIUM_MAX_MG:
        lines.append(
            f"Sodium averaged {n['avg_sodium_mg']} mg a day; less salt and fewer packaged snacks "
            "would help."
        )
    return lines


def _sleep_notes(s: dict[str, Any]) -> list[str]:
    if not s["nights_logged"]:
        return ["No sleep was logged in this period."]
    lines = [
        f"You met your sleep goal on {s['goal_met_days']} of {s['nights_logged']} nights.",
        f"Your longest sleep was {_hm(s['longest_min'])}.",
    ]
    if s["avg_goal_min"] and s["avg_min"] < s["avg_goal_min"]:
        short = s["avg_goal_min"] - s["avg_min"]
        lines.append(
            f"You slept about {_hm(short)} less than your goal; a regular, earlier bedtime "
            "can help."
        )
    else:
        lines.append("Maintain a consistent bedtime for better sleep.")
    trend = _trend_words(
        s["trend"], "You slept longer in the second half.", "You slept less in the second half."
    )
    return [*lines, trend] if trend else lines


def basic_insights(summary: Summary) -> dict[str, list[str]]:
    """Short, rule-based observations per section for every tier (no AI, numbers only)."""
    out: dict[str, list[str]] = {}
    if summary.hydration:
        out["hydration"] = _hydration_notes(summary.hydration)
    if summary.nutrition:
        out["nutrition"] = _nutrition_notes(summary.nutrition)
    if summary.sleep:
        out["sleep"] = _sleep_notes(summary.sleep)
    return out


def fallback_advanced(summary: Summary) -> AdvancedInsights:
    """Rule-based trend and recommendations when the AI call was skipped or failed (cap reached,
    provider down): STAR still gets the page, from the same numbers."""
    parts: list[str] = []
    recs: list[str] = []
    h, n, s = summary.hydration, summary.nutrition, summary.sleep
    if h and h["days_logged"]:
        parts.append(f"You reached your water goal on {h['goal_met_pct']}% of logged days.")
        if h["goal_met_pct"] < HYDRATION_GOOD_PCT:
            recs.append("Increase water intake on low days; keep a bottle within reach.")
    if n and n["days_logged"]:
        parts.append(f"Your calories averaged {n['avg_target_pct']}% of your target.")
        if n["protein_kcal_pct"] < PROTEIN_MIN_KCAL_PCT:
            recs.append("Increase protein intake: add dal, paneer, eggs or curd to dinner.")
        if n["avg_fiber_g"] < FIBRE_MIN_G:
            recs.append("Add a vegetable or fruit to each meal to raise fibre.")
    if s and s["nights_logged"]:
        parts.append(f"You met your sleep goal on {s['goal_met_pct']}% of nights.")
        recs.append("Keep your sleep schedule consistent, even on weekends.")
    if not parts:
        parts.append("Very little was logged in this period.")
        recs.append("Log your water, meals and sleep every day to see clearer trends.")
    return AdvancedInsights(" ".join(parts), recs[:4])


def _hm(minutes: float) -> str:
    m = round(minutes)
    return f"{m // 60}h {m % 60:02d}m"


def _period(meta: ReportMeta) -> str:
    days = (meta.period_to - meta.period_from).days + 1
    return (
        f"{meta.period_from:%d %b} - {meta.period_to:%d %b %Y} "
        f"({days} day{'s' if days != 1 else ''})"
    )


def _signed(value: int, unit: str = "%") -> str:
    return f"{'+' if value >= 0 else '-'}{abs(value)}{unit}"


class _Pdf:
    """Canvas helpers for the report pages; y runs down from the top margin."""

    def __init__(self, meta: ReportMeta) -> None:
        self.buffer = io.BytesIO()
        self.c = Canvas(self.buffer, pagesize=A4, pageCompression=1)
        self.c.setTitle("NaraaCare health report")
        self.c.setAuthor("NaraaCare")
        self.meta = meta
        self.page = 0
        self.y = 0.0
        self.footer_left = ""

    # ------------------------------------------------------------------ pages
    def new_page(self) -> None:
        if self.page:
            self._footer()
            self.c.showPage()
        self.page += 1
        self.y = PAGE_H - MARGIN

    def _footer(self) -> None:
        self.c.setStrokeColor(LINE)
        self.c.line(MARGIN, 44, PAGE_W - MARGIN, 44)
        self.c.setFont("Helvetica", 8)
        self.c.setFillColor(MUTED)
        if self.footer_left:
            self.c.drawString(MARGIN, 30, _plain(self.footer_left))
            self.c.drawRightString(PAGE_W - MARGIN, 30, "NaraaCare")
        else:
            self.c.drawCentredString(PAGE_W / 2, 30, f"Page {self.page}")
        self.footer_left = ""

    def need(self, height: float) -> None:
        if self.y - height < BOTTOM:
            self.new_page()

    def finish(self) -> bytes:
        self._footer()
        self.c.save()
        return self.buffer.getvalue()

    # ------------------------------------------------------------------ text
    def text(
        self,
        value: object,
        *,
        size: float = 10,
        bold: bool = False,
        colour: Any = INK,
        gap: float = 4,
        x: float = MARGIN,
        width: float = CONTENT_W,
    ) -> None:
        font = "Helvetica-Bold" if bold else "Helvetica"
        lines = simpleSplit(_plain(value, 2000), font, size, width) or [""]
        for line in lines:
            self.need(size + gap)
            self.c.setFont(font, size)
            self.c.setFillColor(colour)
            self.y -= size
            self.c.drawString(x, self.y, line)
            self.y -= gap

    def heading(self, value: str, size: float = 11) -> None:
        self.need(40)
        self.y -= 8
        self.text(value, size=size, bold=True, gap=8)

    def checklist(self, lines: Sequence[str], colour: Any) -> None:
        for line in lines:
            wrapped = simpleSplit(_plain(line, 400), "Helvetica", 9.5, CONTENT_W - 20) or [""]
            self.need(14 * len(wrapped) + 4)
            top = self.y - 9.5
            self._tick(MARGIN + 2, top + 1, colour)
            for part in wrapped:
                self.c.setFont("Helvetica", 9.5)
                self.c.setFillColor(INK)
                self.y -= 9.5
                self.c.drawString(MARGIN + 18, self.y, part)
                self.y -= 4.5
            self.y -= 4

    def _tick(self, x: float, y: float, colour: Any) -> None:
        self.c.setStrokeColor(colour)
        self.c.setLineWidth(1.6)
        path = self.c.beginPath()
        path.moveTo(x, y + 4)
        path.lineTo(x + 3.5, y + 0.5)
        path.lineTo(x + 10, y + 8)
        self.c.drawPath(path, stroke=1, fill=0)
        self.c.setLineWidth(1)

    # ------------------------------------------------------------------ shapes
    def icon(self, section: str, x: float, y: float, size: float = 26) -> None:
        """A tinted rounded square with a simple vector glyph (no image files)."""
        c = self.c
        colour = SECTION_COLOURS[section]
        c.setFillColor(SECTION_TINTS[section])
        c.roundRect(x, y, size, size, 6, stroke=0, fill=1)
        cx, cy, r = x + size / 2, y + size / 2, size * 0.28
        c.setFillColor(colour)
        c.setStrokeColor(colour)
        if section == "hydration":
            p = c.beginPath()
            p.moveTo(cx, cy + r * 1.25)
            p.curveTo(cx + r * 1.1, cy, cx + r, cy - r, cx, cy - r)
            p.curveTo(cx - r, cy - r, cx - r * 1.1, cy, cx, cy + r * 1.25)
            c.drawPath(p, stroke=0, fill=1)
        elif section == "nutrition":
            c.setLineWidth(1.6)
            c.line(cx - r * 0.5, cy - r, cx - r * 0.5, cy + r)
            c.line(cx + r * 0.5, cy - r, cx + r * 0.5, cy + r)
            c.circle(cx + r * 0.5, cy + r * 0.45, r * 0.32, stroke=0, fill=1)
            c.setLineWidth(1)
        elif section == "sleep":
            c.circle(cx, cy, r, stroke=0, fill=1)
            c.setFillColor(SECTION_TINTS[section])
            c.circle(cx + r * 0.45, cy + r * 0.35, r * 0.85, stroke=0, fill=1)
        else:
            p = c.beginPath()
            for i in range(8):
                rad = r * (1.2 if i % 2 == 0 else 0.45)
                angle = math.pi / 2 + i * math.pi / 4
                px, py = cx + rad * math.cos(angle), cy + rad * math.sin(angle)
                if i == 0:
                    p.moveTo(px, py)
                else:
                    p.lineTo(px, py)
            p.close()
            c.drawPath(p, stroke=0, fill=1)

    def section_title(self, section: str) -> None:
        self.need(60)
        self.icon(section, MARGIN, self.y - 30, 30)
        self.c.setFont("Helvetica-Bold", 18)
        self.c.setFillColor(SECTION_COLOURS[section])
        self.c.drawString(MARGIN + 42, self.y - 21, SECTION_TITLES[section])
        self.y -= 48

    def tiles(self, items: Sequence[tuple[str, str]], tint: Any) -> None:
        """A row of equal tiles: a small label over a bold value."""
        gap = 8
        width = (CONTENT_W - gap * (len(items) - 1)) / max(len(items), 1)
        height = 50
        self.need(height + 10)
        top = self.y
        for i, (label, value) in enumerate(items):
            x = MARGIN + i * (width + gap)
            self.c.setFillColor(tint)
            self.c.roundRect(x, top - height, width, height, 8, stroke=0, fill=1)
            self.c.setFillColor(MUTED)
            self.c.setFont("Helvetica", 8)
            self.c.drawCentredString(x + width / 2, top - 17, _plain(label, 40))
            self.c.setFillColor(INK)
            self.c.setFont("Helvetica-Bold", 13)
            self.c.drawCentredString(x + width / 2, top - 37, _plain(value, 30))
        self.y -= height + 10

    def chart(
        self, title: str, labels: Sequence[str], values: Sequence[float], colour: Any
    ) -> None:
        height = 160.0
        self.need(height + 30)
        self.text(title, size=9.5, bold=True, gap=4)
        drawing = Drawing(CONTENT_W, height)
        bars = VerticalBarChart()
        bars.x, bars.y = 28, 18
        bars.width, bars.height = CONTENT_W - 36, height - 26
        bars.data = [list(values) or [0]]
        bars.bars[0].fillColor = colour
        bars.bars[0].strokeColor = None
        bars.barSpacing = 1
        bars.groupSpacing = 2
        bars.valueAxis.valueMin = 0
        top = max([*values, 1])
        bars.valueAxis.valueMax = top * 1.15
        bars.valueAxis.visibleGrid = True
        bars.valueAxis.gridStrokeColor = LINE
        bars.valueAxis.strokeColor = None
        bars.valueAxis.labels.fontName = "Helvetica"
        bars.valueAxis.labels.fontSize = 7
        bars.valueAxis.labels.fillColor = MUTED
        step = max(1, len(labels) // 5)
        bars.categoryAxis.categoryNames = [
            _plain(lbl, 10) if i % step == 0 else "" for i, lbl in enumerate(labels)
        ] or [""]
        bars.categoryAxis.strokeColor = LINE
        bars.categoryAxis.labels.fontName = "Helvetica"
        bars.categoryAxis.labels.fontSize = 7
        bars.categoryAxis.labels.fillColor = MUTED
        drawing.add(bars)
        renderPDF.draw(drawing, self.c, MARGIN, self.y - height)
        self.y -= height + 8

    def meter_rows(self, rows: Sequence[tuple[str, str, float]], colour: Any, tint: Any) -> None:
        """Label, a bar filled to a share (0..1) with the amount inside, and the percentage."""
        for label, amount, share in rows:
            self.need(22)
            top = self.y
            self.c.setFont("Helvetica", 9)
            self.c.setFillColor(INK)
            self.c.drawString(MARGIN, top - 12, _plain(label, 30))
            bar_x, bar_w = MARGIN + 90, CONTENT_W - 140
            self.c.setFillColor(tint)
            self.c.roundRect(bar_x, top - 16, bar_w, 14, 4, stroke=0, fill=1)
            self.c.setFillColor(colour)
            self.c.roundRect(bar_x, top - 16, bar_w * min(share, 1), 3, 1.5, stroke=0, fill=1)
            self.c.setFillColor(INK)
            self.c.drawCentredString(bar_x + bar_w / 2, top - 12, _plain(amount, 30))
            self.c.drawRightString(PAGE_W - MARGIN, top - 12, f"{round(100 * share)}%")
            self.y -= 22

    def table(self, rows: Sequence[tuple[str, str]]) -> None:
        for left, right in rows:
            self.need(20)
            self.c.setStrokeColor(LINE)
            self.c.line(MARGIN, self.y, PAGE_W - MARGIN, self.y)
            self.c.setFont("Helvetica", 9)
            self.c.setFillColor(INK)
            self.c.drawString(MARGIN + 4, self.y - 13, _plain(left, 60))
            self.c.setFillColor(MUTED)
            self.c.drawString(MARGIN + 150, self.y - 13, _plain(right, 60))
            self.y -= 20

    def donut(self, centre: str, sub: str, legend: Sequence[tuple[str, int, str]]) -> None:
        """Ring split by count with a legend: (name, count, detail)."""
        size = 110.0
        self.need(size + 16)
        cx, cy, r = MARGIN + size / 2, self.y - size / 2 - 4, size / 2
        total = sum(n for _, n, _ in legend) or 1
        start = 90.0
        for (_, n, _), colour in zip(legend, QUALITY_COLOURS, strict=False):
            extent = -360 * n / total
            if n:
                self.c.setFillColor(colour)
                p = self.c.beginPath()
                p.moveTo(cx, cy)
                p.arcTo(cx - r, cy - r, cx + r, cy + r, start, extent)
                p.close()
                self.c.drawPath(p, stroke=0, fill=1)
            start += extent
        self.c.setFillColor(colors.white)
        self.c.circle(cx, cy, r * 0.68, stroke=0, fill=1)
        self.c.setFillColor(INK)
        self.c.setFont("Helvetica-Bold", 16)
        self.c.drawCentredString(cx, cy + 1, _plain(centre, 10))
        self.c.setFont("Helvetica", 8)
        self.c.setFillColor(MUTED)
        self.c.drawCentredString(cx, cy - 12, _plain(sub, 20))
        lx = MARGIN + size + 30
        ly = self.y - 30
        for (name, n, detail), colour in zip(legend, QUALITY_COLOURS, strict=False):
            self.c.setFillColor(colour)
            self.c.circle(lx, ly + 3, 3.5, stroke=0, fill=1)
            self.c.setFillColor(INK)
            self.c.setFont("Helvetica", 9.5)
            self.c.drawString(lx + 12, ly, _plain(name, 20))
            self.c.setFillColor(MUTED)
            self.c.drawString(lx + 70, ly, _plain(f"{_pct(n, total)}% ({detail})", 40))
            ly -= 24
        self.y -= size + 16

    def trend_card(self, section: str, title: str, detail: str) -> None:
        height = 52
        self.need(height + 8)
        top = self.y
        self.c.setStrokeColor(LINE)
        self.c.setFillColor(colors.white)
        self.c.roundRect(MARGIN, top - height, CONTENT_W, height, 10, stroke=1, fill=1)
        self.icon(section, MARGIN + 12, top - height + 12, 28)
        self.c.setFillColor(INK)
        self.c.setFont("Helvetica-Bold", 10.5)
        self.c.drawString(MARGIN + 52, top - 22, _plain(title, 40))
        self.c.setFillColor(MUTED)
        self.c.setFont("Helvetica", 9)
        self.c.drawString(MARGIN + 52, top - 37, _plain(detail, 90))
        self.y -= height + 8


def _cover(pdf: _Pdf, meta: ReportMeta, summary: Summary) -> None:  # noqa: PLR0915 - one page layout
    c = pdf.c
    pdf.new_page()
    # Brand mark: a blue rounded square with a white drop, then the name.
    c.setFillColor(BRAND)
    c.roundRect(MARGIN, pdf.y - 24, 24, 24, 6, stroke=0, fill=1)
    c.setFillColor(colors.white)
    p = c.beginPath()
    cx, cy, r = MARGIN + 12, pdf.y - 12, 6
    p.moveTo(cx, cy + r * 1.25)
    p.curveTo(cx + r * 1.1, cy, cx + r, cy - r, cx, cy - r)
    p.curveTo(cx - r, cy - r, cx - r * 1.1, cy, cx, cy + r * 1.25)
    c.drawPath(p, stroke=0, fill=1)
    c.setFillColor(BRAND)
    c.setFont("Helvetica-Bold", 14)
    c.drawString(MARGIN + 32, pdf.y - 17, "NaraaCare")
    pdf.y -= 56
    pdf.text("Health Report", size=26, bold=True, gap=8)
    pdf.text(_period(meta), size=12, colour=MUTED, gap=20)

    name = meta.full_name or (meta.username or "")
    if name or meta.username:
        initial = _plain((name or "?")[:1].upper(), 1)
        c.setFillColor(TILE)
        c.circle(MARGIN + 16, pdf.y - 16, 16, stroke=0, fill=1)
        c.setFillColor(BRAND)
        c.setFont("Helvetica-Bold", 13)
        c.drawCentredString(MARGIN + 16, pdf.y - 21, initial)
        c.setFillColor(INK)
        c.setFont("Helvetica-Bold", 11)
        c.drawString(MARGIN + 42, pdf.y - 12, _plain(name, 60))
        if meta.username:
            c.setFillColor(MUTED)
            c.setFont("Helvetica", 9)
            c.drawString(MARGIN + 42, pdf.y - 26, _plain(f"@{meta.username}", 40))
        pdf.y -= 52

    included = [SECTION_TITLES[s] for s in meta.sections if s in SECTION_TITLES]
    if meta.insights:
        included.append("Advanced Insights")
    pdf.text("Report includes", size=11, bold=True, gap=4)
    pdf.text(", ".join(included), size=9, colour=MUTED, gap=12)

    tiles = [
        (s, getattr(summary, s)["goal_met_pct"])
        for s in ("hydration", "nutrition", "sleep")
        if getattr(summary, s)
    ]
    if tiles:
        gap, height = 10, 92
        width = (CONTENT_W - gap * (len(tiles) - 1)) / len(tiles)
        top = pdf.y
        for i, (section, pct) in enumerate(tiles):
            x = MARGIN + i * (width + gap)
            c.setStrokeColor(LINE)
            c.setFillColor(colors.white)
            c.roundRect(x, top - height, width, height, 10, stroke=1, fill=1)
            pdf.icon(section, x + width / 2 - 13, top - 36, 26)
            c.setFillColor(SECTION_COLOURS[section])
            c.setFont("Helvetica", 9)
            c.drawCentredString(x + width / 2, top - 50, SECTION_TITLES[section])
            c.setFillColor(INK)
            c.setFont("Helvetica-Bold", 16)
            c.drawCentredString(x + width / 2, top - 70, f"{pct}%")
            c.setFillColor(MUTED)
            c.setFont("Helvetica", 7.5)
            c.drawCentredString(x + width / 2, top - 82, "Goal achievement")
        pdf.y -= height + 24

    highlights: list[str] = []
    if summary.hydration and summary.hydration["days_logged"]:
        h = summary.hydration
        highlights.append(
            f"You hit your hydration goal on {h['goal_met_days']} of {h['days_logged']} days."
        )
    if summary.nutrition and summary.nutrition["days_logged"]:
        highlights.append(
            f"Your average protein intake was {summary.nutrition['avg_protein_g']:g} g/day."
        )
    if summary.sleep and summary.sleep["nights_logged"]:
        s = summary.sleep
        highlights.append(
            f"You met your sleep goal on {s['goal_met_days']} of {s['nights_logged']} nights."
        )
    if highlights:
        pdf.text("Highlights", size=11, bold=True, gap=8)
        pdf.checklist(highlights, BRAND)
    pdf.footer_left = f"Generated on {meta.generated_on:%d %b %Y}"


def _hydration_page(
    pdf: _Pdf, summary: Summary, days: Sequence[dict[str, Any]], notes: list[str]
) -> None:
    h = summary.hydration
    pdf.new_page()
    pdf.section_title("hydration")
    pdf.heading("Overview", 10)
    pdf.tiles(
        [
            ("Average Intake", f"{h['avg_ml'] / 1000:.1f} L/day"),
            ("Goal", f"{h['avg_need_ml'] / 1000:.1f} L/day"),
            ("Total Intake", f"{h['total_ml'] / 1000:.1f} L"),
        ],
        SECTION_TINTS["hydration"],
    )
    pdf.y -= 6
    pdf.chart(
        "Daily Water Intake (L)",
        [f"{d['local_date']:%d %b}" for d in days],
        [(_num(d.get("water_ml")) or 0) / 1000 for d in days],
        SECTION_COLOURS["hydration"],
    )
    pdf.heading("Insights", 10)
    pdf.checklist(notes, SECTION_COLOURS["hydration"])


def _nutrition_page(
    pdf: _Pdf,
    summary: Summary,
    days: Sequence[dict[str, Any]],
    extras: Mapping[str, Any],
    notes: list[str],
) -> None:
    n = summary.nutrition
    colour, tint = SECTION_COLOURS["nutrition"], SECTION_TINTS["nutrition"]
    pdf.new_page()
    pdf.section_title("nutrition")
    pdf.heading("Overview", 10)
    pdf.tiles(
        [
            ("Avg. Calories", f"{n['avg_kcal']:,} kcal"),
            ("Avg. Protein", f"{n['avg_protein_g']:g} g"),
            ("Avg. Carbs", f"{n['avg_carbs_g']:g} g"),
            ("Avg. Fat", f"{n['avg_fat_g']:g} g"),
        ],
        tint,
    )
    pdf.y -= 6
    pdf.chart(
        "Daily Calories (kcal)",
        [f"{d['local_date']:%d %b}" for d in days],
        [_num(d.get("kcal")) or 0 for d in days],
        colour,
    )
    rows: list[tuple[str, str, float]] = []
    for label, key, target_key in (
        ("Protein", "avg_protein_g", "target_protein_g"),
        ("Carbs", "avg_carbs_g", "target_carbs_g"),
        ("Fat", "avg_fat_g", "target_fat_g"),
    ):
        target = _num(extras.get(target_key))
        if target:
            rows.append((label, f"{n[key]:g} g / {target:g} g", n[key] / target))
    rows.append(
        ("Fibre", f"{n['avg_fiber_g']:g} g / {FIBRE_MIN_G} g", n["avg_fiber_g"] / FIBRE_MIN_G)
    )
    pdf.heading("Top Nutrients (Daily Average)", 10)
    pdf.meter_rows(rows, colour, tint)
    shares = extras.get("meal_kcal_pct") or {}
    if isinstance(shares, Mapping) and shares:
        ranked = sorted(shares.items(), key=lambda kv: -(_num(kv[1]) or 0))
        pdf.heading("Top Meals", 10)
        pdf.table(
            [
                (f"{i}.  {MEAL_NAMES.get(str(k), 'Other')}", f"{_num(v) or 0:g}% of daily calories")
                for i, (k, v) in enumerate(ranked, start=1)
            ]
        )
    if extras.get("foods_logged") is not None:
        pdf.need(24)
        pdf.y -= 6
        pdf.c.setFont("Helvetica-Bold", 10)
        pdf.c.setFillColor(INK)
        pdf.c.drawString(MARGIN, pdf.y - 10, "Foods Logged")
        pdf.c.setFont("Helvetica", 10)
        pdf.c.drawRightString(
            PAGE_W - MARGIN, pdf.y - 10, f"{_num(extras['foods_logged']) or 0:g} items"
        )
        pdf.y -= 22
    pdf.heading("Insights", 10)
    pdf.checklist(notes, colour)


def _sleep_page(
    pdf: _Pdf, summary: Summary, days: Sequence[dict[str, Any]], notes: list[str]
) -> None:
    s = summary.sleep
    colour, tint = SECTION_COLOURS["sleep"], SECTION_TINTS["sleep"]
    pdf.new_page()
    pdf.section_title("sleep")
    pdf.heading("Overview", 10)
    pdf.tiles(
        [
            ("Average Sleep", _hm(s["avg_min"])),
            ("Goal", _hm(s["avg_goal_min"])),
            ("Total Nights", str(s["nights_logged"])),
        ],
        tint,
    )
    pdf.y -= 6
    pdf.chart(
        "Sleep Duration (Hours)",
        [f"{d['local_date']:%d %b}" for d in days],
        [(_num(d.get("sleep_min")) or 0) / 60 for d in days],
        colour,
    )
    if s["nights_logged"]:
        pdf.heading("Sleep Quality (Avg.)", 10)
        label = (
            "Good"
            if s["good_nights"] >= max(s["fair_nights"], s["low_nights"])
            else ("Fair" if s["fair_nights"] >= s["low_nights"] else "Low")
        )
        pdf.donut(
            f"{s['avg_score_pct']}%",
            label,
            [
                ("Good", s["good_nights"], f"{s['good_nights']} nights"),
                ("Fair", s["fair_nights"], f"{s['fair_nights']} nights"),
                ("Low", s["low_nights"], f"{s['low_nights']} nights"),
            ],
        )
    pdf.heading("Insights", 10)
    pdf.checklist(notes, colour)


def _advanced_page(pdf: _Pdf, summary: Summary, advanced: AdvancedInsights, ai: bool) -> None:
    v = summary.vs_previous
    prev = v.get("previous_days") or summary.days
    pdf.new_page()
    pdf.section_title("insights")
    pdf.heading("Trends", 10)
    no_data = f"Not enough data from the previous {prev} days"
    if summary.hydration:
        ch = v.get("water_change_pct")
        pdf.trend_card(
            "hydration",
            "Hydration",
            f"{_signed(ch)} water intake vs previous {prev} days" if ch is not None else no_data,
        )
    if summary.nutrition:
        ch = v.get("protein_change_pct")
        pdf.trend_card(
            "nutrition",
            "Nutrition",
            f"{_signed(ch)} protein intake vs previous {prev} days" if ch is not None else no_data,
        )
    if summary.sleep:
        ch = v.get("sleep_change_min")
        detail = (
            f"{'+' if ch >= 0 else '-'}{_hm(abs(ch))} per night vs previous {prev} days"
            if ch is not None
            else no_data
        )
        pdf.trend_card("sleep", "Sleep", detail)
    if advanced.trend:
        pdf.heading("Overall Trend", 10)
        pdf.text(advanced.trend, size=9.5, gap=4)
    if advanced.recommendations:
        pdf.heading("Recommendations", 10)
        pdf.checklist(list(advanced.recommendations), SECTION_COLOURS["insights"])
    pdf.y -= 6
    pdf.text(
        "Generated by AI from your period averages only. Check anything important with a "
        "professional."
        if ai
        else "Worked out from your period averages.",
        size=7.5,
        colour=MUTED,
    )


def build_pdf(
    meta: ReportMeta,
    days: Sequence[dict[str, Any]],
    advanced: AdvancedInsights | None = None,
    extras: Mapping[str, Any] | None = None,
) -> bytes:
    extras = extras or {}
    summary = summarise(days, meta.sections, extras)
    basic = basic_insights(summary)
    pdf = _Pdf(meta)
    _cover(pdf, meta, summary)
    pages: dict[str, Callable[[], None]] = {
        "hydration": lambda: _hydration_page(pdf, summary, days, basic["hydration"]),
        "nutrition": lambda: _nutrition_page(pdf, summary, days, extras, basic["nutrition"]),
        "sleep": lambda: _sleep_page(pdf, summary, days, basic["sleep"]),
    }
    for section in ("hydration", "nutrition", "sleep"):
        if getattr(summary, section):
            pages[section]()
    if meta.insights:
        _advanced_page(pdf, summary, advanced or fallback_advanced(summary), advanced is not None)
    pdf.need(110)
    pdf.y -= 14
    pdf.text("About this report", size=10, bold=True, gap=4)
    pdf.text(DISCLAIMER, size=8, colour=MUTED, gap=3)
    return pdf.finish()
