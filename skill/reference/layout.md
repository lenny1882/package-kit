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
  uninstall.sh                     --yes --keep-settings
  update.sh                        newest GitHub Release, no git needed
  lib/update-check.sh              the once-a-day update notice
  hooks/ | skill/ | bin/           the thing itself
  test/run-tests.sh                behaviour first, installer second
  .github/workflows/release.yml    tag -> GitHub Release
  .claude/skills/release/SKILL.md  how to cut one
```

`update.sh` and `lib/update-check.sh` are the same in every package bar the
name — they are copied by the scaffolder, not rewritten. `manifest.sh` is where
a package differs.

## What every installer must do

These are not stylistic. Each one exists because of something that went wrong.

- **Honour `CLAUDE_DIR`**, defaulting to `~/.claude`, so the tests can run
  against a throwaway directory instead of the real config.
- **Merge into `settings.json`, never replace it**, and back it up first. The
  merge strips only this package's own entries — found by a substring of its
  name in the command — and leaves every other package's alone. There is a test
  for this in the generated suite; keep it.
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

## Naming

Kebab-case, and never containing `gsd-`. GSD's session-start migration deletes
any hook whose command contains that substring — a registration once vanished
between sessions with no error and took a while to find. The scaffolder refuses
such a name.

The package name doubles as the substring the installer uses to find its own
settings entries, so name the installed script after the package.

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
