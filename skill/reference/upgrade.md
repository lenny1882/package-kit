# Upgrading a package to the current kit

A package scaffolded by an older kit keeps that kit's `install.sh`,
`uninstall.sh` and the rest. `new-package.sh` refuses an existing directory, so
the only way those files used to move forward was by hand — which is how the
kit's own `install.sh` and the template's drifted apart until someone noticed.
`upgrade-package.sh` brings the kit-owned files up to date and leaves
everything else alone.

```bash
upgrade-package.sh <package-dir>          dry run: each file's status, and diffs
upgrade-package.sh <package-dir> --apply  write what is safe to write
upgrade-package.sh --root <monorepo>      the same for a monorepo root's own files
```

| Option | |
|---|---|
| `--apply` | write the files marked stale, new or merged |
| `--force <file>` | replace this file with the new render, discarding hand edits; repeatable |
| `--adopt <file>` | keep this hand-edited file as it is, and record the new render as what it came from, so later upgrades merge into it; for a package with no `.kit/` yet; repeatable |
| `--kind`, `--slug`, `--monorepo <root>` | override what was read from `.kit/settings` or inferred |
| `--allow-downgrade` | run although the package was made by a newer kit than this one |

It never commits, installs or runs the package's tests. Run
`./test/run-tests.sh` afterwards.

## Kit-owned and package-owned

| Kit-owned: replaced or merged | Package-owned: never touched |
|---|---|
| `install.sh`, `uninstall.sh` | `manifest.sh`, `README.md`, `VERSION`, `PAYLOAD` |
| `test/installer-tests.sh` | `test/run-tests.sh` |
| `update.sh`, `lib/update-check.sh` (with releases) | the code itself |
| `.github/workflows/release.yml`, `.claude/skills/release/SKILL.md`, `.gitignore` (standalone) | |
| monorepo root: `test/run-tests.sh`, `.gitignore`, the workflow and release skill | monorepo root: `README.md`, `packages/` |

`test/run-tests.sh` sources `test/installer-tests.sh`. The installer tests come
from the kit and are upgraded with it; the behaviour tests are the package's.

When the template's `manifest.sh` for the package's kind has changed since the
package was scaffolded, the old and new template are diffed and shown. Nothing
is written: `manifest.sh` is filled in by hand, and only a person can carry a
template change into it.

## `.kit/`

`new-package.sh` and `new-monorepo.sh` write it, and `upgrade-package.sh`
rewrites it after each `--apply`. It is committed, because the next upgrade
needs it, and left out of the release tarball, because installing never reads
it.

```
.kit/
  settings              key=value lines: kit, name, kind, slug, monorepo,
                        release, payload. Read with grep, never sourced.
  files/                each kit-owned file exactly as generated
    install.sh
    uninstall.sh
    test/installer-tests.sh
    update.sh
    lib/update-check.sh
    gitignore
    dot-github/workflows/release.yml
    dot-claude/skills/release/SKILL.md
  template/manifest.sh  the manifest template as it was, for the diff above
```

`.github/`, `.claude/` and `.gitignore` are stored as `dot-github/`,
`dot-claude/` and `gitignore`, the template's own naming. Claude Code loads
skills from nested `.claude/skills/` directories, so a literal `.claude/` under
`.kit/` would load the release skill a second time.

`kit` is the kit's version, read from `skill/VERSION`. The root `VERSION` is a
symlink to it, so the installed kit — which is a copy of `skill/` — carries its
version too.

## What happens to each file

The new render comes from running `new-package.sh` (or `new-monorepo.sh`) into
a temp directory with the package's settings. Each kit-owned file is then
compared with what is on disk and with its copy in `.kit/files/`:

| On disk | Status | With `--apply` |
|---|---|---|
| missing | new | written |
| same as the new render | up to date | nothing |
| same as `.kit/files/` | stale | replaced |
| differs from both, and the kit has not changed it | up to date (hand edits kept) | nothing |
| differs from both | merged, or conflict | `git merge-file` combines the hand edits with the kit's changes. A clean merge is written. A conflict is shown with its markers and left alone unless `--force` |
| differs, and there is no `.kit/` copy | hand-edited | diff shown; left alone unless `--force` or `--adopt` |

`.gitignore` with no `.kit/` copy is the exception: the kit's lines missing from
it are appended, since the order of the lines rarely matters and adding one
cannot undo a hand edit.

After `--apply`, `.kit/files/` holds the new render for every file that was
written, and keeps the old copy for every file left alone, so a later upgrade
can still merge it.

## Packages made before `.kit/` existed

The settings are read from the package itself, and printed:

- **name**: `PKG=` in `manifest.sh`.
- **kind**: `skill` if `manifest.sh` installs under `$CLAUDE_DIR/skills/`,
  `command` if it installs into `~/.local/bin/`, otherwise `hook`.
- **monorepo**: a `PAYLOAD` file, with the root two directories up.
- **release**: `update.sh` exists.
- **slug**: `GITHUB_SLUG=` in `update.sh`, else the root README's
  `versions.txt` URL, else `lenny1882/<name>`.
- **payload**: the workflow's `git archive` line or `PAYLOAD`, less the files
  every tarball carries.

With no record of what was generated, every file that differs is hand-edited.
The first upgrade of an old package is a read of each diff and, per file, a
`--force` to take the kit's version or an `--adopt` to keep the package's.
After it, `.kit/` exists and later upgrades merge.

An old package's `test/run-tests.sh` has the installer tests written inline.
The upgrade writes `test/installer-tests.sh` and says that `run-tests.sh` does
not source it yet; moving to it is an edit to a package-owned file, so it is
left to a person.

## An older kit

If the kit running the upgrade is older than `kit=` in `.kit/settings`, the
upgrade would write older files over newer ones. It refuses unless
`--allow-downgrade`.

## The kit itself

The kit is a skill package and carries its own `.kit/`. Its test suite runs
`upgrade-package.sh` against the kit's own checkout and fails if anything
other than "up to date" comes back, so the kit's installer cannot drift from
the template it ships.
