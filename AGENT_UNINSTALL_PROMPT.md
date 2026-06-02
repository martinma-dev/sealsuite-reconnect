# Agent Uninstall Prompt

Use this prompt with a local coding agent that can read web pages and run macOS
terminal commands.

```text
You are uninstalling SealSuite Reconnect Watcher from this Mac.

Goal:
- Fetch the uninstaller from GitHub.
- Unload the SealSuite Reconnect Watcher LaunchAgent.
- Remove the watcher plist.
- Verify the watcher service is no longer loaded.

Source:
- Prompt: https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/main/AGENT_UNINSTALL_PROMPT.md
- Alternate prompt URL: https://raw.githubusercontent.com/martinma-dev/sealsuite-reconnect/refs/heads/main/AGENT_UNINSTALL_PROMPT.md
- Repository: https://github.com/martinma-dev/sealsuite-reconnect
- Git clone URL: https://github.com/martinma-dev/sealsuite-reconnect.git
- Zip URL: https://github.com/martinma-dev/sealsuite-reconnect/archive/refs/heads/main.zip

Safety rules:
- Do not disconnect, quit, force-kill, or test-fail SealSuite/VPN.
- Do not delete /Applications/SealSuite.app.
- Do not delete or print /usr/local/corplink/rpc.conf.
- Do not delete /usr/local/corplink or other Corplink runtime files.
- Do not remove support files or logs unless the user explicitly asks for full cleanup.
- Do not modify unrelated files.
- If one raw prompt URL returns 404, try the alternate prompt URL before reporting an access problem.
- If the GitHub source cannot be fetched after retrying the alternate URL, stop and report the access problem.

Steps:
1. Confirm you are on macOS.
2. Fetch a fresh copy of the repository into a temporary directory:
   WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/sealsuite-reconnect.XXXXXX")"
   cd "$WORKDIR"
   if command -v git >/dev/null 2>&1 && git clone --depth 1 https://github.com/martinma-dev/sealsuite-reconnect.git sealsuite-reconnect; then
     cd sealsuite-reconnect
   else
     curl -fsSL --retry 3 -o sealsuite-reconnect.zip https://github.com/martinma-dev/sealsuite-reconnect/archive/refs/heads/main.zip
     unzip -q sealsuite-reconnect.zip
     cd sealsuite-reconnect-main
   fi
3. Confirm the directory contains uninstall.sh.
4. Run: zsh ./uninstall.sh
5. Verify both LaunchAgent labels are unloaded:
   for label in com.sealsuite.reconnect com.martin.sealsuite.reconnect; do
     if launchctl print "gui/$(id -u)/${label}" >/dev/null 2>&1; then
       printf 'loaded: %s\n' "$label"
     else
       printf 'unloaded: %s\n' "$label"
     fi
   done
6. Verify both plist files are absent:
   for plist in "$HOME/Library/LaunchAgents/com.sealsuite.reconnect.plist" "$HOME/Library/LaunchAgents/com.martin.sealsuite.reconnect.plist"; do
     if [[ -e "$plist" ]]; then
       printf 'present: %s\n' "$plist"
     else
       printf 'absent: %s\n' "$plist"
     fi
   done
7. Report:
   - Whether com.sealsuite.reconnect is unloaded.
   - Whether com.martin.sealsuite.reconnect is unloaded.
   - Whether both plist files are absent.
   - That support files and logs were intentionally preserved.

Expected behavior:
- The uninstaller removes only the watcher LaunchAgent plist.
- It preserves support files and logs under:
  "$HOME/Library/Application Support/SealSuiteReconnect"
  "$HOME/Library/Logs/SealSuiteReconnect"
- It does not disconnect or otherwise test the VPN.
```
