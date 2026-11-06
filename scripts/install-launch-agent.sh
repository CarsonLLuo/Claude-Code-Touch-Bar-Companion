#!/bin/bash
# Keep the Touch Bar Companion running in the background, independent of any Claude session.
#
#   scripts/install-launch-agent.sh            build, install and start (also use after code changes)
#   scripts/install-launch-agent.sh uninstall  stop and remove
#
# Installs a LaunchAgent that starts the app at login and restarts it if it crashes.
# Quitting it from the CC menu keeps it quit until the next login.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABEL="com.claude-touchbar-companion"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
# Outside Desktop / Documents: launchd jobs can be blocked from reading those folders.
INSTALL_DIR="$HOME/Library/Application Support/ClaudeTouchBarCompanion"
BIN="$INSTALL_DIR/TouchBarCompanion"
LOG="$HOME/.claude-touchbar/app.log"
DOMAIN="gui/$(id -u)"

stop() {
  launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
  # bootout returns before the job is fully gone; bootstrapping too early fails with error 5.
  for _ in $(seq 1 50); do
    launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1 || return 0
    sleep 0.1
  done
}

case "${1:-install}" in
  install)
    (cd "$ROOT/app" && swift build -c release)
    stop
    mkdir -p "$INSTALL_DIR" "$HOME/Library/LaunchAgents" "$(dirname "$LOG")"
    cp "$ROOT/app/.build/release/TouchBarCompanion" "$BIN"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <dict>
    <key>SuccessfulExit</key>
    <false/>
  </dict>
  <key>LimitLoadToSessionType</key>
  <string>Aqua</string>
  <key>ProcessType</key>
  <string>Interactive</string>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
EOF
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed and started: $LABEL"
    echo "Log: $LOG"
    ;;
  uninstall)
    stop
    rm -f "$PLIST" "$BIN"
    rmdir "$INSTALL_DIR" 2>/dev/null || true
    echo "Removed: $LABEL"
    ;;
  *)
    echo "usage: $0 [install|uninstall]" >&2
    exit 2
    ;;
esac
