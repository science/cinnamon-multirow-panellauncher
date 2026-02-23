#!/bin/bash
# Uninstall multirow-panel-launchers@cinnamon applet
#
# Safe to run from a TTY if Cinnamon has crashed.
# Removes the applet from dconf and deletes the symlink/directory.
# Does NOT require a running GUI — only needs dconf and a shell.
#
# Usage: ./uninstall.sh

set -eo pipefail

UUID="multirow-panel-launchers@cinnamon"
STOCK_UUID="panel-launchers@cinnamon.org"
APPLET_DIR="$HOME/.local/share/cinnamon/applets/$UUID"

echo "Uninstalling $UUID..."
echo ""

# 1. Check if dconf is available (needed for enabled-applets)
if ! command -v dconf &>/dev/null; then
    echo "WARNING: dconf not found. Skipping enabled-applets cleanup."
    echo "  You may need to manually edit enabled-applets after Cinnamon restarts."
else
    # 2. Remove from dconf enabled-applets list
    CURRENT=$(dconf read /org/cinnamon/enabled-applets 2>/dev/null || echo "")
    if echo "$CURRENT" | grep -q "$UUID"; then
        UPDATED=$(echo "$CURRENT" | python3 -c "
import sys, ast
raw = sys.stdin.read().strip()
entries = ast.literal_eval(raw)
filtered = [e for e in entries if '$UUID' not in e]
print(filtered)
")
        dconf write /org/cinnamon/enabled-applets "$UPDATED"
        echo "  Removed from enabled-applets"
    else
        echo "  Not in enabled-applets (already disabled)"
    fi

    # 3. Check if stock panel-launchers is present — warn if not
    CURRENT=$(dconf read /org/cinnamon/enabled-applets 2>/dev/null || echo "")
    if ! echo "$CURRENT" | grep -q "$STOCK_UUID"; then
        echo ""
        echo "WARNING: Stock panel-launchers ($STOCK_UUID) is not enabled."
        echo "  You will have no panel launchers after restart."
        echo "  To restore the stock one, run:"
        echo "    Right-click panel -> Applets -> search 'Panel launchers' -> Add"
        echo "  Or from a TTY, re-add it manually with dconf."
    fi
fi

# 4. Remove applet files/symlink
if [ -L "$APPLET_DIR" ]; then
    rm "$APPLET_DIR"
    echo "  Removed symlink: $APPLET_DIR"
elif [ -d "$APPLET_DIR" ]; then
    rm -rf "$APPLET_DIR"
    echo "  Removed directory: $APPLET_DIR"
else
    echo "  No applet directory found (already removed)"
fi

echo ""
echo "Done. Restart Cinnamon to apply:"
echo "  - From desktop: Alt+F2 -> r -> Enter"
echo "  - From TTY:     DISPLAY=:0 cinnamon --replace &"
