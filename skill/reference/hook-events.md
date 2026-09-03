# What hooks can actually do

Most of this is not in the documentation. It was read out of the compiled
Claude Code binary at 2.1.228, re-read at 2.1.259, and confirmed by running it.
Check it still holds before relying on any of it in a new package — an update
can withdraw an undocumented behaviour without saying so.

## Deny, not ask

At 2.1.228 a `PreToolUse` hook returning `ask` never reached the user in auto
mode — the harness resolved it through the same classifier that approves
ordinary tool calls, and it approved a test command silently.

**That is no longer true.** Re-tested at 2.1.259 in an interactive session under
`--permission-mode auto`, with a hook returning `ask` on every `Read`. The hook
fired and the dialog appeared:

```
Read(/tmp/…/target.txt)
Do you want to proceed?
❯ 1. Yes
  2. No
Esc to cancel · Tab to amend
```

Two things to know before relying on it.

**The reason is not shown.** `permissionDecisionReason` appeared nowhere on
screen — the dialog names the tool call and asks. Whatever the hook wanted to
explain, the person deciding does not see it. A `deny` still carries its message,
so a hook with something to say is still better off denying and spending the
text on it.

**A hook on one tool does not cover the job that tool does.** In the first run
the same probe held `Read` at the prompt, and Claude simply read the file with
`cat` through `Bash`, which had no hook on it, and carried on. Guard the
intention, not the tool: work out every tool that reaches the thing you care
about, or accept that the guard is advisory.

A headless run tells you nothing here. At 2.1.259 `ask` under `auto` and under
`manual` both refused identically, which is the documented headless behaviour —
the binary states it for `PreModelSwitch` as "a headless session refuses
instead". Test this one interactively or not at all.

There is now a fourth decision, `defer`, alongside `allow`, `deny` and `ask`. It
parks the tool call to be resolved in a later resumed session rather than
deciding now — and the resume does not restore the permission mode it was
deferred under, so `--resume` needs `--permission-mode` passed again to match. A
call being served to a cloud session cannot be deferred at all; there is no
resume machinery for it, and the deferral is turned into a denial.

## Exit codes

- **0** — allowed. On most events stdout is ignored; the exceptions are below.
- **2** — blocking. stderr goes to the model on `PreToolUse` and `Stop`, and to
  the user on `PreCompact`.
- **Anything else** — counts as *failed*, not blocked, so the action proceeds.
  A hook that times out lands here. The default timeout is 600 seconds and the
  per-hook `timeout` field is in **seconds**.

## Events worth knowing

The whole roster at 2.1.259, in the order the binary declares it:

`PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`,
`PermissionDenied`, `Notification`, `UserPromptSubmit`, `UserPromptExpansion`,
`SessionStart`, `Stop`, `StopFailure`, `SubagentStart`, `SubagentStop`,
`PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `SessionEnd`,
`PermissionRequest`, `Setup`, `TeammateIdle`, `TaskCreated`, `TaskCompleted`,
`Elicitation`, `ElicitationResult`, `ConfigChange`, `InstructionsLoaded`,
`WorktreeCreate`, `WorktreeRemove`, `CwdChanged`, `FileChanged`,
`DirectoryAdded`, `MessageDisplay`.

The ones added since this page was first written:

- **`PostToolUseFailure`** — a tool call failed. Gets `tool_name`, `tool_input`,
  `tool_use_id`, `error`, `error_type`, `is_interrupt`, `is_timeout`; matcher is
  `tool_name`. Exit 2 shows stderr to the model immediately.
- **`PostToolBatch`** — fires once after every call in a batch resolves, before
  the next model request. Gets `tool_calls`, an array of `{tool_name,
  tool_input, tool_use_id, tool_response}`. Return `additionalContext` through
  `hookSpecificOutput` to inject context once for the whole batch instead of
  once per call. Exit 2 stops the agentic loop.
- **`PermissionDenied`** — the auto-mode classifier refused a call. Gets
  `tool_name`, `tool_input`, `tool_use_id`, `reason`. Return
  `{"hookSpecificOutput":{"hookEventName":"PermissionDenied","retry":true}}` to
  tell the model it may try again.
- **`StopFailure`** — fires *instead of* `Stop` when an API error ended the
  turn. Matcher is `error`: `rate_limit`, `overloaded`,
  `authentication_failed`, `billing_error`, `max_output_tokens` and the rest.
  Fire-and-forget — output and exit codes are ignored, so it cannot hold a turn
  open the way `Stop` can.
- **`PreModelSwitch`** / **`PostModelSwitch`** — a `/model`, picker or
  `set_model` change. Both get `from_model`, `to_model`, `requested_model`,
  `source`, `context_tokens` and the estimated re-cache cost; matcher is
  `to_model`. `PreModelSwitch` takes a `permissionDecision` of allow/deny/ask
  exactly as `PreToolUse` does, and exit 2 blocks the switch.
- **`TeammateIdle`** — a teammate is about to go idle. Gets `teammate_name` and
  `team_name`. Exit 2 sends stderr to the teammate and keeps it working.
- **`WorktreeCreate`** / **`WorktreeRemove`** — these two *implement* worktrees
  rather than observing them. `WorktreeCreate` gets `name`, a suggested slug,
  and must print the absolute path of the directory it made on stdout; a
  non-zero exit means creation failed. `WorktreeRemove` gets `worktree_path`.
  This is the hook interface for isolation on something other than git.
- **`Setup`** — repo setup, matcher `trigger` of `init` or `maintenance`. On
  exit 0 its JSON `additionalContext` goes to Claude, so it can hand a fresh
  checkout whatever a session needs to know about it.
- **`Elicitation`** — an MCP server is asking the user for input. Gets
  `mcp_server_name`, `message`, `requested_schema`; matcher is
  `mcp_server_name`. Return `hookSpecificOutput` with an `action` of
  `accept`/`decline`/`cancel` and optional `content` to answer **in the user's
  place**; exit 2 denies outright.
- **`ElicitationResult`** — after the user answers one. Gets
  `mcp_server_name`, `action`, `content`, `mode`, `elicitation_id`, and can
  return an `action` and `content` that override what the user actually said.
  Exit 2 turns the response into `decline`.
- **`InstructionsLoaded`** — a `CLAUDE.md` or rule file was read. Gets
  `file_path`, `memory_type` (`User`, `Project`, `Local`, `Managed`),
  `load_reason` (`session_start`, `nested_traversal`, `path_glob_match`,
  `include`, `compact`), plus `globs`, `trigger_file_path` and
  `parent_file_path` when they apply; matcher is `load_reason`. Stated as
  observability-only — it cannot block.
- **`DirectoryAdded`** — after `/add-dir` or the `register_repo_root` SDK
  control request adds a working directory. Gets `directory` and `source`
  (`slash_command` or `register_repo_root`), which is also the matcher. It runs
  *after* the sandbox configuration is refreshed, so the new directory is
  already visible to sandboxed tools by the time the hook sees it — and hook
  commands themselves run unsandboxed either way.
- **`MessageDisplay`** — fires while Claude's reply is being printed. Gets
  `turn_id`, `message_id`, `index`, `final` and `delta`, the newly completed
  lines, and can return `displayContent` to **replace that text on screen**.
  Display-only: the stored message and what the model sees are untouched, so
  the transcript and the terminal can be made to disagree. A non-zero exit
  falls back to printing the original.

**`UserPromptExpansion`** is the event for a slash command the user typed. A
typed `/gsd:discuss-phase` never becomes a `Skill` tool call, so a `PreToolUse`
hook with matcher `Skill` never sees it — that gap is easy to miss, because the
same command started by Claude does go through `PreToolUse`. Catching both means
registering one script on both events.

It receives `expansion_type` (`slash_command` or `mcp_prompt`), `command_name`,
`command_args`, `command_source`, and `prompt`, which is `/<name> <args>`. The
matcher is compared against `command_name`; leaving the matcher out runs the hook
on every slash command, which is the safe choice when you are not certain what
name a plugin's command registers under, since a matcher that misses fails
silently.

Exit 2 blocks it. The block sets `shouldQuery: false`, so **Claude is not invoked
at all** — the stderr is printed to the user as a terminal warning, followed by
`Original prompt: <the command>`. A refusal here has to tell the *user* what to
do; there is no model turn to instruct. That is the opposite of the `PreToolUse`
convention above, and getting it backwards produces a message nobody acts on.
Confirmed against 2.1.259 on 3 Sep 2026.

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
