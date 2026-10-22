#!/usr/bin/env bash
# Tests for __PKG__.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. The installer tests come free, from installer-tests.sh, which
# claude-package-kit keeps up to date. This file is the package's own: add the
# behaviour tests below — they are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

echo "behaviour"
# TODO: the tests that actually matter. Feed the thing its real input and check
# what it does — an installer test proves nothing about whether it works.
no "behaviour is tested" "no behaviour tests written yet — delete this line once there are"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
