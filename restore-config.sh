#!/bin/bash
# restore-config.sh — Restore panel launcher config after a Cinnamon ID change
#
# Reads panel-launchers-backup.json (written by the applet on every settings
# change) and merges its values into whatever instance ID Cinnamon is currently
# using. Run this after a panel reset, applet re-add, or on a new machine.
#
# Usage:
#   ./restore-config.sh              # restore from backup
#   ./restore-config.sh --dry-run    # show what would change without writing

set -eo pipefail

UUID="multirow-panel-launchers@cinnamon"
SPICES_DIR="$HOME/.config/cinnamon/spices/$UUID"
BACKUP_FILE="$SPICES_DIR/panel-launchers-backup.json"
DRY_RUN=false

[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

# Check dependencies
for cmd in jq dconf; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: $cmd is required but not installed." >&2
        exit 1
    fi
done

# Check backup file exists
if [[ ! -f "$BACKUP_FILE" ]]; then
    echo "Error: No backup file found at $BACKUP_FILE" >&2
    echo "The applet creates this file automatically when you change settings." >&2
    exit 1
fi

echo "Backup file: $BACKUP_FILE"
echo ""

# Find current instance ID from dconf enabled-applets
ENABLED=$(dconf read /org/cinnamon/enabled-applets)
if [[ -z "$ENABLED" ]]; then
    echo "Error: Could not read /org/cinnamon/enabled-applets from dconf" >&2
    exit 1
fi

# Extract instance ID for our UUID — format is 'panel:location:position:UUID:ID'
INSTANCE_ID=$(echo "$ENABLED" | grep -oP "${UUID}:\K[0-9]+" | head -1)
if [[ -z "$INSTANCE_ID" ]]; then
    echo "Error: $UUID is not in enabled-applets. Is the applet added to a panel?" >&2
    exit 1
fi

INSTANCE_FILE="$SPICES_DIR/${INSTANCE_ID}.json"
echo "Current instance: $INSTANCE_ID ($INSTANCE_FILE)"

# Check if instance file exists
if [[ ! -f "$INSTANCE_FILE" ]]; then
    echo "Error: Instance file $INSTANCE_FILE does not exist." >&2
    echo "Cinnamon may not have created it yet. Try restarting Cinnamon first." >&2
    exit 1
fi

# Read backup values
LAUNCHER_LIST=$(jq -c '.launcherList' "$BACKUP_FILE")
MAX_ROWS=$(jq '."max-rows"' "$BACKUP_FILE")
ICON_SIZE=$(jq '."icon-size-override"' "$BACKUP_FILE")
MAX_WIDTH=$(jq '."max-width"' "$BACKUP_FILE")
ALLOW_DRAG=$(jq '."allow-dragging"' "$BACKUP_FILE")

echo ""
echo "Backup contains:"
echo "  launchers:    $(echo "$LAUNCHER_LIST" | jq -r 'length') apps"
echo "  max-rows:     $MAX_ROWS"
echo "  icon-size:    $ICON_SIZE"
echo "  max-width:    $MAX_WIDTH"
echo "  allow-drag:   $ALLOW_DRAG"

# Show current instance values for comparison
CURRENT_COUNT=$(jq '.launcherList.value | length' "$INSTANCE_FILE")
echo ""
echo "Current instance has: $CURRENT_COUNT launchers"

if $DRY_RUN; then
    echo ""
    echo "[dry-run] Would write backup values into $INSTANCE_FILE"
    echo "[dry-run] No changes made."
    exit 0
fi

# Merge backup values into instance file
jq --argjson launchers "$LAUNCHER_LIST" \
   --argjson maxrows "$MAX_ROWS" \
   --argjson iconsize "$ICON_SIZE" \
   --argjson maxwidth "$MAX_WIDTH" \
   --argjson allowdrag "$ALLOW_DRAG" \
   '.launcherList.value = $launchers |
    ."max-rows".value = $maxrows |
    ."icon-size-override".value = $iconsize |
    ."max-width".value = $maxwidth |
    ."allow-dragging".value = $allowdrag' \
   "$INSTANCE_FILE" > "${INSTANCE_FILE}.tmp" \
   && mv "${INSTANCE_FILE}.tmp" "$INSTANCE_FILE"

echo ""
echo "Restored backup into $INSTANCE_FILE"
echo ""
echo "Restart Cinnamon to apply: Alt+F2 → r → Enter"
