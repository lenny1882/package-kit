# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the command variant: an executable on PATH, optionally with data
# files and hook registrations that call it.

PKG="__PKG__"
OWNS="__PKG__"

FILES=(
  "bin/__PKG__:$HOME/.local/bin/__PKG__"
)
DIRS=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/__PKG__/, unless --keep-state) and
# ~/.local/share/__PKG__. See reference/layout.md.
STATE_DIRS=()

# EDIT, or delete if nothing calls this from a hook. claude-notify registers
# Notification and Stop hooks that shell out to the installed command.
settings_merge() {
  jq --arg cmd "~/.local/bin/$PKG" '
    .hooks //= {}
    | .hooks.Notification = ((.hooks.Notification // []) + [
        { hooks: [{ type: "command", command: ($cmd + " play notification"), async: true }] }
      ])
  '
}

REGISTRATIONS=(
  "Notification"
)

verify_probe() {
  [ -x "$HOME/.local/bin/$PKG" ] || return 1
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) return 0 ;;
    *) printf '  warn  %s is not on PATH\n' "$HOME/.local/bin"; return 0 ;;
  esac
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
