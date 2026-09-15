#!/bin/sh
# Build the tools and install them into ~/.local/bin.
#
# A hotkey must not depend on this checkout: the spike currently lives in a git
# worktree that gets deleted with the session. Installed binaries survive that.
set -e
cd "$(dirname "$0")"
./build.sh
mkdir -p "$HOME/.local/bin"
for t in wdump wprobe warrange wfocus; do
    install -m 755 "$t" "$HOME/.local/bin/$t"
done
echo "installed -> $HOME/.local/bin: wdump wprobe warrange wfocus"

# The focus recorder has to be running to be useful: relevance cannot be
# reconstructed at arrange time. It needs no permissions and records only window
# ids and timestamps. Opt in explicitly - it is a background process on your
# machine and you should have to ask for it.
PLIST="$HOME/Library/LaunchAgents/com.windoworganizer.wfocus.plist"

if [ "${1:-}" = "--uninstall-recorder" ]; then
    launchctl bootout "gui/$(id -u)/com.windoworganizer.wfocus" 2>/dev/null || true
    rm -f "$PLIST"
    echo "focus recorder stopped and removed"
    exit 0
fi

if [ "${1:-}" = "--with-recorder" ]; then
    mkdir -p "$(dirname "$PLIST")"
    cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.windoworganizer.wfocus</string>
    <key>ProgramArguments</key>
    <array><string>$HOME/.local/bin/wfocus</string></array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>StandardErrorPath</key><string>/tmp/wfocus.err.log</string>
</dict>
</plist>
PLISTEOF
    launchctl bootout "gui/$(id -u)/com.windoworganizer.wfocus" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST"
    echo "focus recorder running, and will start at login"
    echo "  inspect:  wfocus --status"
    echo "  the log:  ~/.window-spike/focus.jsonl   (window ids and timestamps only)"
    echo "  stop it:  ./install.sh --uninstall-recorder"
else
    echo ""
    echo "The focus recorder is NOT running. Without it every window scores equally"
    echo "and layout falls back to priority alone. Start it with:"
    echo "  ./install.sh --with-recorder"
fi
