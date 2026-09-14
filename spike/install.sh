#!/bin/sh
# Build the tools and install them into ~/.local/bin.
#
# A hotkey must not depend on this checkout: the spike currently lives in a git
# worktree that gets deleted with the session. Installed binaries survive that.
set -e
cd "$(dirname "$0")"
./build.sh
mkdir -p "$HOME/.local/bin"
for t in wdump wprobe warrange; do
    install -m 755 "$t" "$HOME/.local/bin/$t"
done
echo "installed -> $HOME/.local/bin: wdump wprobe warrange"
