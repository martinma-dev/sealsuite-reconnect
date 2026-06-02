#!/bin/zsh
set -eu

LABEL="${SEALSUITE_RECONNECT_LABEL:-com.sealsuite.reconnect}"
LEGACY_LABELS=(com.martin.sealsuite.reconnect)
STATE_DIR="$HOME/Library/Application Support/SealSuiteReconnect"

unload_label() {
  local label="$1"
  local plist="$HOME/Library/LaunchAgents/${label}.plist"

  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  launchctl bootout "gui/$(id -u)/${label}" >/dev/null 2>&1 || true
  rm -f "$plist"
}

unload_label "$LABEL"
for legacy in "${LEGACY_LABELS[@]}"; do
  [[ "$legacy" == "$LABEL" ]] && continue
  unload_label "$legacy"
done

printf 'SealSuite Reconnect Watcher unloaded.\n'
printf 'Support files are preserved at: %s\n' "$STATE_DIR"
printf 'To disable without uninstalling later, create: %s/disabled\n' "$STATE_DIR"
