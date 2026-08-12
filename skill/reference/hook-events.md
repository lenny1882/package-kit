# What hooks can actually do

Most of this is not in the documentation. It was read out of the compiled
Claude Code binary at 2.1.228 and confirmed by running it. Check it still holds
before relying on any of it in a new package — an update can withdraw an
undocumented behaviour without saying so.

## Deny, not ask

A `PreToolUse` hook can return `ask`, which reads like the obvious way to put a
decision to the user. **In auto mode it never reaches them.** The harness
resolves an `ask` through the same classifier that approves ordinary tool calls,
and it approved a test command silently. `deny` is the only decision beyond its
reach.

So a hook that wants a human writes `deny` and spends its refusal text telling
Claude what to ask. Both guard hooks on this machine work that way. If either is
ever "tidied up" to `ask`, it stops working and nothing visibly breaks.

## Exit codes

- **0** — allowed. On most events stdout is ignored; the exceptions are below.
- **2** — blocking. stderr goes to the model on `PreToolUse` and `Stop`, and to
  the user on `PreCompact`.
- **Anything else** — counts as *failed*, not blocked, so the action proceeds.
  A hook that times out lands here. The default timeout is 600 seconds and the
  per-hook `timeout` field is in **seconds**.

## Events worth knowing

`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `SessionStart`, `SessionEnd`,
`Stop`, `SubagentStart`, `SubagentStop`, `PreCompact`, `PostCompact`,
`Notification`, `PermissionRequest`, `ConfigChange`, `CwdChanged`,
`FileChanged`, `TaskCreated`, `TaskCompleted`, and more.

**`PreCompact`** matches `manual` (from `/compact`) or `auto`, and receives
`transcript_path`, `cwd`, `trigger` and `custom_instructions`. Exit 2 cancels
the compaction. On exit 0 its **stdout becomes the compaction instructions**,
which is a cheap way to steer what a summary keeps.

**`Stop`** fires at the end of a turn. Exit 2 stops the turn ending and feeds
stderr back to the model, which is how `inventory-guard` makes the record get
written. Honour `stop_hook_active` in the input and return success while it is
true — the harness warns that a hook which cannot be satisfied otherwise loops
until a cap.

## Handing work to the running session

`asyncRewake: true` on a hook backgrounds it, and on exit 2 its stderr is
injected as a system-reminder that starts a turn. It is the **only** mechanism
by which a hook can give the live session a task. `rewakeMessage` sets the
prefix and `rewakeSummary` the terminal one-liner; both are marked `@internal`
in the settings schema, so treat them as borrowed.

It lives in the shared hook runner rather than the Stop-specific path, which is
why it works on `PreCompact` too — confirmed on 12 Aug 2026 by `handoff-gate`.

## Hook types beyond `command`

- `prompt` — evaluated by a model, returns a verdict. No tools, so it cannot
  write files. Defaults to a small fast model; `model` overrides it.
- `mcp_tool` — calls a tool on a configured MCP server.
- `http` — POSTs the hook input to a URL.

## Other things that cost time to learn

- Hooks are read at **startup**. `/hooks` forces a settings reload in a running
  session, but a newly added hook needs a restart.
- Hooks run **outside** the Bash sandbox, so they can write where the assistant
  cannot — including `~/.claude/hooks` and `settings.json`.
- Transcripts are far larger than a context window: 1.5–5.5 MB is ordinary and
  one reached 26 MB, against roughly 800 KB of context. Any hook handing
  `transcript_path` to a headless run must trim it first.
- Fail open. If `jq` is missing, exit 0 rather than breaking every tool call.
