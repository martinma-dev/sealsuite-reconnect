# Agent Install Prompt

Use this prompt with a local coding agent that can read web pages and run macOS
terminal commands.

```text
You are installing SealSuite Reconnect Watcher on this Mac.

Goal:
- Fetch the installer from GitHub.
- Install the files locally.
- Register a user LaunchAgent that runs every 60 seconds after login.
- Verify status without intentionally disconnecting SealSuite.

Source:
- Prompt: https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/main/AGENT_INSTALL_PROMPT.md
- Alternate prompt URL: https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/refs/heads/main/AGENT_INSTALL_PROMPT.md
- Repository: https://github.com/martinma-dev/sealsuite-reconnect
- Git clone URL: https://github.com/martinma-dev/sealsuite-reconnect.git
- Zip URL: https://github.com/martinma-dev/sealsuite-reconnect/archive/refs/heads/main.zip

Safety rules:
- Do not disconnect, quit, or force-kill SealSuite unless the user explicitly asks.
- Do not print or copy the contents of /usr/local/corplink/rpc.conf.
- Do not call connectVpn manually and do not run reconnect tests by simulating a down VPN.
- Do not modify unrelated files.
- If one raw prompt URL returns 404, try the alternate prompt URL before reporting an access problem.
- If the GitHub source cannot be fetched after retrying the alternate URL, stop and report the access problem.
- If Node.js is missing, stop and tell the user to install Node.js LTS first.

Steps:
1. Confirm you are on macOS.
2. Fetch a fresh copy of the repository into a temporary directory:
   WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/sealsuite-reconnect.XXXXXX")"
   cd "$WORKDIR"
   if command -v git >/dev/null 2>&1; then
     git clone --depth 1 https://github.com/martinma-dev/sealsuite-reconnect.git
     cd sealsuite-reconnect
   else
     curl -fsSL --retry 3 -o sealsuite-reconnect.zip https://github.com/martinma-dev/sealsuite-reconnect/archive/refs/heads/main.zip
     unzip -q sealsuite-reconnect.zip
     cd sealsuite-reconnect-main
   fi
3. Confirm the directory contains install.sh plus files/sealsuite-grpc.js.
4. Run: zsh ./install.sh
5. Run:
   "$HOME/Library/Application Support/SealSuiteReconnect/status.sh"
6. Report:
   - Whether launchd is loaded.
   - The LaunchAgent label. It should be com.sealsuite.reconnect.
   - Whether the tunnel is currently healthy.
   - Whether Corplink RPC status is readable.
   - The log path: "$HOME/Library/Logs/SealSuiteReconnect/reconnect.log"

Expected behavior:
- The watcher is a user LaunchAgent, so it starts after the user logs in.
- It is not a constantly running daemon; launchd runs it every 60 seconds.
- If the SealSuite tunnel is down for consecutive checks, it wakes SealSuite/CorplinkNe and calls local Corplink connectVpn.
- Manual status checks must not flap or reconnect the VPN.
- The installer can replace an older SealSuite reconnect LaunchAgent and preserves the local vpn-connect.json config.
```
