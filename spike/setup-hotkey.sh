#!/bin/sh
# Bind window-organizer to global hotkeys using skhd - a small daemon whose only
# job is hotkeys. No Raycast, no GUI step beyond granting Accessibility once.
#
#   ./setup-hotkey.sh            set up the bindings
#   ./setup-hotkey.sh --remove   take them out again
#
# Safe to re-run: the bindings live inside a marked block that is replaced whole,
# so anything else in your skhdrc is left alone.

set -eu

BIN="$HOME/.local/bin/warrange"
CONF="$HOME/.config/skhd/skhdrc"
BEGIN="# >>> window-organizer >>>"
END="# <<< window-organizer <<<"

say()  { printf '%s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

# ---------- strip any previous block ----------

strip_block() {
    [ -f "$CONF" ] || return 0
    grep -qF "$BEGIN" "$CONF" || return 0
    tmp=$(mktemp)
    awk -v b="$BEGIN" -v e="$END" '
        $0 == b { skip = 1; next }
        $0 == e { skip = 0; next }
        !skip   { print }
    ' "$CONF" > "$tmp"
    mv "$tmp" "$CONF"
}

if [ "${1:-}" = "--remove" ]; then
    if [ -f "$CONF" ] && grep -qF "$BEGIN" "$CONF"; then
        strip_block
        command -v skhd >/dev/null 2>&1 && skhd --restart-service >/dev/null 2>&1 || true
        say "bindings removed from $CONF"
    else
        say "nothing to remove - no window-organizer block in $CONF"
    fi
    exit 0
fi

# ---------- prerequisites ----------

[ -x "$BIN" ] || fail "$BIN not found. Run ./install.sh first."

if ! command -v skhd >/dev/null 2>&1; then
    say "skhd is not installed. It is a ~1MB hotkey daemon and the only new dependency."
    if command -v brew >/dev/null 2>&1; then
        printf 'Install it with Homebrew now? [y/N] '
        read -r reply
        case "$reply" in
            [yY]*) brew install koekeishiya/formulae/skhd ;;
            *) fail "declined - install skhd yourself, or see the Automator note at the end of this script" ;;
        esac
    else
        fail "Homebrew not found. Install skhd manually: https://github.com/koekeishiya/skhd"
    fi
fi

# ---------- write the bindings ----------

mkdir -p "$(dirname "$CONF")"
[ -f "$CONF" ] || : > "$CONF"
strip_block

# cmd+alt is chosen deliberately: an existing AeroSpace config uses alt on its own
# for focus and workspace movement, so these will not collide if it is ever enabled.
cat >> "$CONF" <<EOF
$BEGIN
# Arrange every visible window with zero overlap; the app you are in takes the master pane.
cmd + alt - a : $BIN --master 0.6 --spill --apply

# Put everything back, including un-minimising whatever was stowed.
cmd + alt - z : $BIN --undo

# Arrange without a master pane - even columns instead.
cmd + alt - s : $BIN --spill --apply
$END
EOF

skhd --restart-service >/dev/null 2>&1 || skhd --start-service >/dev/null 2>&1 || true

# ---------- report ----------

say ""
say "bindings written to $CONF"
say ""
say "  cmd+alt+A   arrange (master pane)"
say "  cmd+alt+S   arrange (even columns)"
say "  cmd+alt+Z   undo"
say ""
say "One manual step remains, and the hotkeys do nothing silently without it:"
say "  System Settings > Privacy & Security > Accessibility > enable skhd"
say ""
say "macOS attributes the window moves to skhd, not to warrange, because skhd is the"
say "process that launches it. Granting warrange alone is not enough."
say ""
say "Check the daemon:  skhd --status"
say "Remove bindings:   ./setup-hotkey.sh --remove"
say ""

# ---------- zero-dependency alternative ----------
#
# If you would rather not run a daemon at all, macOS can do this natively:
#
#   1. Automator > New > Quick Action
#   2. "Workflow receives" -> no input, in any application
#   3. Add a "Run Shell Script" action containing:
#          $HOME/.local/bin/warrange --master 0.6 --spill --apply
#   4. Save as "Arrange Windows"
#   5. System Settings > Keyboard > Keyboard Shortcuts > Services >
#      General > Arrange Windows -> assign your key
#
# Same Accessibility caveat applies, granted to Automator/Finder instead of skhd.
# It is slower to fire (a few hundred ms) because macOS spins up a workflow host,
# which is why skhd is the default recommendation here.
