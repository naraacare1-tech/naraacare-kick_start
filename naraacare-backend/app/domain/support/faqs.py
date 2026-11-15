"""Frequently asked questions (Help & Support, Session 14). Plain text only; the app shows them with
Text widgets. DRAFT written from the product documents: the owner reviews the wording before
release (Figma note "need list of questions and answers", docs/pending-tasks.md)."""

from __future__ import annotations

FAQS: tuple[tuple[str, str, str], ...] = (
    (
        "what_is_naraacare",
        "What is NaraaCare?",
        "NaraaCare helps you build healthy daily habits. You log what you drink, eat and how you "
        "sleep, and your avatar fills up as you get closer to your personal goals for the day.",
    ),
    (
        "hydration_tracking",
        "How does it track hydration?",
        "Your daily water need is worked out from your profile, activity and the weather where you "
        "are. Each drink counts by its type (for example tea counts slightly less than water) and "
        "water in food and workouts are taken into account.",
    ),
    (
        "nutrition_tracking",
        "How are calories and nutrients calculated?",
        "Foods come from our food database. Your calorie target is based on your age, height, "
        "weight, activity level and goal. STAR members see the full nutrient breakdown.",
    ),
    (
        "sleep_tracking",
        "How is my sleep score worked out?",
        "Sleep tracking is part of STAR. We count the time between falling asleep and waking up, "
        "minus any time you were awake in the night, and compare it with the sleep goal for your "
        "age.",
    ),
    (
        "streak",
        "How does my streak work?",
        "Your streak grows by one for every day you log any hydration, nutrition or sleep data. If "
        "a whole day passes with nothing logged, the streak starts again from zero.",
    ),
    (
        "offline",
        "Can I log while I am offline?",
        "Yes. Entries are saved on your phone and sent automatically when you are back online. If "
        "the same entry was changed on another device, the most recent saved version is kept and "
        "the app tells you.",
    ),
    (
        "care_circle",
        "What can members of my Care Circle see?",
        "Only the avatars you choose to share with that circle (hydration, nutrition and, on STAR, "
        "sleep). You can change what you share or leave a circle at any time.",
    ),
    (
        "rin_ai",
        "What is Rin AI?",
        "Rin is the AI assistant included with STAR. It can answer wellness questions and help you "
        "log meals and drinks. It does not give medical advice. Rin only uses your own data, and "
        "only after you agree to AI processing.",
    ),
    (
        "reports",
        "How do I download a report?",
        "Go to Profile, open your streak and tap Download report. Everyone can create monthly "
        "reports for hydration and nutrition; STAR members can also choose any date range and add "
        "sleep and AI insights. Reports stay available for 7 days.",
    ),
    (
        "star_plan",
        "What do I get with STAR?",
        "STAR adds sleep tracking, the full nutrient breakdown, voice and barcode logging, custom "
        "drinks, Rin AI, custom reports with insights, and sleep sharing in Care Circles.",
    ),
    (
        "data_privacy",
        "Is my health data safe?",
        "Your data is sent over encrypted connections and is never sold. You can see and change "
        "your privacy choices in Settings at any time.",
    ),
)


def search(query: str | None) -> list[dict[str, str]]:
    items = [{"id": i, "question": q, "answer": a} for i, q, a in FAQS]
    if not query:
        return items
    needle = query.casefold()
    return [
        f for f in items if needle in f["question"].casefold() or needle in f["answer"].casefold()
    ]
