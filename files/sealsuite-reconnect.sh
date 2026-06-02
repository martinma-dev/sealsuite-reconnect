#!/bin/zsh
set -u

PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin

APP_BIN="/Applications/SealSuite.app/Contents/MacOS/SealSuite"
AGENT_BIN="/Applications/SealSuite.app/Contents/Frameworks/CorplinkNe.app/Contents/MacOS/CorplinkNe"
VPN_CONF="/usr/local/corplink/vpn.conf"
CORPLINK_LOG="/usr/local/corplink/logs/corplink.log"

STATE_DIR="$HOME/Library/Application Support/SealSuiteReconnect"
LOG_DIR="$HOME/Library/Logs/SealSuiteReconnect"
LOG_FILE="$LOG_DIR/reconnect.log"
STATE_FILE="$STATE_DIR/state"
DISABLED_FILE="$STATE_DIR/disabled"
LAST_RECOVER_FILE="$STATE_DIR/last-recover"
GRPC_HELPER="$STATE_DIR/sealsuite-grpc.js"
LOCK_DIR="/tmp/sealsuite-reconnect.lock"

FAIL_THRESHOLD=2
COOLDOWN_SECONDS=180

mkdir -p "$STATE_DIR" "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

with_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    exit 0
  fi
  trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT INT TERM
}

read_tun_name() {
  local tun=""
  if [[ -r "$VPN_CONF" ]]; then
    tun="$(plutil -extract TunName raw -o - "$VPN_CONF" 2>/dev/null || true)"
    if [[ -z "$tun" ]]; then
      tun="$(sed -n 's/.*"TunName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$VPN_CONF" 2>/dev/null | head -n 1)"
    fi
  fi
  printf '%s' "$tun"
}

tunnel_is_up() {
  local tun="$1"
  local info=""
  [[ -n "$tun" ]] || return 1
  info="$(ifconfig "$tun" 2>/dev/null || true)"
  [[ "$info" == *"<UP,"* || "$info" == *",UP,"* ]] || return 1
  [[ "$info" == *"RUNNING"* ]] || return 1
  [[ "$info" == *$'\n\tinet '* || "$info" == *$'\n\tinet6 '* ]]
}

recent_wireguard_activity() {
  local now=0
  local modified=0
  [[ -r "$CORPLINK_LOG" ]] || return 1
  now="$(date +%s)"
  modified="$(stat -f %m "$CORPLINK_LOG" 2>/dev/null || printf 0)"
  (( now - modified <= 180 )) || return 1
  tail -n 240 "$CORPLINK_LOG" 2>/dev/null | grep -Eq 'Receiving keepalive packet|WireGuardHandshakeComplete|reportVpnStatus success'
}

failure_count() {
  [[ -r "$STATE_FILE" ]] && cat "$STATE_FILE" || printf 0
}

set_failure_count() {
  printf '%s' "$1" > "$STATE_FILE"
}

in_cooldown() {
  local now=0
  local last=0
  [[ -r "$LAST_RECOVER_FILE" ]] || return 1
  now="$(date +%s)"
  last="$(cat "$LAST_RECOVER_FILE" 2>/dev/null || printf 0)"
  (( now - last < COOLDOWN_SECONDS ))
}

mark_recovered() {
  date +%s > "$LAST_RECOVER_FILE"
}

ensure_processes_running() {
  if ! pgrep -x SealSuite >/dev/null 2>&1 && [[ -x "$APP_BIN" ]]; then
    log "starting SealSuite process"
    "$APP_BIN" >/dev/null 2>&1 &
  fi

  if ! pgrep -x CorplinkNe >/dev/null 2>&1 && [[ -x "$AGENT_BIN" ]]; then
    log "starting CorplinkNe process"
    "$AGENT_BIN" >/dev/null 2>&1 &
  fi
}

node_bin() {
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

connect_vpn_rpc() {
  local node=""
  node="$(node_bin || true)"

  if [[ -z "$node" ]]; then
    log "connectVpn skipped: node binary not found"
    return 1
  fi

  if [[ ! -r "$GRPC_HELPER" ]]; then
    log "connectVpn skipped: grpc helper missing"
    return 1
  fi

  log "calling connectVpn through local Corplink RPC"
  "$node" "$GRPC_HELPER" connect-default --force >> "$LOG_FILE" 2>&1
  local code=$?
  log "connectVpn rpc exit_code=${code}"
  return "$code"
}

recover() {
  local uid=""
  local tun_after=""
  uid="$(id -u)"

  ensure_processes_running

  # Prefer launchd-managed restarts when available. These only run after the
  # tunnel is already confirmed absent, so they should not interrupt a live VPN.
  launchctl kickstart -k "gui/${uid}/com.volcengine.corplink.agent" >/dev/null 2>&1 || true
  launchctl kickstart -k "gui/${uid}/SealSuite" >/dev/null 2>&1 || true

  sleep 2
  connect_vpn_rpc || true

  sleep 5
  tun_after="$(read_tun_name)"
  if tunnel_is_up "$tun_after"; then
    log "recovery confirmed tun=${tun_after}"
  else
    log "recovery attempted; tunnel still down tun=${tun_after:-unknown}"
  fi

  mark_recovered
  set_failure_count 0
}

main() {
  with_lock

  if [[ -e "$DISABLED_FILE" ]]; then
    log "disabled marker present; skipping"
    exit 0
  fi

  local tun=""
  local count=0

  tun="$(read_tun_name)"

  if tunnel_is_up "$tun"; then
    set_failure_count 0
    if recent_wireguard_activity; then
      log "healthy tun=${tun}"
    else
      log "healthy tun=${tun}; recent WireGuard activity not observed"
    fi
    exit 0
  fi

  count="$(failure_count)"
  [[ "$count" =~ '^[0-9]+$' ]] || count=0
  count=$((count + 1))
  set_failure_count "$count"
  log "tunnel down or missing tun=${tun:-unknown} failure_count=${count}/${FAIL_THRESHOLD}"

  if (( count < FAIL_THRESHOLD )); then
    ensure_processes_running
    exit 0
  fi

  if in_cooldown; then
    log "cooldown active; recovery skipped"
    exit 0
  fi

  log "recovery triggered"
  recover
}

main "$@"
