# Shared by new-package.sh, new-monorepo.sh and upgrade-package.sh: reading and
# writing a package's .kit/ record. Sourced, not run. KIT must be set to the
# kit's skill directory. See reference/upgrade.md.

kit_version() { head -1 "$KIT/VERSION" | tr -d '[:space:]'; }

# A package path and its name under .kit/files/. .github/, .claude/ and
# .gitignore are stored as dot-github/, dot-claude/ and gitignore: Claude Code
# loads skills from nested .claude/skills/ directories, so a literal .claude/
# under .kit/ would load the release skill a second time.
kit_key() {
  case "$1" in
    .github/*) printf 'dot-github/%s\n' "${1#.github/}" ;;
    .claude/*) printf 'dot-claude/%s\n' "${1#.claude/}" ;;
    .gitignore) printf 'gitignore\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}
kit_path() {
  case "$1" in
    dot-github/*) printf '.github/%s\n' "${1#dot-github/}" ;;
    dot-claude/*) printf '.claude/%s\n' "${1#dot-claude/}" ;;
    gitignore) printf '.gitignore\n' ;;
    *) printf '%s\n' "$1" ;;
  esac
}

# kit_settings <dir> key=value... — writes <dir>/.kit/settings.
kit_settings() {
  local dir="$1"; shift
  mkdir -p "$dir/.kit"
  printf '%s\n' "$@" > "$dir/.kit/settings"
}

# kit_get <dir> <key> — one value from <dir>/.kit/settings. Read with grep, so
# opening a package's record never runs anything in it.
kit_get() {
  { grep -m1 "^$2=" "$1/.kit/settings" 2>/dev/null || true; } | cut -d= -f2-
}

# kit_record <dir> <path>... — copies each kit-owned file, as it now stands in
# <dir>, into <dir>/.kit/files/.
kit_record() {
  local dir="$1" p k; shift
  for p in "$@"; do
    k=$(kit_key "$p")
    mkdir -p "$(dirname "$dir/.kit/files/$k")"
    cp "$dir/$p" "$dir/.kit/files/$k"
  done
}

# True when $2 is a strictly higher version than $1.
kit_newer_than() {
  [ -n "$2" ] || return 1
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1)" = "$2" ]
}
