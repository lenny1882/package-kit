# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="claude-package-kit"
OWNS="claude-package-kit"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/claude-package-kit"
)
FILES=()
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/claude-package-kit (no settings entry needed)"
)

# The whole point of this skill is that new-package.sh runs and produces a
# working package, so the probe scaffolds one rather than checking that files
# are present. A copy that installed but lost its executable bit, or a template
# directory that did not come along, looks perfect to a file-existence check and
# fails the first time anyone asks for a package.
verify_probe() {
  local dir="$CLAUDE_DIR/skills/$PKG"
  local f="$dir/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -q '^name:' "$f" && grep -q '^description:' "$f" || return 1

  [ -x "$dir/bin/new-package.sh" ] || return 1
  local t; t=$(mktemp -d) || return 1
  local rc=0
  "$dir/bin/new-package.sh" --name probe-package --kind hook --dir "$t" >/dev/null 2>&1 || rc=1
  [ "$rc" -eq 0 ] && bash -n "$t/probe-package/install.sh" 2>/dev/null || rc=1
  [ "$rc" -eq 0 ] && [ -f "$t/probe-package/hooks/probe-package.sh" ] || rc=1
  [ "$rc" -eq 0 ] && ! grep -rq '__PKG__\|__SLUG__\|__PAYLOAD__' "$t/probe-package" || rc=1
  rm -rf "$t"
  return "$rc"
}
