#!/bin/bash

set -euo pipefail

PROJECT_DIR="${CLAUDE_TOUCHBAR_PROJECT_DIR:-/Users/carson/Desktop/code/claude-touchbar-companion}"
CLAUDE_CMD="${CLAUDE_TOUCHBAR_CLAUDE_CMD:-claude}"

osascript - "$PROJECT_DIR" "$CLAUDE_CMD" <<'APPLESCRIPT'
on run argv
  set projectDir to item 1 of argv
  set claudeCommand to item 2 of argv

  tell application "iTerm2"
    activate
    set newWindow to (create window with default profile)
    tell current session of newWindow
      write text "cd " & quoted form of projectDir & " && " & claudeCommand
    end tell
  end tell
end run
APPLESCRIPT
