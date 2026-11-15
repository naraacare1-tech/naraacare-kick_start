#!/usr/bin/env bash
# Fails if the shared XSS/script payload list is not the version this repo expects.
# The canonical list lives in naraacare-backend (tests/security/payloads/xss.txt); copies must match.
set -euo pipefail
cd "$(dirname "$0")/.."

EXPECTED="1.0.0"
FILE="tests/payloads/xss.txt"
ACTUAL="$(sed -n 's/^# payload-list-version: //p' "$FILE" | head -1)"

if [[ "$ACTUAL" != "$EXPECTED" ]]; then
  echo "Payload list version mismatch: expected ${EXPECTED}, found '${ACTUAL}' in ${FILE}" >&2
  exit 1
fi
echo "Payload list version ${ACTUAL} OK ($(grep -cv '^#' "$FILE") payloads)"
