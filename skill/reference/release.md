# Publishing and releasing

Every step here is outward-facing. Creating a repo, pushing a branch, and
publishing a release are each visible to anyone watching, and agreement to one
is not agreement to the next. Ask in the moment, each time.

## Turning a local package into a published one

1. Move the directory to `/mnt/sda/Development/github-lenny1882/<name>` — that
   is where the published ones live.
2. `git init`, and a first commit.
3. Ask before creating the GitHub repo, and ask whether it is public or private.
   `gh repo create` is the tool; the remote is `git@github.com:lenny1882/<name>.git`
   to match the others.
4. Check `update.sh` and `lib/update-check.sh` carry the right `GITHUB_SLUG` —
   the scaffolder fills in `lenny1882/<name>` by default. The repo does not have
   to be named after the package: `claude-package-kit` is published from a repo
   called `package-kit`. When they differ, pass `--slug`, and remember the two
   names are used for different things — `GITHUB_SLUG` is the repo, while
   `TARBALL_NAME`, the `--prefix` in the release workflow and the directory the
   README's install one-liner tells people to `cd` into are all the package.
5. Cut `v1.0.0` with the release process below.

## How a release works

`.github/workflows/release.yml` turns any pushed `vX.Y.Z` tag into a GitHub
Release with generated notes, and attaches an install-only tarball named
`<name>.tar.gz`. That fixed filename is what lets `update.sh` and the README's
one-liner find the newest release without knowing the version in advance:

    https://github.com/<slug>/releases/latest/download/<name>.tar.gz

The tarball deliberately excludes `.github/` and `.claude/` — GitHub's own
"Source code" links are the whole checkout, which is right for a developer and
wrong for someone who just wants to install the tool. The payload list is the
`git archive` line in the workflow; keep it current if the layout changes.
`manifest.sh` is on that line for a reason that is easy to miss — `install.sh`
sources it, so a tarball built without it stops on the first line that matters
with `No such file or directory`, while the git checkout it was tested from
installs perfectly.

A tag with a hyphen — `v1.2.0-rc1` — publishes as a pre-release, so
`/releases/latest` skips it and nobody on the stable update path is offered it.

## The branch rule

**A release tag is only ever created on its `release/vX.x` branch, after `main`
has been merged into it.**

GitHub fires the workflow on any `v*` tag push regardless of branch — a tag push
and a branch push are separate ref events, so the trigger cannot require it. The
guarantee is process, not CI. Each published package carries a `/release` skill
that is the only place tags should be created; follow it in order.

The `x` in `release/vX.x` is literal, and it is one branch per major line:
`1.2.0` and `1.2.1` both ship from `release/v1.x`.

In outline, and with the user's agreement at each push:

1. `main` clean, fetched, and genuinely worth releasing.
2. Bump `VERSION`, commit as `Bump version to X.Y.Z`, push `main`.
3. Move `release/vX.x` onto the new commit **without checking it out**:
   `git merge-base --is-ancestor release/vX.x main` to confirm a fast-forward,
   then `git fetch . main:release/vX.x` to move it. Check it actually moved,
   then push. A non-zero exit from the first command means the branch diverged
   some other way, so stop and ask.
4. `git tag -a vX.Y.Z release/vX.x -m "<name> vX.Y.Z"`, naming the branch, and
   verify with `git branch --contains vX.Y.Z`. Push the tag. This is the step
   that publishes.
5. Point the user at the Actions run and then the release.

Step 3 is written that way because checking the branch out and running
`git merge main` went wrong once: the merge said "Already up-to-date", the
branch never moved, and the tag ended up on `main` — the one thing the branch
rule exists to prevent. Run those commands one at a time and read the output of
each.

## Versioning

`VERSION` is the only source of truth — the installer reads it, `update.sh`
compares against it, and `lib/update-check.sh` records it. There is no changelog
to infer a bump from, so ask patch, minor or major when it is not obvious.
