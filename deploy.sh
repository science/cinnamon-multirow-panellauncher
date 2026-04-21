#!/bin/bash
# Deploy current repo contents to the stable install of
# multirow-panel-launchers@cinnamon.
#
# Copies the repo into ~/.local/share/cinnamon/applets/<UUID>.stable/
# (creating it if needed) and points the Cinnamon applet symlink at
# that snapshot. Edits to the repo after deploy do NOT affect the
# running applet until the next deploy.
#
# Usage: ./deploy.sh

set -eo pipefail

UUID="multirow-panel-launchers@cinnamon"
APPLETS_DIR="$HOME/.local/share/cinnamon/applets"
APPLET_LINK="$APPLETS_DIR/$UUID"
STABLE_DIR="$APPLETS_DIR/$UUID.stable"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REQUIRED_FILES=(applet.js helpers.js metadata.json settings-schema.json)

echo "Deploying $UUID to stable..."
echo ""

# 1. Validate required files exist
MISSING=()
for f in "${REQUIRED_FILES[@]}"; do
    [ -f "$SCRIPT_DIR/$f" ] || MISSING+=("$f")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: Missing required files in repo: ${MISSING[*]}"
    exit 1
fi

# 2. Validate metadata UUID
META_UUID=$(python3 -c "import json; print(json.load(open('$SCRIPT_DIR/metadata.json'))['uuid'])" 2>/dev/null || echo "")
if [ "$META_UUID" != "$UUID" ]; then
    echo "ERROR: metadata.json uuid is '$META_UUID', expected '$UUID'"
    exit 1
fi
echo "  Metadata UUID: OK"

# 3. Rsync repo -> stable dir (excluding dev cruft)
mkdir -p "$STABLE_DIR"
rsync -a --delete \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='dist/' \
    --exclude='vm/' \
    --exclude='.claude/' \
    "$SCRIPT_DIR/" "$STABLE_DIR/"
echo "  Synced repo -> $STABLE_DIR"

# 4. Point the applet symlink at the stable dir
if [ -L "$APPLET_LINK" ]; then
    CURRENT=$(readlink -f "$APPLET_LINK")
    if [ "$CURRENT" != "$STABLE_DIR" ]; then
        rm "$APPLET_LINK"
        ln -s "$STABLE_DIR" "$APPLET_LINK"
        echo "  Switched symlink: $APPLET_LINK -> $STABLE_DIR"
    else
        echo "  Symlink already points at stable"
    fi
elif [ -e "$APPLET_LINK" ]; then
    echo "ERROR: $APPLET_LINK exists and is not a symlink. Remove it first:"
    echo "  rm -rf $APPLET_LINK"
    exit 1
else
    ln -s "$STABLE_DIR" "$APPLET_LINK"
    echo "  Created symlink: $APPLET_LINK -> $STABLE_DIR"
fi

echo ""
echo "Done. Restart Cinnamon to load the deployed version:"
echo "  - From desktop: Alt+F2 -> r -> Enter"
echo "  - From TTY:     DISPLAY=:0 cinnamon --replace &"
