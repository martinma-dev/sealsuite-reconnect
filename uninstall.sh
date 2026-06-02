#!/bin/zsh
set -eu

LABEL="${SEALSUITE_RECONNECT_LABEL:-com.sealsuite.reconnect}"
PLIST="$HOME/Library/LaunchAgents/${LABEL}.plist"
STATE_DIR="$HOME/Library/Application Support/SealSuiteReconnect"

launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
rm -f "$PLIST"

printf 'SealSuite Reconnect Watcher unloaded.\n'
printf 'Support files are preserved at: %s\n' "$STATE_DIR"
printf 'To disable without uninstalling later, create: %s/disabled\n' "$STATE_DIR"
