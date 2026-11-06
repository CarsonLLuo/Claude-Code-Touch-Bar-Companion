<div align="center">

# Claude Code Touch Bar Companion

**Answer Claude Code permission requests and watch your plan usage from the MacBook Pro Touch Bar**

When Claude Code asks to edit a file or run a command, the request shows up on the Touch Bar as a short summary with a few buttons. One tap sends the answer back through Claude Code's own hooks. You never have to switch to the terminal, and no keystrokes are injected. The rest of the time, a small battery in the Control Strip shows how much of your 5-hour and weekly limits is left.

![status](https://img.shields.io/badge/status-MVP-orange?style=flat-square)
![platform](https://img.shields.io/badge/platform-macOS_Touch_Bar-black?style=flat-square&logo=apple)
![app](https://img.shields.io/badge/app-Swift-F05138?style=flat-square&logo=swift&logoColor=white)
![integration](https://img.shields.io/badge/integration-Claude_Code_hooks-D97706?style=flat-square)

[Design principles](#design-principles) · [How it works](#how-it-works) · [Plan usage](#plan-usage) · [Quick start](#quick-start) · [Roadmap](#roadmap)

English | [简体中文](./README.zh-CN.md)

</div>

---

> **Status: the MVP works end to end** with real Claude Code permission requests, and plan usage (5h / 7d) is shown from real account data. The Touch Bar is rendered by a native Swift menu bar app; the original BetterTouchTool setup is kept as a legacy option.

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
4. **Out of the way.** The companion bar pops up only when a request needs an answer, then steps aside so the regular Touch Bar (including Esc) comes back. Permission requests may interrupt you; usage never does.
5. **Never act on stale state.** Every request gets a fresh `request_id`; a tap is ignored if the request has changed since the button was drawn.
6. **Local by default.** State, responses and logs live in `~/.claude-touchbar/`. Logs redact prompts, assistant messages and file contents. The only network request is the opt-in usage fetch to Anthropic's own API.

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
| Claude desktop's next-step question (end of turn) | `Commit and push this change?` | `提交并推送 / 先不提交 / On screen` |
| Nothing pending | `CC Ready` | none |

A choice on a next-step question is passed back to Claude as feedback and the turn continues; the Touch Bar waits 20 seconds, and a click on the screen meanwhile is queued until then, so tap `On screen` to answer there right away. See [docs/HOOK_SETUP.md](docs/HOOK_SETUP.md#next-step-questions-claude-desktop).

The context item is a white, display-only pill, optionally prefixed by an icon from `~/.claude-touchbar/icon.png`. Actions are colored by meaning: `Yes` green, session-wide allow blue, `No` red, review actions gray.

## Plan usage

Your plan's 5-hour and weekly (7-day) limits are shown as batteries: the number is the charge **left**, not what you have used.

![Control Strip: 5h with 47% left over a segmented battery](image/README/usage-control-strip.png)

![After tapping it: 5h and 7d batteries with the charge left and when they reset](image/README/usage-on-demand.png)

*Top: the Control Strip. Bottom: after tapping it. Captured on a real Touch Bar with example data.*

| Tier | Where | What you see |
| --- | --- | --- |
| Ambient | Control Strip, always visible | The tighter window, e.g. `5h 57` over a thin segmented battery; the number turns yellow, then red, as it runs low |
| On demand | Tap the Control Strip item | Both windows as long batteries, with the time until 5h resets and the weekday 7d resets |
| Interrupt | On a permission request | Nothing, unless 5h has 10% or less left: then a red low-battery badge |

The tighter window is the one closer to trouble. 7d counts as tight when it is low or when you are using it faster than the week is passing; on a tie, 5h wins because it decides the next few hours.

Each battery is split into time slices, like F1 minisectors: 10 slices of 30 minutes for 5h, 7 slices of one day for 7d. Each slice is colored by how much was used in it compared with an even share:

| Slice | Meaning |
| --- | --- |
| Green | At or under pace |
| Yellow | Up to 1.5× pace |
| Red | Over 1.5× pace |
| White outline | The current slice |
| Dark | Not reached yet |
| Hatched | Not recorded, e.g. before the app started or while the Mac was asleep |

The whole battery turns gray when no update has arrived for 30 minutes, and a bolt appears when 5h refills within 15 minutes.

**Where the numbers come from.** The usage API only reports the current totals, so the app records a snapshot every 5 minutes and builds the slices from the differences. There are two sources, both writing the same files:

- **Your Claude account (recommended, opt-in).** Turn on *Fetch Usage from Claude Account* in the `CC` menu bar menu. The app calls the endpoint behind Claude Code's `/usage` command, so usage from the terminal, the desktop app and claude.ai all counts. It reads Claude Code's sign-in token from the keychain on each fetch, keeps it in memory for that one request, and never refreshes it. The endpoint is undocumented and may change.
- **Claude Code status line (fallback).** [`touchbar_statusline.py`](.claude/hooks/touchbar_statusline.py) records the `rate_limits` Claude Code passes to its status line. It only runs in terminal sessions, not in the desktop app.

Usage data is only available on Pro, Max and Ultra plans. See [docs/APP_SETUP.md](docs/APP_SETUP.md#plan-usage-5h--7d) for setup details and limits.

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

   It lives in the menu bar as `CC`, with no Dock icon. To keep it running in the background and start it at login, use `scripts/install-launch-agent.sh` instead (see [docs/APP_SETUP.md](docs/APP_SETUP.md#run-in-the-background-recommended)).
3. Trigger a Claude Code permission request and tap an action on the Touch Bar.
4. Optional: turn on *Fetch Usage from Claude Account* in the `CC` menu to see your plan usage.

See [docs/APP_SETUP.md](docs/APP_SETUP.md) for details and [docs/HOOK_SETUP.md](docs/HOOK_SETUP.md) for hook behavior.

To check what happened:

```bash
python3 -m json.tool ~/.claude-touchbar/state.json        # current state
tail -n 1 ~/.claude-touchbar/actions.jsonl                # last tap
find ~/.claude-touchbar/responses -maxdepth 1 -type f     # response files
```

## Roadmap

- [x] **MVP**: hook flow with BetterTouchTool, risk-aware actions, session permissions
- [ ] **Phase 1: Native app**: Swift app replaces BetterTouchTool and passes the permission test matrix (done); two-minute demo rehearsal
- [ ] **Phase 2: Usage and mascot**: plan usage as segmented batteries (done); an animated character that follows Claude Code's state
- [ ] **Phase 3: Configurable**: Touch Bar buttons defined in a config file, with the safety rules enforced in code
- [ ] **Phase 4: Settings window**: SwiftUI editor for buttons with a live Touch Bar preview
- [ ] **Phase 5: Open-source distribution**: hook rewritten in Swift (no Python dependency), one-click hook install, Homebrew cask (launch at login is already available via a LaunchAgent script)

Details are in [TODO.md](TODO.md).

## Tech stack

| Layer | Choice |
| --- | --- |
| Hook | Python 3, standard library only |
| Touch Bar app | Swift + AppKit, built with SwiftPM; undocumented system-modal Touch Bar APIs resolved at runtime |
| Communication | Local JSON files with atomic writes |
| Usage data | Opt-in fetch from `api.anthropic.com/api/oauth/usage`; Claude Code status line as fallback |
| Tests | Swift Testing |
| Legacy renderer | BetterTouchTool widgets + `scripts/btt_*.py` ([docs/BTT_SETUP.md](docs/BTT_SETUP.md)) |

## Project structure

```text
.claude/hooks/touchbar_hook.py   # hook: writes state, returns the decision
.claude/hooks/touchbar-hook.sh   # hook shell wrapper
.claude/hooks/touchbar_statusline.py  # status line: records plan usage (fallback source)
app/                             # native Swift Touch Bar app (SwiftPM)
docs/APP_SETUP.md                # Swift app setup
docs/HOOK_SETUP.md               # hook behavior and manual tests
docs/BTT_SETUP.md                # legacy: BetterTouchTool setup
scripts/install-launch-agent.sh  # run the app in the background, start at login
scripts/                         # legacy: BetterTouchTool scripts and iTerm2 launcher
TODO.md                          # roadmap and checklist
```

## Non-goals

- Replacing Claude Code's own permission UI or bypassing its permission system
- Typing into the terminal or parsing the terminal TUI
- Managing multiple Claude Code sessions
