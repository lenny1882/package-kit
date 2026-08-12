#!/usr/bin/env bash
# Tests for __PKG__.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. Add cases for the behaviour itself below the installer ones —
# the installer tests come free, the behaviour tests are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

echo "sanity"
for f in "$REPO"/*.sh "$REPO"/hooks/*.sh "$REPO"/lib/*.sh; do
  [ -f "$f" ] || continue
  bash -n "$f" && ok "$(basename "$f") parses" || no "$(basename "$f") parses" "syntax error"
done
[ -s "$REPO/VERSION" ] && ok "VERSION is set" || no "VERSION is set" "empty or missing"

echo "installer"
# A pre-existing hook from some other package, to prove we leave it alone.
printf '{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"someone-elses-thing"}]}]}}\n' \
  > "$CLAUDE_DIR/settings.json"

"$REPO/install.sh" --link --yes >"$TMP/out" 2>&1 \
  && ok "installs" || no "installs" "$(tail -5 "$TMP/out")"
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "leaves other packages' entries alone" || no "leaves other packages' entries alone" "removed them"

before=$(jq -S . "$CLAUDE_DIR/settings.json")
"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ "$before" = "$(jq -S . "$CLAUDE_DIR/settings.json")" ] \
  && ok "installing twice changes nothing" || no "installing twice changes nothing" "settings drifted"

"$REPO/install.sh" --dry-run >"$TMP/out" 2>&1
grep -q "dry run" "$TMP/out" && ok "--dry-run writes nothing" || no "--dry-run writes nothing" "$(tail -3 "$TMP/out")"

"$REPO/uninstall.sh" --yes >/dev/null 2>&1
grep -q "someone-elses-thing" "$CLAUDE_DIR/settings.json" \
  && ok "uninstall leaves other packages alone" || no "uninstall leaves other packages alone" "removed them"
jq -e --arg o "__PKG__" '[.. | .command? // empty] | any(contains($o))' \
  "$CLAUDE_DIR/settings.json" >/dev/null 2>&1 \
  && no "uninstall removes our entries" "still registered" || ok "uninstall removes our entries"

echo "behaviour"
# TODO: the tests that actually matter. Feed the thing its real input and check
# what it does — an installer test proves nothing about whether it works.
no "behaviour is tested" "no behaviour tests written yet — delete this line once there are"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
