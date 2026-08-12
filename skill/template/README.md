# __PKG__

<One sentence: what it does. Then a short paragraph on the problem it solves —
what goes wrong without it. Lead with the problem, not the mechanism.>

## What you actually see

<The observable behaviour, from the user's side. Not the implementation.>

## Install

Needs `jq`.

    git clone https://github.com/__SLUG__ && cd __PKG__
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Or without cloning, from the newest release:

    curl -fsSL https://github.com/__SLUG__/releases/latest/download/__PKG__.tar.gz | tar -xz
    cd __PKG__ && ./install.sh

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads the newest GitHub Release, so drafts and pre-releases are skipped. Works
from a downloaded tarball as well as a clone — no git needed.

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
never touched.

## Releasing

`/release` in this repo — bump `VERSION` on `main`, merge into `release/vX.x`,
tag there. The tag is what publishes it. See
`.claude/skills/release/SKILL.md`.
