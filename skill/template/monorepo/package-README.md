# __PKG__

<One sentence: what it does. Then a short paragraph on the problem it solves —
what goes wrong without it. Lead with the problem, not the mechanism.>

Part of [__REPO__](https://github.com/__SLUG__), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

<The observable behaviour, from the user's side. Not the implementation.>

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/__SLUG__/versions/versions.txt | awk '$1=="__PKG__" {print $2}')
    curl -fsSL "https://github.com/__SLUG__/releases/download/__PKG__-v$v/__PKG__.tar.gz" | tar -xz
    cd __PKG__ && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/__PKG__-vX.Y.Z/__PKG__.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/__SLUG__ && cd __REPO__/packages/__PKG__
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone

## How it works

<The mechanism, and anything undocumented it relies on. If it depends on
behaviour that could be withdrawn in a Claude Code update, say so here and say
what the symptom would look like.>

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release __PKG__` at the repo root — bump `packages/__PKG__/VERSION` on `main`,
move `release/__PKG__-vX.x` onto it, tag `__PKG__-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
