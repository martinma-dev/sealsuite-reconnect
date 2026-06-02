#!/bin/zsh
set -eu

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin:/opt/homebrew/bin

LABEL="${SEALSUITE_RECONNECT_LABEL:-com.sealsuite.reconnect}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$SCRIPT_DIR/files"
STATE_DIR="$HOME/Library/Application Support/SealSuiteReconnect"
LOG_DIR="$HOME/Library/Logs/SealSuiteReconnect"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
PLIST="$LAUNCH_AGENTS_DIR/${LABEL}.plist"
DRY_RUN=0

if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
fi

say() {
  printf '%s\n' "$*"
}

run() {
  if (( DRY_RUN )); then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
  else
    "$@"
  fi
}

find_node() {
  emulate -L zsh
  setopt null_glob
  local candidate=""
  node_supported() {
    "$1" -e 'process.exit(Number(process.versions.node.split(".")[0]) >= 14 ? 0 : 1)' >/dev/null 2>&1
  }
  for candidate in \
    "$HOME"/.nvm/versions/node/*/bin/node \
    "$HOME"/.volta/bin/node \
    "$HOME"/.asdf/shims/node \
    "$HOME"/.local/share/mise/shims/node \
    "$HOME"/.nodenv/shims/node \
    /opt/homebrew/bin/node \
    /usr/local/bin/node \
    /usr/bin/node; do
    if [[ -x "$candidate" ]] && node_supported "$candidate"; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

require_file() {
  if [[ ! -r "$1" ]]; then
    say "missing required file: $1"
    exit 1
  fi
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  say "This installer is for macOS only."
  exit 1
fi

require_file "$SRC_DIR/sealsuite-reconnect.sh"
require_file "$SRC_DIR/sealsuite-grpc.js"
require_file "$SRC_DIR/status.sh"
require_file "$SRC_DIR/vpn-connect.json"

NODE_BIN="$(find_node || true)"
if [[ -z "$NODE_BIN" ]]; then
  say "Node.js was not found. Install Node.js LTS first, then rerun this installer."
  say "Common options: Homebrew node, nvm, Volta, asdf, mise, or nodenv."
  exit 1
fi

if [[ ! -d "/Applications/SealSuite.app" ]]; then
  say "warning: /Applications/SealSuite.app was not found."
  say "Install SealSuite first, then this watcher can reconnect it automatically."
fi

if [[ ! -r "/usr/local/corplink/rpc.conf" ]]; then
  say "warning: /usr/local/corplink/rpc.conf is not readable yet."
  say "Open SealSuite and sign in once before expecting reconnect to work."
fi

say "Installing SealSuite Reconnect Watcher..."
say "  label: $LABEL"
say "  node:  $NODE_BIN"

run mkdir -p "$STATE_DIR" "$LOG_DIR" "$LAUNCH_AGENTS_DIR"
run install -m 755 "$SRC_DIR/sealsuite-reconnect.sh" "$STATE_DIR/sealsuite-reconnect.sh"
run install -m 755 "$SRC_DIR/sealsuite-grpc.js" "$STATE_DIR/sealsuite-grpc.js"
run install -m 755 "$SRC_DIR/status.sh" "$STATE_DIR/status.sh"

if [[ ! -e "$STATE_DIR/vpn-connect.json" ]]; then
  run install -m 644 "$SRC_DIR/vpn-connect.json" "$STATE_DIR/vpn-connect.json"
else
  say "Preserving existing reconnect config: $STATE_DIR/vpn-connect.json"
fi

if (( DRY_RUN )); then
  say "+ write plist $PLIST"
else
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/zsh</string>
    <string>${STATE_DIR}/sealsuite-reconnect.sh</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>EnvironmentVariables</key>
  <dict>
    <key>SEALSUITE_RECONNECT_LABEL</key>
    <string>${LABEL}</string>
  </dict>
  <key>StandardOutPath</key>
  <string>${LOG_DIR}/launchd.out.log</string>
  <key>StandardErrorPath</key>
  <string>${LOG_DIR}/launchd.err.log</string>
</dict>
</plist>
EOF
fi

if (( ! DRY_RUN )); then
  plutil -lint "$PLIST" >/dev/null
  launchctl bootout "gui/$(id -u)" "$PLIST" >/dev/null 2>&1 || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST"
  launchctl enable "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  "$STATE_DIR/status.sh" || true
fi

say "Done."
say "Status: \"$STATE_DIR/status.sh\""
say "Logs:   tail -f \"$LOG_DIR/reconnect.log\""
