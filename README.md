# SealSuite Reconnect Watcher

Small macOS user LaunchAgent for SealSuite/Corplink. It checks SealSuite's
recorded tunnel once per minute. If the tunnel is missing/down for consecutive
checks, it wakes the background Corplink agent and calls Corplink's local gRPC
`connectVpn`. By default it also restarts/activates the SealSuite UI during
recovery so the visible app state reloads against the backend tunnel state.

The package does not include any user token. At runtime it reads the local
Corplink RPC token from `/usr/local/corplink/rpc.conf`.

## Install With An Agent

Give the user's local agent this prompt:

```text
Please read and follow the installation instructions at https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/main/AGENT_INSTALL_PROMPT.md, then install sealsuite-reconnect on this Mac. Use that document as the source of truth and report the final installation status.
```

This is the recommended prompt-script flow: the raw prompt tells the agent how
to fetch the installer, how to avoid destructive VPN tests, and how to verify
the result.

## Manual Install

```sh
git clone https://github.com/martinma-dev/sealsuite-reconnect.git
cd sealsuite-reconnect
zsh ./install.sh
```

The installer writes:

- `~/Library/Application Support/SealSuiteReconnect/sealsuite-reconnect.sh`
- `~/Library/Application Support/SealSuiteReconnect/sealsuite-grpc.js`
- `~/Library/Application Support/SealSuiteReconnect/status.sh`
- `~/Library/Application Support/SealSuiteReconnect/vpn-connect.json`
- `~/Library/LaunchAgents/com.sealsuite.reconnect.plist`

## Requirements

- macOS
- SealSuite installed in `/Applications/SealSuite.app`
- SealSuite signed in at least once
- Node.js 14+ available through nvm, Volta, asdf, mise, nodenv, Homebrew, or a
  standard node path

## Useful Commands

```sh
"$HOME/Library/Application Support/SealSuiteReconnect/status.sh"
tail -f "$HOME/Library/Logs/SealSuiteReconnect/reconnect.log"
touch "$HOME/Library/Application Support/SealSuiteReconnect/disabled"
rm "$HOME/Library/Application Support/SealSuiteReconnect/disabled"
```

## Behavior Options

The watcher keeps the UI consistent by default:

- `SEALSUITE_RECONNECT_WAKE_GUI=1`: restart/activate the SealSuite UI during recovery.
- `SEALSUITE_RECONNECT_NOTIFY=1`: send macOS notifications for reconnect attempts and outcomes.

To keep reconnect recovery fully in the background, reinstall with:

```sh
SEALSUITE_RECONNECT_WAKE_GUI=0 zsh ./install.sh
```

To disable macOS notifications, reinstall with:

```sh
SEALSUITE_RECONNECT_NOTIFY=0 zsh ./install.sh
```

## Reconnect Config

Default config:

```json
{
  "server": -1,
  "mode": "Split"
}
```

Edit:

```sh
open -e "$HOME/Library/Application Support/SealSuiteReconnect/vpn-connect.json"
```

## Uninstall

Give the user's local agent this prompt:

```text
Please read and follow the uninstall instructions at https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/main/AGENT_UNINSTALL_PROMPT.md, then uninstall sealsuite-reconnect from this Mac. Use that document as the source of truth and report the final uninstall status.
```

Manual uninstall:

```sh
zsh ./uninstall.sh
```

The uninstall script unloads the LaunchAgent and removes its plist. It preserves
support files and logs.
