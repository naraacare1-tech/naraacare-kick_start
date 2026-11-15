"""Structured JSON logging with PII redaction (doc 03 §7, doc 07 SEC-7.4).

Processors, in order:
1. merge the request context (request_id, user_id) bound by the middleware;
2. ``redact``: drop every key whose name matches the SEC-7.4 pattern (password, token, otp, email,
   name, weight, height, kcal, ml, body, content, description, code), at any nesting depth;
3. ``truncate``: cap long strings so nothing large or unexpected is ever written;
4. ``safe_exception``: tracebacks keep file/line/function frames and the exception TYPE only. The
   exception message is dropped because driver and library messages can quote input values.
Request/response bodies are never logged (Semgrep rule no-logging-request-body).
"""

from __future__ import annotations

import logging
import sys
import traceback
from collections.abc import MutableMapping
from typing import Any

import regex
import structlog

REDACT_KEYS = regex.compile(
    r"(?i)password|token|otp|email|name|weight|height|kcal|ml|body|content|description|code|"
    r"secret|authorization|cookie"
)
# Keys we write ourselves that would otherwise trip the pattern ("error_code" is a catalogue code).
SAFE_KEYS = frozenset({"event", "error_code", "status_code", "exc_type"})
MAX_STRING = 500


def _scrub(value: Any, depth: int = 0) -> Any:
    if depth > 5:  # noqa: PLR2004 - nesting cap
        return "[depth]"
    if isinstance(value, dict):
        return {
            k: _scrub(v, depth + 1)
            for k, v in value.items()
            if k in SAFE_KEYS or not REDACT_KEYS.search(str(k))
        }
    if isinstance(value, list | tuple):
        return [_scrub(v, depth + 1) for v in value[:50]]
    if isinstance(value, str) and len(value) > MAX_STRING:
        return value[:MAX_STRING] + "...[truncated]"
    return value


def redact(_: Any, __: str, event_dict: MutableMapping[str, Any]) -> MutableMapping[str, Any]:
    scrubbed = _scrub(dict(event_dict))
    event_dict.clear()
    event_dict.update(scrubbed)
    return event_dict


def safe_exception(
    _: Any, __: str, event_dict: MutableMapping[str, Any]
) -> MutableMapping[str, Any]:
    exc_info = event_dict.pop("exc_info", None)
    if not exc_info:
        return event_dict
    exc = exc_info if isinstance(exc_info, BaseException) else sys.exc_info()[1]
    if exc is None:
        return event_dict
    frames = traceback.extract_tb(exc.__traceback__)
    event_dict["exception"] = {
        "type": f"{type(exc).__module__}.{type(exc).__qualname__}",
        "frames": [f"{f.filename}:{f.lineno} in {f.name}" for f in frames[-15:]],
    }
    return event_dict


class _StdoutLogger:
    """Writes each line to the CURRENT sys.stdout (looked up per call, not captured at start-up),
    so redirected or replaced streams (tests, process managers) are always honoured."""

    def msg(self, message: str) -> None:
        # The one allowed print: this IS the log sink, reached only after the redaction processors.
        print(message, file=sys.stdout, flush=True)  # noqa: T201  # nosemgrep: no-print

    debug = info = warning = warn = error = critical = exception = fatal = msg


def _logger_factory(*_: Any) -> _StdoutLogger:
    return _StdoutLogger()


# Third-party loggers that print full URLs (query strings, ids, tokens) at INFO/DEBUG: outbound
# calls to Google, Apple, Anthropic, Open Food Facts and storage would otherwise leak them
# (SEC-7.4).
QUIET_LOGGERS = ("httpx", "httpx2", "httpcore", "urllib3", "uvicorn.access")


def configure_logging(level: str) -> None:
    logging.basicConfig(format="%(message)s", stream=sys.stdout, level=level, force=True)
    for name in QUIET_LOGGERS:
        logging.getLogger(name).setLevel(logging.WARNING)
    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            safe_exception,
            redact,
            structlog.processors.JSONRenderer(),
        ],
        wrapper_class=structlog.make_filtering_bound_logger(logging.getLevelNamesMapping()[level]),
        logger_factory=_logger_factory,
        cache_logger_on_first_use=True,
    )
