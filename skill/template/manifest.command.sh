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
STATE_DIRS=(
  "$HOME/.local/share/__PKG__"
)

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
