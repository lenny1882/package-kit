#!/usr/bin/env bash
# Remove claude-package-kit from this machine.
#
#   ./uninstall.sh                 ask before editing settings.json
#   ./uninstall.sh --yes           no prompts
#   ./uninstall.sh --keep-settings leave settings.json alone

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_DIR="${CLAUDE_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
LIB_DIR="$HOME/.local/share/claude-package-kit"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/claude-package-kit"

ASSUME_YES=0; KEEP_SETTINGS=0
for a in "$@"; do
  case "$a" in
    --yes|-y)        ASSUME_YES=1 ;;
    --keep-settings) KEEP_SETTINGS=1 ;;
    -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
step() { printf '\n== %s\n' "$*"; }
confirm() {
  [ "$ASSUME_YES" -eq 1 ] && return 0
  local reply; read -r -p "$1 [Y/n] " reply </dev/tty || return 1
  case "$reply" in [Nn]*) return 1 ;; *) return 0 ;; esac
}

FILES=(); DIRS=(); STATE_DIRS=()
# shellcheck source=manifest.sh
. "$REPO/manifest.sh"

printf '%s\n' "== Uninstalling $PKG"

step "Removing files"
for entry in ${FILES[@]+"${FILES[@]}"} ${DIRS[@]+"${DIRS[@]}"}; do
  d="${entry#*:}"
  if [ -e "$d" ] || [ -L "$d" ]; then rm -rf "$d"; ok "removed $d"; else ok "no $d"; fi
done
for d in "$LIB_DIR" "$STATE" ${STATE_DIRS[@]+"${STATE_DIRS[@]}"}; do
  [ -d "$d" ] && { rm -rf "$d"; ok "removed $d"; }
done

step "settings.json"
if [ "$KEEP_SETTINGS" -eq 1 ]; then
  ok "left alone (--keep-settings)"
elif [ ! -f "$SETTINGS" ]; then
  ok "no $SETTINGS"
elif ! jq empty "$SETTINGS" 2>/dev/null; then
  warn "$SETTINGS is not valid JSON — leaving it untouched."
  warn "Remove the hook entries whose command contains '$OWNS' by hand."
elif confirm "  Remove this package's hook entries?"; then
  cp "$SETTINGS" "$SETTINGS.bak-uninstall"
  tmp=$(mktemp)
  jq --arg owns "$OWNS" '
    def ours: (.command // "") | contains($owns);
    def strip_ours: map(.hooks |= map(select(ours | not))) | map(select((.hooks | length) > 0));
    if (.hooks | type) == "object" then
      .hooks |= with_entries(if (.value | type) == "array" then .value |= strip_ours else . end)
      | .hooks |= with_entries(select((.value | type) != "array" or (.value | length) > 0))
      | (if (.hooks // null) == {} then del(.hooks) else . end)
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
  ok "cleaned; previous file saved as $SETTINGS.bak-uninstall"
else
  ok "left alone"
fi

printf '\n%s\n' "Done."
