# Hook Setup

## Goal

This project-local hook setup drives the Touch Bar MVP.

It observes Claude Code events, writes local Touch Bar state, and for `PermissionRequest` can return a structured Claude Code decision:

- `Yes` -> `behavior: allow`
- `No` -> `behavior: deny`
- `Yes all session` -> `behavior: allow` with session `Read` `updatedPermissions`
- `All edits` -> `behavior: allow` with `updatedPermissions`
- `Review` / `Review on screen` -> no decision, fallback to the normal Claude Code permission screen

No keyboard injection is used.

## Files

- `.claude/settings.local.json`
  - Registers project-local hooks.
  - Daily use should not force routine project-local `Read` approvals.
  - For testing/demo only, you can temporarily add `permissions.ask: ["Read"]` so file reads trigger permission prompts.
  - Gives the `PermissionRequest` hook enough timeout to wait for Touch Bar input.

- `.claude/hooks/touchbar-hook.sh`
  - Shell wrapper called by Claude Code.
  - Runs the Python hook and exits safely.

- `.claude/hooks/touchbar_hook.py`
  - Reads hook JSON from stdin.
  - Writes raw but sanitized event files.
  - Writes normalized Touch Bar state.
  - Waits for a Touch Bar response file during `PermissionRequest`.
  - Returns Claude Code structured hook output.

## Output Directory

The hook writes files under:

```text
~/.claude-touchbar/
```

Expected files:

```text
actions.jsonl
events.jsonl
last-event.json
responses/
state.json
```

## State File

`state.json` is the file BetterTouchTool reads.

Example:

```json
{
  "version": 1,
  "request_id": "uuid",
  "session_id": "claude-session-id",
  "updated_at": 1780000000000,
  "expires_at": 1780000030000,
  "kind": "PermissionRequest",
  "context": "Read PRD_中文.md",
  "risk": "low",
  "actions": [
    { "id": "allow", "label": "Yes" },
    {
      "id": "allow_session_read",
      "label": "Yes all session",
      "updated_permissions": [
        {
          "behavior": "allow",
          "destination": "session",
          "rules": [
            { "toolName": "Read", "ruleContent": "//Users/carson/Desktop/code/claude-touchbar-companion/**" }
          ],
          "type": "addRules"
        }
      ]
    },
    { "id": "deny", "label": "No" }
  ],
  "raw_event_path": "/Users/carson/.claude-touchbar/last-event.json"
}
```

Create / edit request with Claude Code session edit suggestion:

```json
{
  "context": "Create permission-edit-test.md",
  "risk": "medium",
  "actions": [
    { "id": "allow", "label": "Yes" },
    {
      "id": "allow_session_edits",
      "label": "All edits",
      "updated_permissions": [
        { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
      ]
    },
    { "id": "deny", "label": "No" }
  ]
}
```

## Permission Response Flow

For `PermissionRequest`, the hook writes a fresh `request_id` into `state.json`, then waits up to 20 seconds for:

```text
~/.claude-touchbar/responses/<request_id>.json
```

The BTT action script writes that response file.

`Yes` response:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow"
    }
  }
}
```

`No` response:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "Denied from Touch Bar"
    }
  }
}
```

`All edits` response:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
      ]
    }
  }
}
```

`Yes all session` response for `Read`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedPermissions": [
        {
          "behavior": "allow",
          "destination": "session",
          "rules": [
            { "toolName": "Read", "ruleContent": "//Users/carson/Desktop/code/claude-touchbar-companion/**" }
          ],
          "type": "addRules"
        }
      ]
    }
  }
}
```

If no response arrives before timeout, the hook exits without a decision and Claude Code falls back to the normal permission dialog.

## Next-Step Questions (Claude Desktop)

Claude desktop ends many turns with a "next step" box: a question plus one or two reply
buttons (for example *Commit and push?* · `提交并推送` · `先不提交`). The same question is shown on
the Touch Bar at the same time, and you can answer in either place.

1. `PreToolUse` of `mcp__ccd_turn__wrap_up` saves the question and the labeled buttons to
   `pending-question.json`. App actions without a label (commit, create PR, ...) are left to
   the screen.
2. When the turn ends, a second Stop hook runs **in the background** (`asyncRewake`), so the
   turn is not held and the box appears on screen right away. It shows
   `[question] [choice 1] [choice 2] [On screen]` on the Touch Bar for up to 5 minutes
   (`CLAUDE_TOUCHBAR_QUESTION_TIMEOUT_MS`).
3. Tapping a choice makes the hook exit with code 2. Its message
   (`The user chose 「…」 on the Touch Bar, answering your question: …`) wakes Claude, even
   when the session is idle, and Claude carries on with it.
4. Answering on screen (or typing anything) starts a new turn. Its `UserPromptSubmit` event
   replaces `state.json`, and the background hook withdraws the question from the Touch Bar.
   `On screen` and the timeout also withdraw it.

Hook configuration for this (in addition to the regular `Stop` hook):

```json
"Stop": [{ "hooks": [
  { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/touchbar-hook.sh" },
  { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/touchbar-hook.sh question",
    "asyncRewake": true, "timeout": 330 }
]}],
"UserPromptSubmit": [{ "hooks": [
  { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/touchbar-hook.sh" }
]}]
```

What testing in Claude desktop showed, and why it works this way:

- Claude desktop only shows its box after every synchronous Stop hook has finished. An
  earlier version waited in a synchronous Stop hook, which hid the box for the whole wait.
- A synchronous Stop hook's `decision: "block"` shows up as a "Stop hook blocking error";
  `additionalContext` reads better but still holds the turn. `asyncRewake` avoids both.
- The question is skipped when the Touch Bar app is not running (its pid is in
  `frontmost.json`).

### A Touch Bar answer is a hint, not an approval

Claude Code delivers the background hook's message as a system notification that is
explicitly *not* user input: Claude cannot tell a real tap from any program that writes the
same response file. So a Touch Bar answer steers what Claude does next, but it never counts
as consent for outward-facing or hard-to-undo actions such as committing or pushing.

Those actions get their consent from Claude Code's permission system instead. Add `ask`
rules so they always raise a permission request, which also shows on the Touch Bar:

```json
"permissions": {
  "ask": ["Bash(git commit *)", "Bash(git push *)", "Bash(git push)", "Bash(gh pr *)"]
}
```

`ask` rules apply even when a broader `allow` rule (such as `"Bash"`) or bypass-permissions
mode would let the command run.

For one-tap commits, skip the question altogether: let Claude run the combined
`git commit … && git push` directly. The permission request it raises is the only question,
shown on screen and on the Touch Bar as `Commit & push` (or `Commit` / `Push`). `Yes` commits
and pushes; `No` leaves everything uncommitted. Answering on screen also takes a single
click this way.

`questions.jsonl` logs when each question was asked and how it ended (`choice_N`, `screen`,
`answered elsewhere`, `timeout`, or `skipped` with a reason); a question without an
`ended_at` line means the hook was cut off while waiting.

## Sanitized Logs

`events.jsonl` and `last-event.json` are sanitized by default.

Redacted fields include:

- `tool_input.content`
- `tool_response.file.content`
- `prompt`
- `last_assistant_message`

This avoids storing full code content, prompts, or assistant messages in the local Touch Bar event log.

## Manual Test

Run this from the project root:

```sh
printf '%s\n' '{
  "hook_event_name": "PermissionRequest",
  "session_id": "manual-test",
  "cwd": "/Users/carson/Desktop/code/claude-touchbar-companion",
  "tool_name": "Read",
  "tool_input": {
    "file_path": "/Users/carson/Desktop/code/claude-touchbar-companion/PRD_中文.md"
  }
}' | CLAUDE_TOUCHBAR_PERMISSION_TIMEOUT_MS=0 ./.claude/hooks/touchbar-hook.sh
```

Inspect:

```sh
python3 -m json.tool ~/.claude-touchbar/state.json
```

Expected Touch Bar state:

```text
Read PRD_中文.md    Yes    Yes all session    No
```

## All Edits Test

```sh
printf '%s\n' '{
  "hook_event_name": "PermissionRequest",
  "session_id": "manual-edit-test",
  "cwd": "/Users/carson/Desktop/code/claude-touchbar-companion",
  "tool_name": "Write",
  "tool_input": {
    "file_path": "/Users/carson/Desktop/code/claude-touchbar-companion/permission-edit-test.md",
    "content": "# test"
  },
  "permission_suggestions": [
    { "destination": "session", "mode": "acceptEdits", "type": "setMode" }
  ]
}' | CLAUDE_TOUCHBAR_PERMISSION_TIMEOUT_MS=0 ./.claude/hooks/touchbar-hook.sh
```

Expected Touch Bar state:

```text
Create permission-edit-test.md    Yes    All edits    No
```

## Optional Read Permission Test

Daily use should not ask before every routine project-local `Read` tool call. Repeated read approvals add friction and can create confirmation fatigue.

If you need to validate or demo the `Read` Touch Bar flow, temporarily add:

```json
"permissions": {
  "ask": ["Read"]
}
```

Remove it again after testing, or replace it with narrower rules for sensitive paths only.

## Stop Events

`Stop` events write `Claude done` as a glanceable status indicator and show no action buttons. Stopping Claude Code from the Touch Bar is intentionally not supported: `Stop` is a notification hook that fires after the turn already ended, so there is nothing to interrupt. The Touch Bar focuses on permission approvals, which is the actual high-friction case.
