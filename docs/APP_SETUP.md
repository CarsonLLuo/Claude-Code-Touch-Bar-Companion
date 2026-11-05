# Touch Bar Companion App Setup

Native Swift menu bar app that replaces BetterTouchTool as the Touch Bar renderer.
The hook (`.claude/hooks/touchbar_hook.py`) is unchanged; the app reads the same
`~/.claude-touchbar/state.json` and writes the same `responses/<request_id>.json`.

No keyboard injection is used.

## Requirements

- MacBook Pro with a physical Touch Bar
- macOS 12+
- Swift 6 toolchain (Xcode or Command Line Tools)

## Build and Run

```sh
cd app
swift build
.build/debug/TouchBarCompanion
```

The app runs in the menu bar (`CC`) with no Dock icon. Quit it from that menu.

Optional: put a square PNG at `~/.claude-touchbar/icon.png` to show it before the
context text (read at launch). The logo is not bundled in this repo.

## Behavior

- Idle: the regular Touch Bar stays as is; a `CC` button sits in the Control Strip.
- Permission request: the companion bar pops up automatically:

  ```text
  [x] [Context] [Action 1] [Action 2] [Action 3]
  ```

- Context is a white pill. Action colors follow meaning, not position: `Yes` green,
  session-wide allow (`All edits` / `Yes all session`) blue, `No` red, review actions gray.
- After a decision, timeout or expiry, the bar steps aside and the regular Touch Bar
  (including Esc) is back.
- Tap `CC` in the Control Strip to open the companion bar manually; tap `x` to close it.
- State changes are picked up immediately by watching `~/.claude-touchbar/`; no polling.
- A tap is ignored if the state on disk has moved on to another request since the
  button was drawn. High / unknown risk requests never accept an allow action.

## Plan Usage (5h / 7d)

There are two sources; both write the same files, and the app reads whichever is newest.

### Recommended: fetch from your Claude account (opt-in)

Turn on **Fetch Usage from Claude Account** in the `CC` menu bar menu. Every 5 minutes, and
when you tap the Control Strip item (at most every 30 seconds), the app calls
`https://api.anthropic.com/api/oauth/usage`, the endpoint behind Claude Code's `/usage`
command. Usage from the terminal, the desktop app and claude.ai all shows up, and
segments reflect when usage actually happened.

How it handles your credentials:

- It reads the Claude Code sign-in token from the login keychain
  (`Claude Code-credentials`) through `/usr/bin/security`, on every fetch, and only keeps it
  in memory for that request. Nothing token-related is written to disk or logs.
- It never refreshes the token. When it has expired, fetching pauses until Claude Code
  refreshes it (any Claude Code activity), and the Touch Bar goes gray as data ages.
- The endpoint is undocumented and may change without notice; the status line below keeps
  working as a fallback.

### Fallback: status line

Claude Code passes plan usage to its status line. `.claude/hooks/touchbar_statusline.py`
records it for the app and prints a short line in the terminal
(`5h 47% left · 7d 45% left · ctx 34%`). Register it in your Claude Code settings
(project `.claude/settings.local.json`, or `~/.claude/settings.json` to cover every project):

```json
"statusLine": {
  "type": "command",
  "command": "/absolute/path/to/claude-touchbar-companion/.claude/hooks/touchbar_statusline.py"
}
```

It writes `~/.claude-touchbar/usage.json` (latest snapshot) and
`~/.claude-touchbar/usage-history.jsonl` (changes over the last 8 days).

What the Touch Bar shows:

- Control Strip: the tighter window (`5h` or `7d`) with the charge left and a thin
  segmented battery. The number turns yellow / red as the window gets tight.
- Tap it: both windows as long batteries, with the charge left and when they reset
  (5h countdown, 7d weekday).
- Permission request: a red low-battery badge only when 5h has 10% or less left.

Each battery segment is a time slice (5h: 30 minutes, 7d: one day), colored by how much
was used in that slice compared with an even share: green at or under pace, yellow up to
1.5x, red above. The current slice has a white outline, slices not reached yet are dark,
and hatched slices had no snapshot. Everything turns gray when no update arrived for 30
minutes. A bolt means the 5h window refills within 15 minutes.

Limits:

- `rate_limits` is only sent for Pro / Max / Ultra subscriptions, after the session's first
  response. Without it the Control Strip shows `CC`.
- The status line only runs in terminal Claude Code sessions, and only while they are active.
  With only the status line, usage from claude.ai and the desktop app is booked into the next
  slice in which a terminal session records a snapshot.
- The first snapshot of a window is only a baseline unless it falls in the first slice: earlier
  slices stay hatched instead of pretending all prior usage happened just now.

## Testing With an Isolated State Directory

Both the hook and the app honor `CLAUDE_TOUCHBAR_DIR`:

```sh
CLAUDE_TOUCHBAR_DIR=/tmp/cc-tb-test app/.build/debug/TouchBarCompanion
```

Capture the Touch Bar for a quick visual check:

```sh
screencapture -x -b /tmp/touchbar.png
```

Unit tests:

```sh
cd app
swift test
```

## Notes

- Uses undocumented Touch Bar APIs (`presentSystemModalTouchBar`, `DFRElementSetControlStripPresenceForIdentifier`),
  resolved at runtime. Future macOS updates may break them.
- Not yet ported from the BTT setup: tapping the context item to launch Claude Code in iTerm2.
