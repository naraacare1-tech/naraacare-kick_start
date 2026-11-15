"""Profile, onboarding, settings, targets and entitlements (doc 04 section 2.2).

Units are metric on the wire (the app converts for display, doc 06 section 1). Ranges match the
database CHECKs; codes are closed ``Literal`` sets or ``SafeCode40`` checked against reference data.
"""

from __future__ import annotations

from datetime import date, datetime, time
from decimal import Decimal
from typing import Annotated, Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field

from app.core.security.validators import (
    SafeCode40,
    SafeEmail,
    SafeLocale,
    SafeName,
    SafeShortText20,
    SafeTimezone,
    SafeUsername,
)
from app.schemas.common import JsonDecimal, JsonTime

Sex = Literal["female", "male"]
AvatarCode = Literal[
    "female_ectomorph",
    "female_mesomorph",
    "female_endomorph",
    "male_ectomorph",
    "male_mesomorph",
    "male_endomorph",
]
ActivityLevel = Literal["sedentary", "lightly_active", "moderately_active", "very_active"]
BodyType = Literal["ectomorph", "mesomorph", "endomorph"]
WeightGoal = Literal[
    "aggressive_loss",
    "moderate_loss",
    "standard_loss",
    "mild_loss",
    "maintain",
    "mild_gain",
    "standard_gain",
    "aggressive_gain",
]
BmiCategory = Literal["underweight", "normal", "overweight_obese"]
ConsentPurpose = Literal[
    "terms", "privacy", "health_data", "ai_processing", "circle_sharing", "marketing"
]
Role = Literal["user", "nutritionist", "support", "admin"]

HeightCm = Annotated[JsonDecimal, Field(ge=120, le=230, decimal_places=1)]
WeightKg = Annotated[JsonDecimal, Field(ge=30, le=250, decimal_places=2)]
AgeYears = Annotated[int, Field(ge=18, le=100)]
ConditionCodes = Annotated[list[SafeCode40], Field(max_length=20)]


class Strict(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)


class ProfileFields(Strict):
    biological_sex: Sex | None = None
    avatar_code: AvatarCode | None = None
    full_name: SafeName | None = None
    height_cm: HeightCm | None = None
    weight_kg: WeightKg | None = None
    weight_goal: WeightGoal | None = None
    target_weight_kg: WeightKg | None = None
    medical_condition_codes: ConditionCodes | None = None
    age_years: AgeYears | None = None
    activity_level: ActivityLevel | None = None
    body_type: BodyType | None = None


class OnboardingStepRequest(ProfileFields):
    """Only the fields of the step being saved may be sent (checked per step)."""


class ProfilePatchRequest(ProfileFields):
    """Any subset; omitted fields stay unchanged."""


class SettingsRequest(Strict):
    height_unit: Literal["cm", "ft_in"]
    weight_unit: Literal["kg", "lb"]
    temperature_unit: Literal["c", "f"]
    timezone: SafeTimezone
    locale: SafeLocale
    sleep_start_local: JsonTime
    wake_local: JsonTime
    biometric_lock: bool


class ConsentIn(Strict):
    purpose: ConsentPurpose
    policy_version: SafeShortText20
    granted: bool


class CompleteOnboardingRequest(Strict):
    consents: Annotated[list[ConsentIn], Field(min_length=1, max_length=10)]


class UsernameRequest(Strict):
    username: SafeUsername


# ------------------------------------------------------------------------------- responses
class ProfileOut(BaseModel):
    biological_sex: Sex | None
    avatar_code: AvatarCode | None
    full_name: SafeName | None
    age_years: int | None
    height_cm: Decimal | None
    weight_kg: Decimal | None
    target_weight_kg: Decimal | None
    weight_goal: WeightGoal | None
    activity_level: ActivityLevel | None
    body_type: BodyType | None
    medical_condition_codes: list[SafeCode40]


class SettingsOut(BaseModel):
    height_unit: Literal["cm", "ft_in"]
    weight_unit: Literal["kg", "lb"]
    temperature_unit: Literal["c", "f"]
    timezone: SafeTimezone
    locale: SafeLocale
    sleep_start_local: time
    wake_local: time
    sleep_goal_min: int | None
    biometric_lock: bool


class OnboardingState(BaseModel):
    current_step: int
    completed: bool


class Counts(BaseModel):
    connections: int
    circles: int
    current_streak: int
    longest_streak: int


class MeResponse(BaseModel):
    user_id: UUID
    email: SafeEmail
    role: Role
    tier: Literal["standard", "star"]
    username: SafeUsername | None
    member_since: date | None = None
    onboarding: OnboardingState
    profile: ProfileOut
    settings: SettingsOut
    counts: Counts


class OnboardingResponse(BaseModel):
    current_step: int
    completed: bool
    data_so_far: ProfileOut


class StepResponse(BaseModel):
    current_step: int


class NutritionTargetsOut(BaseModel):
    kcal: int
    carbs_g: int
    fat_g: int
    protein_g: int
    safety_override: bool


class PreviewResponse(BaseModel):
    calc_version: SafeShortText20
    bmi: Decimal
    bmi_category: BmiCategory
    healthy_weight_range_kg: tuple[int, int]
    targets: NutritionTargetsOut
    water_need_ml: int


class TargetsResponse(BaseModel):
    effective_date: date
    calc_version: SafeShortText20
    bmi: Decimal
    bmi_category: BmiCategory
    nutrition: NutritionTargetsOut
    water_need_ml: int


class ProfilePatchResponse(BaseModel):
    me: MeResponse
    targets_today: TargetsResponse | None


class GoalOptionsResponse(BaseModel):
    bmi: Decimal
    category: BmiCategory
    allowed_goals: list[WeightGoal]
    healthy_weight_range_kg: tuple[int, int]


class UsernameAvailability(BaseModel):
    available: bool


class EntitlementsResponse(BaseModel):
    tier: Literal["standard", "star"]
    source: SafeCode40
    expires_at: datetime | None
    features: dict[SafeCode40, bool]
    limits: dict[SafeCode40, int]
