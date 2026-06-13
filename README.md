# Claude Code Touch Bar Companion

<p align="right">
  <a href="README.md"><img src="https://img.shields.io/badge/English-111827?style=for-the-badge" alt="English"></a>
  <a href="README_%E4%B8%AD%E6%96%87.md"><img src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-2563EB?style=for-the-badge" alt="中文"></a>
</p>

![macOS](https://img.shields.io/badge/macOS-Touch%20Bar-111827?style=for-the-badge&logo=apple&logoColor=white)
![Claude Code](https://img.shields.io/badge/Claude%20Code-Hooks-D97706?style=for-the-badge)
![BetterTouchTool](https://img.shields.io/badge/BetterTouchTool-Ready-2563EB?style=for-the-badge)
![No Keyboard Injection](https://img.shields.io/badge/No%20Keyboard%20Injection-Safe-16A34A?style=for-the-badge)

![1780981115328](image/README/1780981115328.png)

Turn your MacBook Pro Touch Bar into a compact permission console for Claude Code.

Instead of repeatedly jumping back into the terminal for small approvals, this companion surfaces the current Claude Code permission request on the Touch Bar, lets you tap the right action, and sends the result back through Claude Code's structured `PermissionRequest` hook output.

> Scope note: this MVP is currently developed specifically for the BetterTouchTool workflow. Future iterations may add a native helper or other interaction surfaces once the hook flow is stable.

```text
Read PRD_中文.md                  [Yes] [Yes all session] [No]
Create permission-edit-test.md   [Yes] [All edits] [No]
Delete touchbar-test.md          [Yes] [No] [Review]
Delete tmp                       [Review on screen] [No]
Run npm test                     [Yes] [No] [Review]
```

## Why This Exists

Claude Code is great at staying in flow, but agentic coding still involves lots of tiny decisions:

- read this file?
- create this file?
- run this command?
- delete this temporary artifact?
- allow edits for this session?

This project gives those small, repetitive decisions a low-friction second surface while keeping the full Claude Code TUI as the source of truth.

## Highlights

- **Structured hook flow**: returns `allow`, `deny`, and `updatedPermissions` through Claude Code hooks.
- **No keyboard injection**: does not type into the terminal or depend on terminal focus.
- **Touch Bar native feel**: BetterTouchTool widgets show one context item plus up to three actions.
- **Session actions**: supports `Yes all session` for `Read` and `All edits` for Claude Code edit suggestions.
- **Risk-aware actions**: high-risk requests hide direct approval and keep `Review on screen / No`.
- **Short summaries**: long paths and Bash commands are compressed for glanceable Touch Bar labels.
- **Local-only state**: uses `~/.claude-touchbar/` for state, logs, and response files.

## How It Works

```text
Claude Code PermissionRequest
        |
        v
.claude/hooks/touchbar_hook.py
        |
        v
~/.claude-touchbar/state.json
        |
        v
BetterTouchTool Touch Bar widgets
        |
        v
scripts/btt_action.py
        |
        v
~/.claude-touchbar/responses/<request_id>.json
        |
        v
Claude Code structured hook decision
```

## Touch Bar Layout

Create four BetterTouchTool Shell Script / Task widgets:

```text
[Context] [Action 1] [Action 2] [Action 3]
```

The context item is display-only by default. It tells you what Claude Code is asking for; optionally, its click action can run `scripts/start_claude_iterm2.sh` to launch Claude Code in a new iTerm2 window. The action items call `scripts/btt_action.py` with index `0`, `1`, or `2`.

See [docs/BTT_SETUP.md](docs/BTT_SETUP.md) for the exact BetterTouchTool scripts.

## Current Behavior

| Request                                                 | Touch Bar actions              |
| ------------------------------------------------------- | ------------------------------ |
| `Read`                                                | `Yes / Yes all session / No` |
| `Write`, `Edit`, `MultiEdit` with edit suggestion | `Yes / All edits / No`       |
| normal low or medium risk request                       | `Yes / No / Review`          |
| high-risk delete or shell command                       | `Review on screen / No`      |
| expired state                                           | `CC Ready`                   |

`Review` / `Review on screen` intentionally does not approve the request. It lets Claude Code fall back to the normal on-screen permission flow.

## Claude Code Permission Modes

The Touch Bar Companion only activates when Claude Code triggers a `PermissionRequest`. This depends on which permission mode you use:

| Mode                         | Triggers Touch Bar? | Notes                                                       |
| ---------------------------- | ------------------- | ----------------------------------------------------------- |
| **Default (no mode)**  | ✅ All requests     | Write, Edit, Bash all require approval                      |
| **Accept Edits**       | ⚠️ Partial        | Write/Edit auto-approved, Bash still triggers               |
| **Auto Mode**          | ⚠️ Partial        | CC auto-approves low-risk ops, uncertain ones still trigger |
| **Bypass Permissions** | ❌ Never            | All ops auto-approved, hook is never called                 |
| **Plan Mode**          | ❌ Never            | No tool calls, nothing to approve                           |

**Recommended for testing**: use default mode so all permission requests go through the Touch Bar.

## Quick Start

1. Keep this project in your Claude Code workspace.
2. Ensure the project-local hook is registered through [.claude/settings.local.json](.claude/settings.local.json).
3. Configure the four BetterTouchTool widgets from [docs/BTT_SETUP.md](docs/BTT_SETUP.md).
4. Trigger a Claude Code permission request.
5. Tap the Touch Bar action.

During MVP testing, this project intentionally asks before `Read` calls so the Touch Bar flow is easy to test. Remove or narrow that rule once the flow is proven for daily use.

## Project Structure

```text
.claude/hooks/touchbar_hook.py   # Claude Code hook: state writer and decision bridge
.claude/hooks/touchbar-hook.sh   # hook shell wrapper
scripts/btt_state.py             # BetterTouchTool dynamic label reader
scripts/btt_action.py            # BetterTouchTool action writer
scripts/start_claude_iterm2.sh   # optional Context item click action for launching Claude Code
docs/BTT_SETUP.md                # BetterTouchTool setup guide
docs/HOOK_SETUP.md               # hook behavior and manual tests
ONE_PAGE.md                      # project one-pager
README_中文.md                    # Chinese README
PRD_中文.md                       # Chinese PRD
TODO.md                          # implementation checklist
Progress.md                      # current progress notes
```

## Safety Model

The companion is deliberately conservative:

- High-risk or unknown-risk actions cannot be directly approved from the Touch Bar.
- `Review` is a handoff, not an approval.
- Event logs redact prompts, assistant messages, and file contents.
- State files are written atomically.
- Each permission request gets a fresh `request_id`.

This is a companion interface, not a replacement for Claude Code's main permission UI.

## Manual Checks

Inspect current Touch Bar state:

```sh
python3 -m json.tool ~/.claude-touchbar/state.json
```

Inspect action clicks:

```sh
tail -n 1 ~/.claude-touchbar/actions.jsonl
```

Inspect pending response files:

```sh
find ~/.claude-touchbar/responses -maxdepth 1 -type f -print
```

## Roadmap

- Prepare a stable two-minute demo path.
- Expand the real permission test matrix.
- Consider a native helper after the hook/BTT MVP is stable.

## Status

MVP is functional for real Claude Code permission requests with BetterTouchTool on macOS Touch Bar. The project is currently BTT-first and will iterate from this foundation.
