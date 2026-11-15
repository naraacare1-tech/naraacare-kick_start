#!/usr/bin/env bash
# Installs pgTAP 1.3.4 into the local/CI PostgreSQL (never into staging/prod).
# pgTAP is a pure-SQL extension: the release's pgtap.sql.in is processed the way its Makefile does
# for PostgreSQL 18 and copied, with the control file, into the server's extension directory.
# Usage: tools/install_pgtap.sh   (needs curl, unzip, pg_config; uses sudo if that directory
#                                  is not writable)
set -euo pipefail

VERSION=1.3.4
SHA256=2570574a9321082e82433768feb5bffe472ef2ced6b22608a86bfd25f2b88e40
DEST="$(pg_config --sharedir | tr -d '\r')/extension"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -sSfL -o "$WORK/pgtap.zip" "https://api.pgxn.org/dist/pgtap/${VERSION}/pgtap-${VERSION}.zip"
echo "${SHA256}  $WORK/pgtap.zip" | sha256sum -c -
unzip -q "$WORK/pgtap.zip" -d "$WORK"
SRC="$WORK/pgtap-${VERSION}"
case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) OS=windows ;; *) OS=linux ;; esac
sed -e 's,MODULE_PATHNAME,pgtap,g' -e "s,__OS__,${OS},g" -e 's,__VERSION__,1.3,g' \
  "$SRC/sql/pgtap.sql.in" > "$WORK/pgtap--${VERSION}.sql"

SUDO=""
[[ -w "$DEST" ]] || SUDO="sudo"
$SUDO cp "$WORK/pgtap--${VERSION}.sql" "$SRC/pgtap.control" "$DEST/"
echo "pgTAP ${VERSION} installed in ${DEST}"
