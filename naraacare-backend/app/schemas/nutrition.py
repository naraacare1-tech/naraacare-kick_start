"""Nutrition requests (doc 04 sections 2.4 and 2.16). Every string is a Safe* type or a closed
``Literal``; models forbid unknown fields (no ``user_id`` anywhere: the user is the token subject,
which also fixes the DOC sample that sent one). Quantities follow the meal rules (0.25..20 in steps
of 0.25); units and sizes are the ``ref.unit`` codes. Responses are plain JSON built by the service.
"""

from __future__ import annotations

from decimal import Decimal
from typing import Annotated, Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, Strict

from app.core.security.validators import (
    SafeCode40,
    SafeLocale,
    SafeShortText60,
    SafeShortText120,
    SafeText300,
)
from app.schemas.common import JsonDecimal, JsonUUID

UnitCode = Literal[
    "katori",
    "bowl",
    "tbsp",
    "tsp",
    "cup",
    "glass",
    "mug",
    "cutting",
    "piece",
    "plate",
    "gram",
    "ml",
    "serving",
]
UnitSize = Literal["standard", "small", "medium", "large", "half", "full"]
MealType = Literal["breakfast", "lunch", "dinner", "snack"]
MealSource = Literal["search", "voice", "barcode", "saved", "rin"]
Quantity = Annotated[JsonDecimal, Field(ge=Decimal("0.25"), le=20, multiple_of=Decimal("0.25"))]
JsonDateTime = Annotated[AwareDatetime, Strict(False)]
NutrientAmount = Annotated[JsonDecimal, Field(ge=0, le=100000, decimal_places=3)]


class _Model(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class MealItemIn(_Model):
    food_id: JsonUUID
    quantity: Quantity
    unit_code: UnitCode
    unit_size: UnitSize | None = None


MealItems = Annotated[list[MealItemIn], Field(min_length=1, max_length=30)]


class MealCreate(_Model):
    client_entry_id: JsonUUID
    logged_at: JsonDateTime
    meal_type: MealType
    source: MealSource
    items: MealItems


class MealUpdate(_Model):
    meal_type: MealType | None = None
    items: MealItems | None = None


class SavedMealCreate(_Model):
    name: SafeShortText60
    items: MealItems


class VoiceParseRequest(_Model):
    transcript: SafeText300
    locale: SafeLocale


class AdminNutrients(_Model):
    """Per 100 g or 100 ml. Omitted = 0. Column CHECKs in the database give the per-unit maxima."""

    calories: NutrientAmount | None = None
    protein: NutrientAmount | None = None
    carbohydrates: NutrientAmount | None = None
    fat: NutrientAmount | None = None
    dietary_fiber: NutrientAmount | None = None
    total_sugar: NutrientAmount | None = None
    saturated_fat: NutrientAmount | None = None
    polyunsaturated_fat: NutrientAmount | None = None
    monounsaturated_fat: NutrientAmount | None = None
    trans_fat: NutrientAmount | None = None
    cholesterol: NutrientAmount | None = None
    sodium: NutrientAmount | None = None
    potassium: NutrientAmount | None = None
    calcium: NutrientAmount | None = None
    iron: NutrientAmount | None = None
    vitamin_a: NutrientAmount | None = None
    vitamin_c: NutrientAmount | None = None


class AdminFoodIn(_Model):
    """POST /admin/foods and PATCH /admin/foods/{id} (full replace of the food's fields)."""

    name: SafeShortText120
    category_code: SafeCode40
    basis: Literal["g", "ml"]
    density_g_per_ml: Annotated[JsonDecimal, Field(gt=0, le=3, decimal_places=3)] | None = None
    is_cooked: bool
    source_ref: SafeShortText120
    nutrients: AdminNutrients
    aliases: Annotated[list[SafeShortText60], Field(max_length=20)] | None = None
    alias_language: Literal["en", "hi", "hinglish"] = "hinglish"
