# Hook Setup

## Goal

This project-local hook setup drives the Touch Bar MVP.

It observes Claude Code events, writes local Touch Bar state, and for `PermissionRequest` can return a structured Claude Code decision:

- `Yes` -> `behavior: allow`
- `No` -> `behavior: deny`
- `Yes all session` -> `behavior: allow` with session `Read` `updatedPermissions`
- `All edits` -> `behavior: allow` with `updatedPermissions`
- `Review` -> no decision, fallback to the normal Claude Code permission screen

No keyboard injection is used.

## Files

- `.claude/settings.local.json`
  - Registers project-local hooks.
  - Adds temporary `permissions.ask: ["Read"]` so file reads trigger permission prompts during MVP testing.
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

## Temporary Permission Setting

This project currently asks before every `Read` tool call:

```json
"permissions": {
  "ask": ["Read"]
}
```

This is only for validating the Touch Bar permission flow. Remove it or replace it with narrower rules after the MVP hook path is proven.

## Current Limitation

`Stop` events currently write `Claude done`, but the implementation can still generate `Continue / Stop` actions that are not wired to real Claude Code control. The next implementation step should hide those actions.
