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
