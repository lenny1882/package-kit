# The house layout

Taken from `claude-branch-guard`, `claude-notify` and `session-colour`, which
are the three that have been through a release cycle and are the reference for
everything else.

```
<name>/
  README.md                        problem first, then mechanism
  VERSION                          bare X.Y.Z, one line
  manifest.sh                      what gets installed and registered
  install.sh                       --link --yes --dry-run
  uninstall.sh                     --yes --keep-settings --keep-state
  update.sh                        newest GitHub Release, no git needed
  lib/update-check.sh              the once-a-day update notice
  hooks/ | skill/ | bin/           the thing itself
  test/run-tests.sh                behaviour first, installer second
  test/installer-tests.sh          the installer tests, sourced; the kit's
  .kit/                            what the kit generated; reference/upgrade.md
  .github/workflows/release.yml    tag -> GitHub Release
  .claude/skills/release/SKILL.md  how to cut one
```

`update.sh` and `lib/update-check.sh` are the same in every package bar the
name and the release lookup — they are copied by the scaffolder, not rewritten.
The lookup is inserted from `template/lookup/`: `/releases/latest` for a package
with a repo to itself, `versions.txt` for one in a monorepo. `manifest.sh` is
where a package differs.

A package in a monorepo has the same layout under `<repo>/packages/<name>/`,
less `.github/`, `.claude/` and `.gitignore`, which the root owns, and plus
`PAYLOAD`, the list of what its tarball carries. See `reference/monorepo.md`.

## What every installer must do

These are not stylistic. Each one exists because of something that went wrong.

- **Honour `CLAUDE_DIR`**, defaulting to `~/.claude`, so the tests can run
  against a throwaway directory instead of the real config.
- **Merge into `settings.json`, never replace it**, and back it up first. The
  merge strips only this package's own entries — found by its name, or the
  name of any script it installs, in the command — and leaves every other
  package's alone. There is a test for this in the generated suite; keep it.
- **Be safe to run twice.** Re-running is how a package upgrades. Installing
  twice must leave `settings.json` byte-identical, which means removing your own
  entries before adding them rather than appending.
- **Write nothing when nothing changed.** Compare before writing so a no-op
  install does not churn the file or its backup.
- **Verify at the end, with a live probe.** Check the registration landed *and*
  that the thing does what it should. `claude-branch-guard` feeds its hook a
  payload it must refuse and confirms it does.
- **Say what to do next.** `/hooks` forces a settings reload in a running
  session; a newly added hook needs a restart.

## Where a package keeps its state

Config, per-item files, logs — anything the package writes while it runs.

- **A skill** keeps it in `state/` inside its installed directory:
  `~/.claude/skills/<name>/state/`.
- **A hook or command package** has no installed directory of its own, so it
  uses `~/.claude/<name>/`. `handoff-gate` and `inventory-guard` do this.

The reason is `place()` in `install.sh`. It runs `rm -rf` on the destination and
copies or links it again, so anything else inside a skill's directory is gone
after every install and every upgrade. `place()` sets `state/` aside before that
and puts it back after, in copy and `--link` mode alike. With `--link` the
installed directory is a symlink to `skill/` in the checkout, so `state/` lives
in the checkout; `.gitignore` ignores `**/skill/state/` so it never lands in git.

`uninstall.sh` removes both kinds of state unless given `--keep-state`. With it,
a skill's `state/` is put back at `~/.claude/skills/<name>/state/`, where the
next install finds it, and `~/.claude/<name>/` is left alone. A `--link`
install's `state/` is in the checkout, and `uninstall.sh` never deletes from a
checkout.

Since `uninstall.sh` removes `~/.claude/<name>/`, a package must not be named
after a directory already there — `skills`, `hooks`, `projects` and the rest.
`new-package.sh` refuses those names and `uninstall.sh` will not delete them;
the two scripts carry the same list.

`~/.local/share/<name>/` is not state. It holds the installed copy of
`update-check.sh`, which `install.sh` replaces every time.

`STATE_DIRS` in `manifest.sh` is not for state either, despite the name. It
lists other directories `uninstall.sh` removes, unconditionally — so state put
there would ignore `--keep-state`. `uninstall.sh` already removes the package's
state and `~/.local/share/<name>/` without being told, and the templates leave
`STATE_DIRS` empty. Older packages list
`~/.local/share/<name>` in it, which is harmless: it is removed once either
way.

## Registering a hook

Two mistakes cost a working guard, both of them silent.

**A typed slash command is not a `Skill` tool call.** When Claude reaches for a
skill, `PreToolUse` sees it with matcher `Skill`. When the user types
`/gsd:plan-phase`, it goes to `UserPromptExpansion` instead and a `PreToolUse`
hook never runs. A guard on planning commands registered only on `PreToolUse`
lets every typed one through. Register on both, and read the name from
`.tool_input.skill` *or* `.command_name` — the field differs by event, so a
script ported across without that change finds nothing and waves everything
past while looking installed.

**Guarding a tool is not guarding the job.** A hook that holds `Read` at the
prompt does not stop the file being read; Claude will reach for `cat` through
`Bash` instead and carry on. Work out every tool that reaches the thing you care
about, or accept the guard is advisory.

See `reference/hook-events.md` for the payloads and what each event does with
exit 2.

## Naming

Kebab-case, and never containing `gsd-`. GSD's session-start migration deletes
any hook whose command contains that substring — a registration once vanished
between sessions with no error and took a while to find. The scaffolder refuses
such a name.

The package name doubles as the substring the installer uses to find its own
settings entries, so name the installed script after the package.

### Renaming is an accepted risk

The installer finds a package's own entries by the names it installs *now*: the
package name and each script's basename. Rename either and a reinstall no
longer recognises the entries registered under the old name. They stay in
`settings.json` beside the new ones, pointing at a script that no longer exists,
and the new version's `uninstall.sh` cannot remove them either.

This is accepted rather than handled. Renames are rare, and the handling on
offer — a list of former names in `manifest.sh`, or a record of registered
commands in the state directory — is machinery for a case a person can deal
with directly. **Whoever ships a rename must say so in the release, and whoever
installs it must run the old version's `uninstall.sh` first, then install the
new version from scratch.** Only the old version's uninstaller knows the old
names. `update.sh` does not do this for them: it extracts the new version over
the old, so the old `uninstall.sh` is gone before anything runs.

A possible guard, not built: `update.sh` could compare the package name and
the script names in the downloaded `manifest.sh` against the installed one, and
refuse to continue on a mismatch, telling the user to uninstall and install
from scratch.

`maestro-drive` handles its own rename from `maestro-remote-mac` with a
`LEGACY_OWNS` list in its manifest. That is the package's choice, not the kit's.

## Tests

`test/run-tests.sh`, no framework, plain bash, `ok`/`no` counters and a
`N passed, M failed` line. It must redirect `HOME` and `CLAUDE_DIR` into a temp
directory and clean up after itself.

Test the behaviour by feeding the thing the JSON Claude Code would actually send
and checking the decision it returns. Two traps found the hard way:

- `jq -e` on an **empty file** exits 0, so "no output" reads as a match. Check
  `[ -s "$file" ]` first.
- Comparing `settings.json` before and after with `diff` shows reordering as
  though it were a change. Compare sorted sets of matcher/command pairs instead.
