# SealSuite Reconnect Watcher

Small macOS user LaunchAgent for SealSuite/Corplink. It checks SealSuite's
recorded tunnel once per minute. If the tunnel is missing/down for consecutive
checks, it wakes SealSuite/CorplinkNe and calls Corplink's local gRPC
`connectVpn`.

The package does not include any user token. At runtime it reads the local
Corplink RPC token from `/usr/local/corplink/rpc.conf`.

## Install With An Agent

Give the user's local agent this prompt:

```text
Please follow the instruction from https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/refs/heads/main/AGENT_INSTALL_PROMPT.md then install sealsuite-reconnect
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
"$HOME/Library/Application Support/SealSuiteReconnect/vpn-connect.json"
```

## Uninstall

```sh
zsh ./uninstall.sh
```

The uninstall script unloads the LaunchAgent and removes its plist. It preserves
support files and logs.
