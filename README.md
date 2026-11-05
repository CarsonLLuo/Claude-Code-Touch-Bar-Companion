<div align="center">

# Claude Code Touch Bar Companion

**Answer Claude Code permission requests from your MacBook Pro Touch Bar**

When Claude Code asks to edit a file or run a command, the request shows up on the Touch Bar as a short summary with a few buttons. One tap sends the answer back through Claude Code's own hooks. You never have to switch to the terminal, and no keystrokes are injected.

![status](https://img.shields.io/badge/status-MVP-orange?style=flat-square)
![platform](https://img.shields.io/badge/platform-macOS_Touch_Bar-black?style=flat-square&logo=apple)
![app](https://img.shields.io/badge/app-Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![integration](https://img.shields.io/badge/integration-Claude_Code_hooks-D97706?style=flat-square)

[Design principles](#design-principles) · [How it works](#how-it-works) · [Quick start](#quick-start) · [Roadmap](#roadmap)

English | [简体中文](./README.zh-CN.md)

</div>

---

> **Status: the MVP works end to end** with real Claude Code permission requests. The Touch Bar is now rendered by a native Swift menu bar app; the original BetterTouchTool setup is kept as a legacy option.

![Touch Bar screenshot](image/README/1780981115328.png)

## Why?

Agentic coding is full of tiny decisions:

- read this file?
- create this file?
- run this command?
- delete this temporary artifact?
- allow edits for the rest of this session?

Each one is small, but each one pulls you back to the terminal and out of whatever you were doing. The Touch Bar sits right above the keyboard and is good at exactly this kind of glance-and-tap interaction. This project turns it into a second surface for those decisions, while the Claude Code TUI stays the source of truth.

## Design principles

1. **Structured, not injected.** Answers go back as structured `PermissionRequest` hook output (`allow`, `deny`, `updatedPermissions`). Nothing is typed into the terminal, and terminal focus does not matter.
2. **Conservative about risk.** High-risk and unknown-risk requests never get a one-tap approval, only `Review on screen / No`. `Review` hands control back to Claude Code; it never approves.
3. **Glanceable.** Long paths and Bash commands are compressed into short labels such as `Delete tmp` or `Run npm test`.
4. **Out of the way.** The companion bar pops up only when a request needs an answer, then steps aside so the regular Touch Bar (including Esc) comes back.
5. **Never act on stale state.** Every request gets a fresh `request_id`; a tap is ignored if the request has changed since the button was drawn.
6. **Local only.** State, responses and logs live in `~/.claude-touchbar/`. Logs redact prompts, assistant messages and file contents.

## What the Touch Bar shows

```text
[x] [Logo Context] [Action 1] [Action 2] [Action 3]
```

| Request | Example context | Actions |
| --- | --- | --- |
| `Read` | `Read PRD.md` | `Yes / Yes all session / No` |
| `Write`, `Edit`, `MultiEdit` with an edit suggestion | `Create permission-edit-test.md` | `Yes / All edits / No` |
| Low or medium risk request | `Delete touchbar-test.md`, `Run npm test` | `Yes / No / Review` |
| High-risk delete or shell command | `Delete tmp` | `Review on screen / No` |
| Nothing pending | `CC Ready` | none |

The context item is a white, display-only pill, optionally prefixed by an icon from `~/.claude-touchbar/icon.png`. Actions are colored by meaning: `Yes` green, session-wide allow blue, `No` red, review actions gray.

## How it works

The hook and the Touch Bar app talk only through local files. A request flows up; your answer flows back down.

```
Touch Bar app (Swift)          ← shows context + actions; a tap writes
     ▲                           responses/<request_id>.json
State files                    ← ~/.claude-touchbar/state.json, responses/,
     ▲                           actions.jsonl, events.jsonl
Hook (touchbar_hook.py)        ← summarizes the request, rates its risk,
     ▲                           waits up to 20 s for a response
Claude Code PermissionRequest
```

For example, when Claude Code wants to create a file:

1. The hook writes `state.json` with the context `Create demo.md`, risk `medium` and the actions `Yes / All edits / No`.
2. The app sees the change immediately (it watches the directory, no polling) and pops up the bar.
3. You tap `All edits`. The app writes the response file; the hook returns `allow` plus the session-scoped `acceptEdits` permission to Claude Code.
4. The bar steps aside. If you do not tap within 20 seconds, Claude Code falls back to its normal on-screen prompt.

## When it triggers

The companion only sees requests that reach Claude Code's `PermissionRequest` hook, so it depends on the permission mode:

| Mode | Triggers the Touch Bar? | Notes |
| --- | --- | --- |
| **Default** | ✅ On approval requests | Write, Edit and Bash usually ask; routine project-local `Read` does not need to |
| **Accept Edits** | ⚠️ Partly | Write/Edit are auto-approved; Bash still asks |
| **Auto Mode** | ⚠️ Partly | Low-risk operations are auto-approved; uncertain ones still ask |
| **Bypass Permissions** | ❌ Never | Everything is auto-approved; the hook is never called |
| **Plan Mode** | ❌ Never | No tool calls, nothing to approve |

For daily use, keep the Touch Bar for side-effecting actions (`Write`, `Edit`, `Bash`, deletes). For testing or demos, temporarily add `permissions.ask: ["Read"]` to your local Claude Code settings so the `Read` flow is easy to reproduce, and remove it afterwards.

## Quick start

Requires a MacBook Pro with a physical Touch Bar, macOS 12 or later, Python 3 and a Swift 6 toolchain (Xcode or Command Line Tools).

1. Keep this project in your Claude Code workspace. The hook is registered in [.claude/settings.local.json](.claude/settings.local.json).
2. Build and run the Touch Bar app:

   ```bash
   cd app
   swift build
   .build/debug/TouchBarCompanion
   ```

   It lives in the menu bar as `CC`, with no Dock icon.
3. Trigger a Claude Code permission request and tap an action on the Touch Bar.

See [docs/APP_SETUP.md](docs/APP_SETUP.md) for details and [docs/HOOK_SETUP.md](docs/HOOK_SETUP.md) for hook behavior.

To check what happened:

```bash
python3 -m json.tool ~/.claude-touchbar/state.json        # current state
tail -n 1 ~/.claude-touchbar/actions.jsonl                # last tap
find ~/.claude-touchbar/responses -maxdepth 1 -type f     # response files
```

## Roadmap

- [x] **MVP**: hook flow with BetterTouchTool, risk-aware actions, session permissions
- [ ] **Phase 1: Native app**: Swift app replaces BetterTouchTool (done); full permission test matrix and a two-minute demo
- [ ] **Phase 2: Configurable**: Touch Bar buttons defined in a config file, with the safety rules enforced in code
- [ ] **Phase 3: Settings window**: SwiftUI editor for buttons with a live Touch Bar preview
- [ ] **Phase 4: Open-source distribution**: hook rewritten in Swift (no Python dependency), one-click hook install, Homebrew cask

Details are in [TODO.md](TODO.md).

## Tech stack

| Layer | Choice |
| --- | --- |
| Hook | Python 3, standard library only |
| Touch Bar app | Swift + AppKit, built with SwiftPM; undocumented system-modal Touch Bar APIs resolved at runtime |
| Communication | Local JSON files with atomic writes, no network |
| Tests | Swift Testing |
| Legacy renderer | BetterTouchTool widgets + `scripts/btt_*.py` ([docs/BTT_SETUP.md](docs/BTT_SETUP.md)) |

## Project structure

```text
.claude/hooks/touchbar_hook.py   # hook: writes state, returns the decision
.claude/hooks/touchbar-hook.sh   # hook shell wrapper
app/                             # native Swift Touch Bar app (SwiftPM)
docs/APP_SETUP.md                # Swift app setup
docs/HOOK_SETUP.md               # hook behavior and manual tests
docs/BTT_SETUP.md                # legacy: BetterTouchTool setup
scripts/                         # legacy: BetterTouchTool scripts and iTerm2 launcher
TODO.md                          # roadmap and checklist
```

## Non-goals

- Replacing Claude Code's own permission UI or bypassing its permission system
- Typing into the terminal or parsing the terminal TUI
- Managing multiple Claude Code sessions
