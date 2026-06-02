# Agent Install Prompt

Use this prompt with a local coding agent that can read this folder and run
macOS terminal commands.

```text
You are installing SealSuite Reconnect Watcher on this Mac.

Goal:
- Install the files from the current bundle directory.
- Register a user LaunchAgent that runs every 60 seconds after login.
- Verify status without intentionally disconnecting SealSuite.

Safety rules:
- Do not disconnect, quit, or force-kill SealSuite unless the user explicitly asks.
- Do not print or copy the contents of /usr/local/corplink/rpc.conf.
- Do not modify unrelated files.
- If Node.js is missing, stop and tell the user to install Node.js LTS first.

Steps:
1. Confirm you are on macOS and the current directory contains install.sh plus files/sealsuite-grpc.js.
2. Run: zsh ./install.sh
3. If launchctl bootstrap fails because an existing service is already loaded, run:
   launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.sealsuite.reconnect.plist"
   Then rerun: zsh ./install.sh
4. Run:
   "$HOME/Library/Application Support/SealSuiteReconnect/status.sh"
5. Report:
   - Whether launchd is loaded.
   - Whether the tunnel is currently healthy.
   - Whether Corplink RPC status is readable.
   - The log path: "$HOME/Library/Logs/SealSuiteReconnect/reconnect.log"

Expected behavior:
- The watcher is a user LaunchAgent, so it starts after the user logs in.
- It is not a constantly running daemon; launchd runs it every 60 seconds.
- If the SealSuite tunnel is down for consecutive checks, it wakes SealSuite/CorplinkNe and calls local Corplink connectVpn.
- Manual status checks must not flap or reconnect the VPN.
```
