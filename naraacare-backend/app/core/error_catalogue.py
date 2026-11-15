"""Error codes (doc 04 §1.1). The only codes the API may return; messages are generic on purpose.

Messages never contain user input, SQL, stack traces or internal identifiers (doc 07 SEC-3.5).
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import StrEnum
from http import HTTPStatus


class ErrorCode(StrEnum):
    BAD_REQUEST = "BAD_REQUEST"
    UNAUTHENTICATED = "UNAUTHENTICATED"
    TOKEN_EXPIRED = "TOKEN_EXPIRED"  # noqa: S105  # nosec B105 - error code, not a secret
    INVALID_CREDENTIALS = "INVALID_CREDENTIALS"
    FORBIDDEN = "FORBIDDEN"
    UPGRADE_REQUIRED = "UPGRADE_REQUIRED"
    DAILY_LIMIT_REACHED = "DAILY_LIMIT_REACHED"
    MONTHLY_LIMIT_REACHED = "MONTHLY_LIMIT_REACHED"
    EDIT_WINDOW_CLOSED = "EDIT_WINDOW_CLOSED"
    SAVED_MEAL_LIMIT = "SAVED_MEAL_LIMIT"
    CUSTOM_DRINK_LIMIT = "CUSTOM_DRINK_LIMIT"
    WATER_BELOW_ZERO = "WATER_BELOW_ZERO"
    SLEEP_OVERLAP = "SLEEP_OVERLAP"
    PURCHASE_INVALID = "PURCHASE_INVALID"
    PURCHASE_TOKEN_IN_USE = "PURCHASE_TOKEN_IN_USE"  # noqa: S105  # nosec B105 - error code
    CONSENT_REQUIRED = "CONSENT_REQUIRED"
    USERNAME_REQUIRED = "USERNAME_REQUIRED"
    USERNAME_CHANGE_TOO_SOON = "USERNAME_CHANGE_TOO_SOON"
    ADMIN_REQUIRED = "ADMIN_REQUIRED"
    NOT_FOUND = "NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    VERSION_CONFLICT = "VERSION_CONFLICT"
    ALREADY_EXISTS = "ALREADY_EXISTS"
    USERNAME_TAKEN = "USERNAME_TAKEN"
    EMAIL_REGISTERED = "EMAIL_REGISTERED"
    ONBOARDING_INCOMPLETE = "ONBOARDING_INCOMPLETE"
    ONBOARDING_ALREADY_COMPLETED = "ONBOARDING_ALREADY_COMPLETED"
    IDENTITY_ALREADY_LINKED = "IDENTITY_ALREADY_LINKED"
    LINK_REQUIRED = "LINK_REQUIRED"
    CIRCLE_FULL = "CIRCLE_FULL"
    ACTION_RESOLVED = "ACTION_RESOLVED"
    LAST_ADMIN = "LAST_ADMIN"
    OTP_EXPIRED = "OTP_EXPIRED"
    INVITE_LINK_EXPIRED = "INVITE_LINK_EXPIRED"
    ACTION_EXPIRED = "ACTION_EXPIRED"
    OTP_LOCKED = "OTP_LOCKED"
    EMAIL_NOT_VERIFIED = "EMAIL_NOT_VERIFIED"
    GOAL_NOT_ALLOWED = "GOAL_NOT_ALLOWED"
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE"
    UNSUPPORTED_MEDIA_TYPE = "UNSUPPORTED_MEDIA_TYPE"
    VALIDATION_FAILED = "VALIDATION_FAILED"
    QUERY_TOO_SHORT = "QUERY_TOO_SHORT"
    SHARES_INVALID = "SHARES_INVALID"
    MENTION_INVALID = "MENTION_INVALID"
    RECIPIENTS_INVALID = "RECIPIENTS_INVALID"
    RECIPIENT_INVALID = "RECIPIENT_INVALID"
    TOO_MANY_MENTIONS = "TOO_MANY_MENTIONS"
    TOO_MANY_INVITEES = "TOO_MANY_INVITEES"
    OTP_INVALID = "OTP_INVALID"
    PASSWORD_REUSED = "PASSWORD_REUSED"  # noqa: S105  # nosec B105
    PASSWORD_WEAK = "PASSWORD_WEAK"  # noqa: S105  # nosec B105
    ACCOUNT_LOCKED = "ACCOUNT_LOCKED"
    RATE_LIMITED = "RATE_LIMITED"
    INVITE_LINK_LIMIT = "INVITE_LINK_LIMIT"
    REPORT_LIMIT_REACHED = "REPORT_LIMIT_REACHED"
    REPORT_NO_DATA = "REPORT_NO_DATA"
    SUPPORT_LIMIT_REACHED = "SUPPORT_LIMIT_REACHED"
    REPORT_RANGE_INVALID = "REPORT_RANGE_INVALID"
    UPLOAD_INVALID = "UPLOAD_INVALID"
    REPORT_NOT_READY = "REPORT_NOT_READY"
    EXPORT_LIMIT_REACHED = "EXPORT_LIMIT_REACHED"
    EXPORT_NOT_READY = "EXPORT_NOT_READY"
    CONSENT_WITHDRAWAL_BLOCKED = "CONSENT_WITHDRAWAL_BLOCKED"
    INTERNAL_ERROR = "INTERNAL_ERROR"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"


@dataclass(frozen=True, slots=True)
class ErrorSpec:
    status: HTTPStatus
    message: str


CATALOGUE: dict[ErrorCode, ErrorSpec] = {
    ErrorCode.BAD_REQUEST: ErrorSpec(HTTPStatus.BAD_REQUEST, "The request could not be read"),
    ErrorCode.UNAUTHENTICATED: ErrorSpec(HTTPStatus.UNAUTHORIZED, "Please sign in"),
    ErrorCode.TOKEN_EXPIRED: ErrorSpec(HTTPStatus.UNAUTHORIZED, "Your session has expired"),
    ErrorCode.INVALID_CREDENTIALS: ErrorSpec(
        HTTPStatus.UNAUTHORIZED, "Email or password is incorrect"
    ),
    ErrorCode.FORBIDDEN: ErrorSpec(HTTPStatus.FORBIDDEN, "You do not have access to this"),
    ErrorCode.UPGRADE_REQUIRED: ErrorSpec(HTTPStatus.FORBIDDEN, "This feature needs STAR"),
    ErrorCode.DAILY_LIMIT_REACHED: ErrorSpec(
        HTTPStatus.FORBIDDEN, "You have reached today's limit"
    ),
    ErrorCode.MONTHLY_LIMIT_REACHED: ErrorSpec(
        HTTPStatus.FORBIDDEN, "You have used this month's Rin allowance"
    ),
    ErrorCode.EDIT_WINDOW_CLOSED: ErrorSpec(
        HTTPStatus.FORBIDDEN, "This entry can no longer be edited"
    ),
    ErrorCode.SAVED_MEAL_LIMIT: ErrorSpec(
        HTTPStatus.FORBIDDEN, "You have saved the maximum number of meals"
    ),
    ErrorCode.CUSTOM_DRINK_LIMIT: ErrorSpec(
        HTTPStatus.FORBIDDEN, "You have saved the maximum number of custom drinks"
    ),
    ErrorCode.WATER_BELOW_ZERO: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_ENTITY, "Today's water cannot go below zero"
    ),
    ErrorCode.SLEEP_OVERLAP: ErrorSpec(HTTPStatus.CONFLICT, "This sleep overlaps another entry"),
    ErrorCode.PURCHASE_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_ENTITY, "This purchase could not be verified"
    ),
    ErrorCode.PURCHASE_TOKEN_IN_USE: ErrorSpec(
        HTTPStatus.CONFLICT, "This purchase belongs to another account"
    ),
    ErrorCode.CONSENT_REQUIRED: ErrorSpec(HTTPStatus.FORBIDDEN, "Your consent is needed first"),
    ErrorCode.USERNAME_REQUIRED: ErrorSpec(HTTPStatus.FORBIDDEN, "Please choose a username first"),
    ErrorCode.USERNAME_CHANGE_TOO_SOON: ErrorSpec(
        HTTPStatus.FORBIDDEN, "Your username can be changed once every 90 days"
    ),
    ErrorCode.ADMIN_REQUIRED: ErrorSpec(HTTPStatus.FORBIDDEN, "Only a circle admin can do this"),
    ErrorCode.NOT_FOUND: ErrorSpec(HTTPStatus.NOT_FOUND, "Not found"),
    ErrorCode.METHOD_NOT_ALLOWED: ErrorSpec(HTTPStatus.METHOD_NOT_ALLOWED, "Method not allowed"),
    ErrorCode.VERSION_CONFLICT: ErrorSpec(HTTPStatus.CONFLICT, "This item was changed elsewhere"),
    ErrorCode.ALREADY_EXISTS: ErrorSpec(HTTPStatus.CONFLICT, "This already exists"),
    ErrorCode.USERNAME_TAKEN: ErrorSpec(HTTPStatus.CONFLICT, "This username is taken"),
    ErrorCode.EMAIL_REGISTERED: ErrorSpec(HTTPStatus.CONFLICT, "This email is already registered"),
    ErrorCode.ONBOARDING_INCOMPLETE: ErrorSpec(
        HTTPStatus.CONFLICT, "Please finish setting up first"
    ),
    ErrorCode.ONBOARDING_ALREADY_COMPLETED: ErrorSpec(
        HTTPStatus.CONFLICT, "Set-up is already complete"
    ),
    ErrorCode.IDENTITY_ALREADY_LINKED: ErrorSpec(
        HTTPStatus.CONFLICT, "This sign-in is linked to another account"
    ),
    ErrorCode.LINK_REQUIRED: ErrorSpec(HTTPStatus.CONFLICT, "Sign in with your password to link"),
    ErrorCode.CIRCLE_FULL: ErrorSpec(HTTPStatus.CONFLICT, "This circle is full"),
    ErrorCode.ACTION_RESOLVED: ErrorSpec(
        HTTPStatus.CONFLICT, "This suggestion was already handled"
    ),
    ErrorCode.LAST_ADMIN: ErrorSpec(HTTPStatus.CONFLICT, "A circle needs at least one admin"),
    ErrorCode.OTP_EXPIRED: ErrorSpec(HTTPStatus.GONE, "This code has expired"),
    ErrorCode.INVITE_LINK_EXPIRED: ErrorSpec(HTTPStatus.GONE, "This invite link has expired"),
    ErrorCode.ACTION_EXPIRED: ErrorSpec(HTTPStatus.GONE, "This suggestion has expired"),
    ErrorCode.OTP_LOCKED: ErrorSpec(HTTPStatus.LOCKED, "Too many wrong codes. Request a new code"),
    ErrorCode.EMAIL_NOT_VERIFIED: ErrorSpec(
        HTTPStatus.FORBIDDEN, "Please verify your email. We have sent you a new code"
    ),
    ErrorCode.GOAL_NOT_ALLOWED: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "This goal is not available for your current weight"
    ),
    ErrorCode.PAYLOAD_TOO_LARGE: ErrorSpec(
        HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "The request is too large"
    ),
    ErrorCode.UNSUPPORTED_MEDIA_TYPE: ErrorSpec(
        HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "Unsupported content type"
    ),
    ErrorCode.VALIDATION_FAILED: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Input contains characters that are not allowed"
    ),
    ErrorCode.QUERY_TOO_SHORT: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Type at least 3 characters"
    ),
    ErrorCode.SHARES_INVALID: ErrorSpec(HTTPStatus.UNPROCESSABLE_CONTENT, "Share 1 to 3 avatars"),
    ErrorCode.MENTION_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "You can only mention members of this circle"
    ),
    ErrorCode.RECIPIENTS_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Choose 1 to 10 circles and up to 20 people"
    ),
    ErrorCode.RECIPIENT_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "You can only share with your connections"
    ),
    ErrorCode.TOO_MANY_MENTIONS: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "A message can mention at most 20 people"
    ),
    ErrorCode.TOO_MANY_INVITEES: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "You can invite at most 49 people at once"
    ),
    ErrorCode.OTP_INVALID: ErrorSpec(HTTPStatus.UNPROCESSABLE_CONTENT, "The code is not correct"),
    ErrorCode.PASSWORD_REUSED: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Please choose a password you have not used recently"
    ),
    ErrorCode.PASSWORD_WEAK: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Password does not meet the requirements"
    ),
    ErrorCode.ACCOUNT_LOCKED: ErrorSpec(HTTPStatus.LOCKED, "Too many attempts. Try again later"),
    ErrorCode.RATE_LIMITED: ErrorSpec(HTTPStatus.TOO_MANY_REQUESTS, "Too many requests"),
    ErrorCode.INVITE_LINK_LIMIT: ErrorSpec(
        HTTPStatus.TOO_MANY_REQUESTS, "Too many invite links today. Try again tomorrow"
    ),
    ErrorCode.REPORT_NO_DATA: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Nothing was logged in this period yet"
    ),
    ErrorCode.REPORT_LIMIT_REACHED: ErrorSpec(
        HTTPStatus.TOO_MANY_REQUESTS, "You can create 10 reports a day. Try again tomorrow"
    ),
    ErrorCode.SUPPORT_LIMIT_REACHED: ErrorSpec(
        HTTPStatus.TOO_MANY_REQUESTS, "You have sent 5 requests today. Try again tomorrow"
    ),
    ErrorCode.REPORT_RANGE_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Choose dates up to today, at most 366 days apart"
    ),
    ErrorCode.UPLOAD_INVALID: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT, "Upload a PNG or JPG image up to 10 MB"
    ),
    ErrorCode.REPORT_NOT_READY: ErrorSpec(HTTPStatus.CONFLICT, "This report is not ready"),
    ErrorCode.EXPORT_LIMIT_REACHED: ErrorSpec(
        HTTPStatus.TOO_MANY_REQUESTS, "You can request one data export a day"
    ),
    ErrorCode.EXPORT_NOT_READY: ErrorSpec(HTTPStatus.CONFLICT, "This export is not ready"),
    ErrorCode.CONSENT_WITHDRAWAL_BLOCKED: ErrorSpec(
        HTTPStatus.UNPROCESSABLE_CONTENT,
        "This consent is needed to use NaraaCare. To stop it, delete your account",
    ),
    ErrorCode.INTERNAL_ERROR: ErrorSpec(HTTPStatus.INTERNAL_SERVER_ERROR, "Something went wrong"),
    ErrorCode.SERVICE_UNAVAILABLE: ErrorSpec(
        HTTPStatus.SERVICE_UNAVAILABLE, "Service temporarily unavailable"
    ),
}

# Database business errors: P0001 with the code in DETAIL (naraacare-database functions/README.md).
DB_DETAIL_CODES: dict[str, ErrorCode] = {
    "USERNAME_TAKEN": ErrorCode.USERNAME_TAKEN,
    "USERNAME_CHANGE_TOO_SOON": ErrorCode.USERNAME_CHANGE_TOO_SOON,
    "USERNAME_REQUIRED": ErrorCode.USERNAME_REQUIRED,
    "ONBOARDING_INCOMPLETE": ErrorCode.ONBOARDING_INCOMPLETE,
    "ONBOARDING_ALREADY_COMPLETED": ErrorCode.ONBOARDING_ALREADY_COMPLETED,
    "CONSENT_REQUIRED": ErrorCode.CONSENT_REQUIRED,
    "IDENTITY_ALREADY_LINKED": ErrorCode.IDENTITY_ALREADY_LINKED,
    "ACCOUNT_NOT_ACTIVE": ErrorCode.INVALID_CREDENTIALS,
    "DAILY_LIMIT_REACHED": ErrorCode.DAILY_LIMIT_REACHED,
    "EDIT_WINDOW_CLOSED": ErrorCode.EDIT_WINDOW_CLOSED,
    "VERSION_CONFLICT": ErrorCode.VERSION_CONFLICT,
    "UPGRADE_REQUIRED": ErrorCode.UPGRADE_REQUIRED,
    "SAVED_MEAL_LIMIT": ErrorCode.SAVED_MEAL_LIMIT,
    "CUSTOM_DRINK_LIMIT": ErrorCode.CUSTOM_DRINK_LIMIT,
    "WATER_BELOW_ZERO": ErrorCode.WATER_BELOW_ZERO,
    "SLEEP_OVERLAP": ErrorCode.SLEEP_OVERLAP,
    "ALREADY_EXISTS": ErrorCode.ALREADY_EXISTS,
    "ADMIN_REQUIRED": ErrorCode.ADMIN_REQUIRED,
    "CIRCLE_FULL": ErrorCode.CIRCLE_FULL,
    "LAST_ADMIN": ErrorCode.LAST_ADMIN,
    "INVITE_LINK_EXPIRED": ErrorCode.INVITE_LINK_EXPIRED,
    "INVITE_LINK_LIMIT": ErrorCode.INVITE_LINK_LIMIT,
    "ACTION_RESOLVED": ErrorCode.ACTION_RESOLVED,
    "ACTION_EXPIRED": ErrorCode.ACTION_EXPIRED,
    "REPORT_LIMIT_REACHED": ErrorCode.REPORT_LIMIT_REACHED,
    "REPORT_NO_DATA": ErrorCode.REPORT_NO_DATA,
    "SUPPORT_LIMIT_REACHED": ErrorCode.SUPPORT_LIMIT_REACHED,
    "EXPORT_LIMIT_REACHED": ErrorCode.EXPORT_LIMIT_REACHED,
}

# Input errors (22023) whose DETAIL the app shows as its own message; every other 22023 detail stays
# VALIDATION_FAILED. The detail is a fixed code from our routines, never user input.
DB_VALIDATION_DETAIL_CODES: dict[str, ErrorCode] = {
    "QUERY_TOO_SHORT": ErrorCode.QUERY_TOO_SHORT,
    "SHARES_INVALID": ErrorCode.SHARES_INVALID,
    "MENTION_INVALID": ErrorCode.MENTION_INVALID,
    "RECIPIENTS_INVALID": ErrorCode.RECIPIENTS_INVALID,
    "RECIPIENT_INVALID": ErrorCode.RECIPIENT_INVALID,
    "TOO_MANY_MENTIONS": ErrorCode.TOO_MANY_MENTIONS,
    "TOO_MANY_INVITEES": ErrorCode.TOO_MANY_INVITEES,
    "REPORT_RANGE_INVALID": ErrorCode.REPORT_RANGE_INVALID,
    "CONSENT_WITHDRAWAL_BLOCKED": ErrorCode.CONSENT_WITHDRAWAL_BLOCKED,
}
