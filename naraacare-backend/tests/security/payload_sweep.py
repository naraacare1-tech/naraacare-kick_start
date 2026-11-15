"""Payload sweep framework (doc 07 §4.7): every route x every string field x every payload -> 422.

Routes and fields are discovered from the app's OpenAPI document, so endpoints added in later
sessions are covered automatically. For each operation a VALID baseline request is built from the
schema (strings get a sample for their ``x-safe-kind``), then one field at a time is replaced by
each payload. Expected outcome: 422 VALIDATION_FAILED (path parameters may also give 404 when the
payload contains ``/``: the request never reaches a handler, which is equally safe).

Fields without ``x-safe-kind`` are bare strings: ``unvalidated_string_fields`` reports them.
Authenticated routes get a valid access token through ``headers_for`` (tests build it with the
app's own token service), so requests reach validation instead of stopping at 401.
"""

from __future__ import annotations

import copy
import uuid
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field
from typing import Any
from urllib.parse import quote

from fastapi.testclient import TestClient

SAMPLES: dict[str, str] = {
    "name": "Priya Sharma",
    "username": "priya.s",
    "email": "priya@example.com",
    "password": "Correct1Horse",
    "new_password": "Correct1Horse",
    "otp": "123456",
    "short_text": "Moong dal",
    "text": "Feeling good",
    "chat": "Great job",
    "search": "dal",
    "opaque_token": "abc.DEF-123",
    "referral_code": "PRIYA26",
    "barcode": "8901058000290",
    "timezone": "Asia/Kolkata",
    "locale": "en-IN",
    "file_name": "photo.png",
    "app_version": "1.0.0",
    "device_token": "fcm:APA91bHPRgkF3J",
    "code": "diabetes",
}
METHODS = ("get", "post", "put", "patch", "delete")


@dataclass(frozen=True)
class Target:
    method: str
    path: str
    location: str  # body | query | path | header
    name: str  # parameter name, or the JSON path inside the body ("items.0.note")
    pointer: tuple[str | int, ...] = ()


@dataclass
class Operation:
    method: str
    path: str
    query: dict[str, Any] = field(default_factory=dict)
    path_params: dict[str, Any] = field(default_factory=dict)
    headers: dict[str, str] = field(default_factory=dict)
    body: Any = None
    targets: list[Target] = field(default_factory=list)
    secured: bool = False  # the operation needs a Bearer token (OpenAPI ``security``)


class _Resolver:
    def __init__(self, spec: dict[str, Any]) -> None:
        self.spec = spec

    def resolve(self, schema: dict[str, Any]) -> dict[str, Any]:
        while "$ref" in schema:
            node: Any = self.spec
            for part in schema["$ref"].lstrip("#/").split("/"):
                node = node[part]
            schema = node
        for key in ("anyOf", "oneOf"):
            if key in schema:  # Optional[X]: use the non-null branch
                branches = [b for b in schema[key] if self.resolve(b).get("type") != "null"]
                return self.resolve(branches[0])
        if "allOf" in schema and len(schema["allOf"]) == 1:
            return self.resolve(schema["allOf"][0])
        return schema

    def sample(self, schema: dict[str, Any]) -> Any:  # noqa: PLR0911 - one branch per JSON type
        schema = self.resolve(schema)
        if "enum" in schema:
            return schema["enum"][0]
        if "const" in schema:
            return schema["const"]
        kind = schema.get("type")
        if kind == "object":
            props = schema.get("properties", {})
            return {name: self.sample(sub) for name, sub in props.items()}
        if kind == "array":
            return [self.sample(schema.get("items", {}))] * max(1, schema.get("minItems", 1))
        if kind == "integer":
            return int(schema.get("minimum", schema.get("exclusiveMinimum", 0) + 1))
        if kind == "number":
            return float(schema.get("minimum", 1))
        if kind == "boolean":
            return True
        if kind == "string":
            fmt = schema.get("format")
            if fmt == "uuid":
                return str(uuid.uuid4())
            if fmt == "date":
                return "2026-10-28"
            if fmt == "date-time":
                return "2026-10-28T08:00:00Z"
            return SAMPLES.get(schema.get("x-safe-kind", ""), "x")
        return None

    def string_leaves(
        self, schema: dict[str, Any], pointer: tuple[str | int, ...] = ()
    ) -> Iterator[tuple[tuple[str | int, ...], dict[str, Any]]]:
        schema = self.resolve(schema)
        kind = schema.get("type")
        if kind == "string" and "format" not in schema and "enum" not in schema:
            yield pointer, schema
        elif kind == "object":
            for name, sub in schema.get("properties", {}).items():
                yield from self.string_leaves(sub, (*pointer, name))
        elif kind == "array":
            yield from self.string_leaves(schema.get("items", {}), (*pointer, 0))


def discover(spec: dict[str, Any]) -> list[Operation]:
    resolver = _Resolver(spec)
    operations: list[Operation] = []
    for path, item in spec.get("paths", {}).items():
        for method in METHODS:
            if method not in item:
                continue
            op_spec = item[method]
            op = Operation(method=method, path=path, secured=bool(op_spec.get("security")))
            for param in op_spec.get("parameters", []):
                schema = resolver.resolve(param.get("schema", {}))
                value = resolver.sample(schema)
                location, name = param["in"], param["name"]
                {"query": op.query, "path": op.path_params, "header": op.headers}.get(location, {})[
                    name
                ] = value if location != "header" else str(value)
                if (
                    schema.get("type") == "string"
                    and "format" not in schema
                    and "enum" not in schema
                ):
                    op.targets.append(Target(method, path, location, name))
            body_schema = (
                op_spec.get("requestBody", {})
                .get("content", {})
                .get("application/json", {})
                .get("schema")
            )
            if body_schema is not None:
                op.body = resolver.sample(body_schema)
                for pointer, _ in resolver.string_leaves(body_schema):
                    name = ".".join(str(p) for p in pointer) or "body"
                    op.targets.append(Target(method, path, "body", name, pointer))
            operations.append(op)
    return operations


def unvalidated_string_fields(spec: dict[str, Any]) -> list[str]:
    """Every string parameter/body field without x-safe-kind (i.e. a bare str)."""
    resolver = _Resolver(spec)
    found: list[str] = []
    for op in discover(spec):
        op_spec = spec["paths"][op.path][op.method]
        for target in op.targets:
            if target.location == "body":
                body_schema = op_spec["requestBody"]["content"]["application/json"]["schema"]
                schema = dict(resolver.string_leaves(body_schema))[target.pointer]
            else:
                param = next(p for p in op_spec["parameters"] if p["name"] == target.name)
                schema = resolver.resolve(param["schema"])
            if "x-safe-kind" not in schema:
                found.append(f"{op.method.upper()} {op.path} {target.location}:{target.name}")
    return found


def _set(body: Any, pointer: tuple[str | int, ...], value: Any) -> Any:
    if not pointer:
        return value
    node = body
    for part in pointer[:-1]:
        node = node[part]
    node[pointer[-1]] = value
    return body


def _sendable_header(value: str) -> bool:
    return value.isprintable() and value.isascii() and value == value.strip()


@dataclass
class SweepResult:
    requests: int = 0
    failures: list[str] = field(default_factory=list)


def sweep(
    client: TestClient,
    operations: list[Operation],
    payloads: list[str],
    *,
    headers_for: Callable[[Operation], dict[str, str]] = lambda _: {},
) -> SweepResult:
    result = SweepResult()
    for op in operations:
        for target in op.targets:
            for payload in payloads:
                query, path_params = dict(op.query), dict(op.path_params)
                headers = {**op.headers, **headers_for(op)}
                body = copy.deepcopy(op.body)
                if target.location == "query":
                    query[target.name] = payload
                elif target.location == "path":
                    path_params[target.name] = payload
                elif target.location == "header":
                    if not _sendable_header(payload):
                        continue  # the HTTP client itself refuses it; it can never arrive
                    headers[target.name] = payload
                else:
                    body = _set(body, target.pointer, payload)
                url = op.path.format(**{k: quote(str(v), safe="") for k, v in path_params.items()})
                response = client.request(
                    op.method.upper(),
                    url,
                    params=query,
                    headers=headers,
                    json=body if op.body is not None else None,
                )
                result.requests += 1
                allowed = {422, 404} if target.location == "path" else {422}
                ok = response.status_code in allowed
                if ok and response.status_code == 422:
                    ok = response.json()["error"]["code"] == "VALIDATION_FAILED"
                if not ok or (len(payload) >= 6 and payload in response.text):
                    result.failures.append(
                        f"{op.method.upper()} {op.path} {target.location}:{target.name} "
                        f"-> {response.status_code} for payload {payload[:40]!r}"
                    )
    return result
