# claude-package-kit

A skill and a scaffolder, so anything built for Claude Code on this machine
comes out the same shape as the three repos that have already been through a
release cycle — `claude-branch-guard`, `claude-notify` and `session-colour`.

The problem it solves is the one `INVENTORY.md` records: things were getting
built, installed, and forgotten, leaving the installed copy as the only copy. No
source, no tests, no note of why it exists. This makes the packaged version the
default and the cheapest path, rather than something to get round to.

## Install

Needs `jq`. The repo is `package-kit`; what it installs is `claude-package-kit`,
which is the name the skill answers to inside Claude Code.

    git clone git@github.com:lenny1882/package-kit.git claude-package-kit
    cd claude-package-kit
    ./install.sh              # copy the skill into ~/.claude/skills
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # say what would happen, write nothing
    ./install.sh --yes        # no prompts

Or without cloning, from the newest release:

    curl -fsSL https://github.com/lenny1882/package-kit/releases/latest/download/claude-package-kit.tar.gz | tar -xz
    cd claude-package-kit && ./install.sh

Re-running it is safe and is how you upgrade. Nothing is written to
`settings.json` — Claude Code reads anything under `skills/` at startup — and
the installer finishes by scaffolding a throwaway package and checking it came
out complete, rather than checking the files merely arrived. Skills load at
startup, so restart Claude Code afterwards.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads the newest GitHub Release, so drafts and pre-releases are skipped. Works
from a downloaded tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh

## Use

Ask for something to be built and the skill should load on its own. By hand:

    ~/.claude/skills/claude-package-kit/bin/new-package.sh \
      --name my-thing --kind hook|skill|command [--dir <where>] [--no-release]

That creates the directory with the machinery filled in and three things left
marked: the source file, `manifest.sh`, and the behaviour tests. The generated
test suite fails on a deliberate TODO until real tests are written.

## What a generated package gets

```
my-thing/
  README.md  VERSION  .gitignore
  manifest.sh                      what gets installed and registered
  install.sh                       --link --yes --dry-run, safe to re-run
  uninstall.sh                     --yes --keep-settings
  update.sh                        newest GitHub Release, no git needed
  lib/update-check.sh              once-a-day update notice
  hooks/ | skill/ | bin/           the thing itself
  test/run-tests.sh                against a throwaway HOME and CLAUDE_DIR
  .github/workflows/release.yml    tag -> GitHub Release with an install tarball
  .claude/skills/release/SKILL.md  how to cut one
```

`update.sh`, `lib/update-check.sh`, the release workflow and the release skill
are carried over from the reference repos with the name substituted — they are
proven, not rewritten. `--no-release` leaves all four out for something that
will never be published.

This repo has that layout too, produced by its own scaffolder — `manifest.sh`,
`install.sh`, `uninstall.sh`, `update.sh`, `lib/update-check.sh`, the release
workflow and the `/release` skill are all generated files with the name
substituted in, not hand-written copies.

The installer machinery is worth not reinventing. It merges into `settings.json`
instead of replacing it, strips only its own entries so other packages survive,
writes nothing when nothing changed, is safe to run twice, honours `CLAUDE_DIR`
so tests never touch the real config, and ends with a live probe that the thing
works rather than merely exists. Each of those is in there because of something
that went wrong once.

## Reference

Three documents ship inside the skill, and they are the reason it is worth
having as more than a template:

- `reference/layout.md` — the layout and what every installer must do
- `reference/hook-events.md` — what hooks can actually do. Most of it is
  undocumented and read out of the compiled binary: why `deny` is the only
  decision that reaches a human in auto mode, what each exit code means, what
  `PreCompact` and `Stop` can do, and `asyncRewake` — the one mechanism by which
  a hook can hand work to the running session.
- `reference/release.md` — publishing, and the rule that a release tag is only
  ever created on its `release/vX.x` branch after `main` is merged in.

## Tests

    ./test/run-tests.sh

Scaffolds one package of each kind, checks no placeholder survives, then
installs, re-installs, dry-runs and uninstalls the generated hook package
against a throwaway config — including that it leaves another package's hooks
alone. It then does the same to this repo itself, so the kit is held to the
layout it hands out.

## Releasing

`/release` in this repo — bump `VERSION` on `main`, merge into `release/vX.x`,
tag there. The tag is what publishes it. See `.claude/skills/release/SKILL.md`,
and `skill/reference/release.md` for why the branch rule exists.
