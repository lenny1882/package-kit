---
name: claude-package-kit
description: Build and package a Claude Code customisation — a hook, skill, slash command, or CLI tool — following this machine's house layout, with an installer, tests, update path and release process. Use when the user asks for something to be built that will be installed into ~/.claude or ~/.local/bin, or asks to package something that already exists there.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - AskUserQuestion
---

# Building a Claude Code customisation

Nothing gets installed by hand. Anything asked for that ends up in
`~/.claude/hooks`, `~/.claude/skills`, `~/.claude/bin` or `~/.local/bin` is a
package with a source directory, an installer, and tests — because the
alternative is what happened before: working code with no source, no tests, and
no record of why it exists.

## 1. Before writing anything

Read the inventory. It says what already exists and how well packaged each one
is. If the ask is close to something already there, extend that package rather
than starting another.

Find it with the first of these that names a file:

```bash
: "${CLAUDE_INVENTORY:=}"
for f in "$CLAUDE_INVENTORY" "$CLAUDE_PROJECT_DIR/INVENTORY.md" \
         "$HOME/claude-sandbox/INVENTORY.md"; do
  [ -n "$f" ] && [ -f "$f" ] && { echo "$f"; break; }
done
```

If none of them exists there is no inventory on this machine — say so and carry
on. A missing inventory is not a reason to stop.

Decide with the user, not for them:

- **Which kind.** `hook` fires on a Claude Code event; `skill` is instructions
  Claude loads on demand; `command` is an executable on `PATH`. A thing that
  needs to *stop* Claude doing something is a hook. A thing that tells Claude
  *how* to do something is a skill.
- **Where it lives.** Ask, and offer what this machine already uses: the
  directory holding the inventory found above for local-only work, or the
  directory the published packages sit in — the parent of this repo's own
  checkout. Both use the same layout, so this can be changed later by moving
  the directory.

## 2. Scaffold it

```bash
"$HOME/.claude/skills/claude-package-kit/bin/new-package.sh" \
  --name <kebab-case-name> --kind hook|skill|command [--dir <where>]
```

Add `--no-release` for something that will never be published — it leaves out
`update.sh`, the update check, the release workflow and the release skill.

Do not assemble these files by hand. The installer machinery is subtle in ways
that are invisible when it goes wrong: a settings merge that drops another
package's entries, an installer that is not safe to run twice, a hook whose name
contains `gsd-` and gets silently deleted by GSD's own migration. All of that is
already handled.

## 3. Write it

The generated files leave three things marked, and each one matters:

- **The source file** — and the comment at the top saying *why it exists*. Not
  what it does; the code says that. What went wrong without it, what was tried
  first and did not work, what breaks if someone simplifies it. Read
  `reference/hook-events.md` before writing a hook: what a hook can and cannot
  do is mostly undocumented, and half of it is counter-intuitive.
- **`manifest.sh`** — what gets installed and registered, and `verify_probe`,
  the live check the installer runs at the end. Make the probe exercise the real
  behaviour. An installer that only checks the file exists will cheerfully
  report success on a script that cannot run.
- **`test/run-tests.sh`** — it fails on a deliberate TODO until behaviour tests
  are written. The installer tests come free; they prove nothing about whether
  the thing works.

## 4. Install and record it

```bash
./test/run-tests.sh && ./install.sh --link
```

`--link` symlinks the checkout so edits are live. `~/.claude/hooks` and
`settings.json` are outside the sandbox's writable area, so hand the user the
command to run rather than running it. If Claude Code is already running,
`/hooks` forces a settings reload; a new hook still needs a restart.

Then add a row to the inventory naming the installed file exactly as it appears
on disk. `inventory-guard` matches by basename and will block the turn otherwise.
Skip this when there is no inventory file.

## 5. Publishing

Only when asked. `git init`, creating a GitHub repo, pushing, and cutting a
release are all outward-facing — each needs the user's agreement in the moment,
and agreeing to one is not agreeing to the next. The process is in
`reference/release.md`, and every published package carries its own `/release`
skill.

## Reference

- `reference/layout.md` — the file layout and what each installer must do
- `reference/hook-events.md` — what hooks can actually do, most of it undocumented
- `reference/release.md` — publishing and cutting releases
