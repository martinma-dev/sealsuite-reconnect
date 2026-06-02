#!/bin/zsh
set -u

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin

STATE_DIR="$HOME/Library/Application Support/SealSuiteReconnect"
VPN_CONF="/usr/local/corplink/vpn.conf"
LOG_FILE="$HOME/Library/Logs/SealSuiteReconnect/reconnect.log"
GRPC_HELPER="$STATE_DIR/sealsuite-grpc.js"
LAUNCHD_LABEL="${SEALSUITE_RECONNECT_LABEL:-com.sealsuite.reconnect}"
LEGACY_LABELS=(com.martin.sealsuite.reconnect)

tun="$(plutil -extract TunName raw -o - "$VPN_CONF" 2>/dev/null || true)"
state="$(cat "$STATE_DIR/state" 2>/dev/null || printf 0)"

printf 'SealSuite reconnect watcher\n'
printf '  launchd: '
loaded_labels=""
labels_to_check=("$LAUNCHD_LABEL" "${LEGACY_LABELS[@]}")
for label in "${labels_to_check[@]}"; do
  [[ "$loaded_labels" == *"$label"* ]] && continue
  if launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1; then
    display_label="$label"
    [[ "$label" != "$LAUNCHD_LABEL" ]] && display_label="${label} legacy"
    [[ -n "$loaded_labels" ]] && loaded_labels="${loaded_labels}, "
    loaded_labels="${loaded_labels}${display_label}"
  fi
done
[[ -n "$loaded_labels" ]] && printf 'loaded (%s)\n' "$loaded_labels" || printf 'not loaded\n'
printf '  disabled: %s\n' "$([[ -e "$STATE_DIR/disabled" ]] && printf yes || printf no)"
printf '  tunnel: %s\n' "${tun:-unknown}"
if [[ -n "$tun" ]]; then
  ifconfig "$tun" 2>/dev/null | sed 's/^/    /' || true
fi
printf '  failure_count: %s\n' "$state"
printf '  corplink_rpc:\n'
node_bin=""
setopt null_glob
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
    node_bin="$candidate"
    break
  fi
done
if [[ -n "$node_bin" && -r "$GRPC_HELPER" ]]; then
  "$node_bin" "$GRPC_HELPER" status 2>&1 | sed 's/^/    /' || true
else
  printf '    unavailable: node or grpc helper missing\n'
fi
printf '  recent watcher log:\n'
tail -n 12 "$LOG_FILE" 2>/dev/null | sed 's/^/    /' || true
