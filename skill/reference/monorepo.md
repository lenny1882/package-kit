# Several packages in one repo

A monorepo here is a repo holding several packages that are each versioned,
released and installed on their own. It is not a way of shipping several things
as one: every package keeps its own `VERSION`, its own tags, its own tarball and
its own installer, and installs with nothing else from the repo present.

## When it is the right answer

When the things fail independently and are installed independently. A hooks
repo holding `handoff-gate`, `inventory-guard` and `claude-branch-guard` is the
case it was built for: a bug in one hook says nothing about another, so each
should be fixable and shippable without re-releasing the rest, and someone who
wants one should not have to install four.

When it is not:

- **One thing.** A single package gets a repo to itself — `new-package.sh`
  without `--monorepo`. Nothing in this document applies to it.
- **Things that must move together.** If two scripts are only correct at the
  same version, they are one package with two scripts, not two packages. One
  `manifest.sh` can install several hooks; the installer matches each script's
  name as well as the package's, so all of them are found on reinstall and
  uninstall.

## Scaffolding

```bash
new-monorepo.sh --name <repo> [--dir <where>] [--slug <owner/repo>] [--no-release]
new-package.sh  --name <package> --kind hook|skill|command --monorepo <repo-root>
```

The first creates the root and no packages. The second adds one package, and
is run once per package. `--slug` on the root is only needed when the GitHub
repo is not `lenny1882/<repo>`; each package reads it from the root README.

## Layout

```
<repo>/
  README.md                        what the collection is for, a table of packages
  test/run-tests.sh                runs every package's suite, fails if any does
  .gitignore
  .github/workflows/release.yml    <package>-vX.Y.Z tag -> that package's release
  .claude/skills/release/SKILL.md  /release <package>
  packages/
    <package>/
      README.md  VERSION  PAYLOAD
      manifest.sh  install.sh  uninstall.sh  update.sh
      lib/update-check.sh
      hooks/ | skill/ | bin/
      test/run-tests.sh
```

Everything a standalone package has, less `.github/`, `.claude/` and
`.gitignore`, which the root owns. There is no root installer: each package's
tarball installs on its own, and a package is always installed from its
release, never from a checkout.

`PAYLOAD` is the one-line list of what the package's tarball carries — the same
list a standalone package's workflow spells out on its `git archive` line. It
lives with the package because one workflow serves every package and the list
differs by kind. Anything else in the package directory — a backlog, a handoff,
a repro project — stays out of the tarball.

## Tags, branches and versions

| | Standalone | Monorepo |
| --- | --- | --- |
| Tag | `vX.Y.Z` | `<package>-vX.Y.Z` |
| Release branch | `release/vX.x` | `release/<package>-vX.x` |
| Pre-release | a hyphen in the tag | a hyphen after `vX.Y.Z` |
| Newest version | `/releases/latest` | the package's line in `versions.txt` |
| Tarball | `<name>.tar.gz` | `<package>.tar.gz` |

**Why not `/releases/latest`.** It returns the newest release in the repo,
whichever package that belongs to. `update.sh` would offer one package's
version to someone running another, and the download URL
`.../releases/latest/download/<package>.tar.gz` would point at whichever
package released last.

**`versions.txt`.** The release workflow keeps one `<package> <version>` line
per package in `versions.txt` on a `versions` branch that nothing else writes
to. It writes a package's line only after that release's tarball is uploaded,
never for a pre-release, and never to lower a version already listed, so the
file only ever names something that can be downloaded. Installs read it through
`raw.githubusercontent.com`, which is not the GitHub API and so is not held to
its 60-an-hour limit; the scaffolded `update.sh` and `lib/update-check.sh` read
it too. The scaffolder writes only that lookup into a monorepo package's
scripts, and only `/releases/latest` into a standalone one's.

GitHub caches the raw file for about five minutes, so for that long after a
release an install can still get the previous version. That tarball still
exists, so it installs.

**Pre-releases.** Every monorepo tag has hyphens in it — before the `v`, and
often in the package name — so the standalone rule would make every release a
pre-release. Only a hyphen after the version counts:
`handoff-gate-v1.2.0-rc1` is a pre-release, `handoff-gate-v1.2.0` is not.

## Releasing

`/release <package>` at the repo root. It is the standalone process with the
names changed — see `reference/release.md` for the branch rule and why it is
enforced by process rather than by CI.
