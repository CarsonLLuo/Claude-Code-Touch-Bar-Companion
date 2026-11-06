#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Pass arguments through (`question` mode) and keep the exit code: the background question
# hook exits 2 to wake Claude with the user's Touch Bar choice.
if command -v python3 >/dev/null 2>&1; then
  exec python3 "$SCRIPT_DIR/touchbar_hook.py" "$@"
fi

exit 0
