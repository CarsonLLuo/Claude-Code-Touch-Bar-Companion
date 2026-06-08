# BetterTouchTool MVP Setup

## Goal

This setup renders Claude Code permission state on the Touch Bar and sends user responses back through the structured hook response path.

No keyboard injection is used.

## Scripts

Use these project scripts in BetterTouchTool Shell Script / Task widgets:

```text
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py
```

## Touch Bar Layout

Create four Touch Bar items:

```text
[Context] [Action 1] [Action 2] [Action 3]
```

The `Context` item is not an approval button. It only shows what Claude Code is asking for.

## Context Widget

Widget type:

```text
Shell Script / Task Widget
```

Script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py context
```

No click action is needed.

Recommended script interval during testing:

```text
1-2 seconds
```

## Action 1 Widget

Dynamic title script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 0
```

Click action script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 0
```

## Action 2 Widget

Dynamic title script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 1
```

Click action script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 1
```

## Action 3 Widget

Dynamic title script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_state.py action-label 2
```

Click action script:

```sh
/Users/carson/Desktop/code/claude-touchbar-companion/scripts/btt_action.py 2
```

## Expected States

Read request:

```text
Read PRD_中文.md    Yes    Yes all session    No
```

Create / edit request with Claude Code session edit suggestion:

```text
Create permission-edit-test.md    Yes    All edits    No
```

Project-local single-file delete:

```text
Delete touchbar-test.md    Yes    No    Review
```

High-risk delete:

```text
Delete tmp    Review    No
```

Unknown / expired state:

```text
Claude idle
```

## Action Behavior

Action clicks append to:

```text
~/.claude-touchbar/actions.jsonl
```

For active `PermissionRequest` states, action clicks also write:

```text
~/.claude-touchbar/responses/<request_id>.json
```

The hook reads that response file and returns a structured decision to Claude Code.

## Edit Session Permissions

When Claude Code shows:

```text
Yes, allow all edits during this session
```

the hook receives a `permission_suggestions` entry similar to:

```json
{
  "destination": "session",
  "mode": "acceptEdits",
  "type": "setMode"
}
```

In that case the Touch Bar shows:

```text
Yes / All edits / No
```

`All edits` returns the suggestion through `updatedPermissions`, equivalent to choosing Claude Code's session-scoped edit permission option.

This button is only shown when Claude Code provides the matching session suggestion.

## Delete Commands

For Bash `rm` requests, the context is summarized instead of showing the full command:

```text
Delete touchbar-permission-test.md
```

Single-file deletes inside the current project are treated as `medium` risk and still show:

```text
Yes / No / Review
```

Recursive deletes, wildcard deletes, directory deletes, and deletes outside the current project are treated as `high` risk and only show:

```text
Review / No
```

## Bash Summaries

Bash commands are summarized before they are shown on the Touch Bar. The full command is not displayed by default.

Examples:

```text
python3 scripts/check.py  ->  Run Python scripts/check.py
npm test                  ->  Run npm test
pytest tests/foo.py       ->  Run pytest tests/foo.py
rm file.md                ->  Delete file.md
unknown-long-command ...  ->  Run unknown-long-command
```

Unknown commands show only the command name, not the full argument list.

## Manual Checks

After a real Claude Code permission request:

```sh
python3 -m json.tool ~/.claude-touchbar/state.json
```

After tapping an action:

```sh
tail -n 1 ~/.claude-touchbar/actions.jsonl
```

For `PermissionRequest` responses:

```sh
find ~/.claude-touchbar/responses -maxdepth 1 -type f -print
```

## Acceptance

- Context shows the latest valid `state.json` context.
- Action buttons show current labels.
- Expired state shows `Claude idle` and empty action labels.
- `Yes` returns an allow decision.
- `Yes all session` returns allow + session `Read` `updatedPermissions`.
- `No` returns a deny decision.
- `All edits` returns allow + `updatedPermissions`.
- `Review` does not approve and falls back to the main Claude Code screen.
- No keyboard input is injected into Claude Code.
