# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="__PKG__"
OWNS="__PKG__"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/__PKG__"
)
FILES=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/__PKG__.
# See reference/layout.md.
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/__PKG__ (no settings entry needed)"
)

# EDIT, or delete. Confirm the installed skill is well formed — a SKILL.md with
# frontmatter Claude Code can actually read.
verify_probe() {
  local f="$CLAUDE_DIR/skills/$PKG/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -q '^name:' "$f" && grep -q '^description:' "$f"
}

# Optional. Runs once after a real install, before verify_probe, for a change
# outside $HOME — say, letting this package's systemd user services start at
# boot. Skipped on --dry-run and when KIT_SKIP_POST_INSTALL=1 (the tests set
# it). Must be safe to run again: every reinstall runs it. Non-zero fails the
# install.
# post_install() {
#   loginctl enable-linger "$USER"
# }

# Optional. Runs in uninstall.sh before anything is removed, while the files
# are still installed: stop services started from the package's directory.
# Non-zero stops the uninstall with nothing removed.
# pre_uninstall() {
#   systemctl --user stop "$PKG.service" 2>/dev/null || true
# }
