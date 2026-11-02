# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the hook variant: one script in ~/.claude/hooks, registered in
# settings.json. Edit the parts marked EDIT; the machinery around it does not
# need changing.

PKG="__PKG__"

# Every settings entry and installed file this package owns is found by this
# substring. It must appear in the command string of every entry you register,
# which it will if the script is named after the package.
OWNS="__PKG__"

# "<path in this repo>:<where it goes>". CLAUDE_DIR is ~/.claude unless
# overridden, which is how the tests run against a throwaway directory.
FILES=(
  "hooks/__PKG__.sh:$CLAUDE_DIR/hooks/__PKG__.sh"
)

# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the package's state (~/.claude/__PKG__/, unless --keep-state) and
# ~/.local/share/__PKG__. See reference/layout.md.
STATE_DIRS=()

# EDIT: the settings.json entries. Reads the current settings on stdin and
# writes the new ones on stdout. strip_ours has already removed this package's
# previous entries, so this only has to add.
#
# Every event name is valid here — PreToolUse, PostToolUse, SessionStart, Stop,
# PreCompact, and the rest. Matchers are per-event: a tool name for PreToolUse,
# startup/resume/clear for SessionStart, manual/auto for PreCompact,
# a command name for UserPromptExpansion.
#
# A slash command the user typed never becomes a Skill tool call, so a
# PreToolUse matcher on Skill sees only the ones Claude starts itself. Catching
# both means registering the same script on UserPromptExpansion as well, and
# leaving the matcher out so it fires on every command — a matcher that misses
# fails silently. Add this branch alongside the one below when that is what the
# hook is for:
#
#     | .hooks.UserPromptExpansion = ((.hooks.UserPromptExpansion // []) + [
#         { hooks: [{ type: "command", command: $cmd }] }
#       ])
#
# Its exit 2 goes to the user, not to Claude — see reference/hook-events.md.
settings_merge() {
  jq --arg cmd "~/.claude/hooks/$PKG.sh" '
    .hooks //= {}
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Bash",
          hooks: [{ type: "command", command: $cmd }] }
      ])
  '
}

# EDIT: one line per registration, printed by install.sh when it finishes.
REGISTRATIONS=(
  "PreToolUse (matcher: Bash)"
)

# EDIT, or delete. A live check that the thing actually works, run at the end
# of install.sh. Return 0 for pass. The reference packages feed their hook a
# payload it should refuse and confirm that it does — an installer that only
# checks the file exists will happily report success on a broken script.
verify_probe() {
  local out
  out=$(printf '{"tool_input":{"command":"true"}}' | "$CLAUDE_DIR/hooks/$PKG.sh" 2>/dev/null) || true
  [ -n "$out" ] || return 0   # a hook that stays silent on a normal call is fine
  printf '%s' "$out" | jq -e . >/dev/null 2>&1
}

# Optional, both. Changes outside $HOME around a real install. pre_install
# runs before any file is placed — stop services running from the package's
# directory, which a reinstall deletes and copies again; non-zero stops the
# install with nothing placed. post_install runs after the files and settings,
# before verify_probe; non-zero fails the install. Each gets $1: "install" the
# first time, "reinstall" when the package's files were already there. Neither
# runs on --dry-run or when KIT_SKIP_MACHINE_HOOKS=1 (the tests set it). Both
# must be safe to run again.
# pre_install() {
#   [ "$1" = reinstall ] && systemctl --user stop "$PKG.service" 2>/dev/null
#   return 0
# }
# post_install() {
#   loginctl enable-linger "$USER" && systemctl --user restart "$PKG.service"
# }

# Optional. Runs when install.sh stops after pre_install has run, with $1 the
# mode and $2 the reason, so services pre_install stopped are not left down.
# Skipped when KIT_SKIP_MACHINE_HOOKS=1.
# install_failed() {
#   systemctl --user start "$PKG.service" 2>/dev/null || true
# }

# Optional, both. Run by update.sh with $1 the installed version and $2 the
# new one, from the new release's manifest.sh. pre_update runs before the new
# files are unpacked; non-zero stops the update with nothing changed.
# post_update runs after install.sh succeeds; use it to migrate from an older
# version. Skipped with --dry-run and when KIT_SKIP_MACHINE_HOOKS=1.
# pre_update() {
#   systemctl --user stop "$PKG.service" 2>/dev/null || true
# }
# post_update() {
#   case "$1" in 1.*) mv "$CLAUDE_DIR/$PKG/old.conf" "$CLAUDE_DIR/$PKG/new.conf" 2>/dev/null ;; esac
#   return 0
# }

# Optional. Run by lib/update-check.sh check, in the background, once for each
# newly found release, with $1 the installed version, $2 the new one and $3 the
# release URL. It cannot show anything in a session; output goes to
# ~/.local/state/__PKG__/update_available.log. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1.
# update_available() {
#   notify-send "__PKG__ v$2 is available" "$3" 2>/dev/null || true
# }

# install.sh registers lib/update-check.sh on SessionStart, to show a waiting
# release and run the daily check. Set this to 0 to leave that out.
# UPDATE_NOTICE=0

# Optional. Runs in uninstall.sh before anything is removed, while the files
# are still installed: stop services started from the package's directory.
# Non-zero stops the uninstall with nothing removed. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1 (the tests set it).
# pre_uninstall() {
#   systemctl --user stop "$PKG.service" 2>/dev/null || true
# }

# Optional. Runs in uninstall.sh after everything is removed, to undo a change
# outside $HOME that needs none of the package's files. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1. Non-zero is reported; nothing is put back.
# post_uninstall() {
#   loginctl disable-linger "$USER"
# }
