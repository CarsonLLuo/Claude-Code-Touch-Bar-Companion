# Claude Code Touch Bar Companion

## One Page v0.2

### Project Summary

Claude Code primarily runs in a terminal TUI. This project explores whether the MacBook Pro Touch Bar can act as a secondary interaction surface for Claude Code: showing concise permission summaries, lightweight state, and safe actions so the user can respond with `Yes`, `No`, `All edits`, or `Review` without shifting attention away from the main coding context.

The goal is not to replace the Claude Code TUI. It is to add a low-friction companion interface for frequent small decisions in agentic coding workflows.

### Verified Core Flow

```text
Claude Code PermissionRequest
        ↓
Project-local hook writes ~/.claude-touchbar/state.json
        ↓
BetterTouchTool Touch Bar widgets read state.json
        ↓
Touch Bar shows [Context] [Action 1] [Action 2] [Action 3]
        ↓
User taps Yes / No / All edits / Review
        ↓
btt_action.py writes ~/.claude-touchbar/responses/<request_id>.json
        ↓
Hook returns structured allow / deny / updatedPermissions to Claude Code
        ↓
Claude Code continues, denies, or applies session-scoped edit permission
```

The current implementation does not use keyboard injection and does not depend on iTerm2 focus. Permission results are returned through Claude Code's structured `PermissionRequest` hook output.

### Touch Bar UI

The MVP uses four Shell Script / Task widgets:

```text
[Context] [Action 1] [Action 2] [Action 3]
```

Examples:

```text
Read PRD_中文.md                  [Yes] [Yes all session] [No]
Create permission-edit-test.md   [Yes] [All edits] [No]
Delete touchbar-test.md          [Yes] [No] [Review]
Delete tmp                       [Review] [No]
Run npm test                     [Yes] [No] [Review]
```

The first item is a request summary, not an action button. It reduces accidental approval risk.

### Current Capabilities

- Captures real Claude Code `PermissionRequest` events.
- Completes real `Yes` and `No` flows from Touch Bar.
- Supports `All edits` for create / edit requests when Claude Code provides a session `acceptEdits` permission suggestion.
- Supports session-scoped read approval for `Read` requests.
- Summarizes `Read`, `Write`, `Bash`, and `rm` requests.
- Summarizes Bash commands instead of showing full command strings and long absolute paths.
- Sanitizes local event logs by default.
- Prevents one-tap approval for high-risk or unknown-risk actions.

### Risk Model

- `low`
  - Normal `Read`
  - Low-risk Bash requests
  - `Read` shows `Yes / Yes all session / No`

- `medium`
  - `Write` / `Edit` / `MultiEdit`
  - Explicit single-file `rm` inside the project
  - Shows `Yes / No / Review` or `Yes / All edits / No`

- `high`
  - `sudo`
  - `rm -rf`
  - Recursive deletes
  - Wildcard deletes
  - Directory deletes
  - Deletes outside the current project
  - `chmod -R`
  - `chown -R`
  - `curl | sh`
  - `wget | sh`
  - `~/.ssh`
  - `/Library`
  - `/System`
  - Shows `Review / No`

- `unknown`
  - Unclassified state
  - No direct approval

### Why It Matters

LLM coding agents frequently ask for small decisions: read a file, create a file, run a command, delete a temporary file, or approve edit permissions for the session. These decisions matter, but their UI is repetitive. The Touch Bar is well suited for short, immediate, low-attention confirmations.

Research question:

> Can the Touch Bar serve as a low-attention permission interface for AI coding agents while preserving user safety awareness?

### Technical Architecture

Current MVP:

```text
Claude Code hooks
  -> .claude/hooks/touchbar_hook.py
  -> ~/.claude-touchbar/state.json
  -> BetterTouchTool Shell Script / Task Widget
  -> scripts/btt_action.py
  -> ~/.claude-touchbar/responses/<request_id>.json
  -> PermissionRequest hook decision
```

Key properties:

- `state.json` is written atomically.
- Each permission request has a `request_id`.
- BTT action clicks write response files.
- The hook waits up to 20 seconds for a response file.
- `Review` does not approve. It falls back to the main Claude Code screen.
- `All edits` is only shown when Claude Code provides a matching `permission_suggestions` entry.

### Non-goals

- No full TUI parsing.
- No OCR or pixel recognition.
- No diff viewer navigation.
- No control of `/config`, `/permissions`, or other internal menus.
- No autocomplete, `@` mention, or character-by-character input tracking.
- No multi-session management.
- No keyboard injection control.
- No native Swift / AppKit helper.
- No public distribution package.

### Next Steps

1. Hide unimplemented `Stop` actions and show only `Claude done`.
2. Prepare a stable two-minute demo checklist.
3. Run the real test matrix:
   - `Read file` -> `Yes`
   - `Read file` -> `No`
   - `Write/Create file` -> `All edits`
   - project-local single-file `rm` -> `Yes`
   - `rm -rf` -> `Review / No`
   - `python3 ...` -> short summary
4. Remove or narrow the temporary `permissions.ask: ["Read"]` setting.
