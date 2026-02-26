#!/bin/bash
# Build a Cinnamon Spices-compatible directory for submission to
# https://github.com/linuxmint/cinnamon-spices-applets
#
# Creates: dist/<UUID>/
#   info.json             (website metadata)
#   screenshot.png        (applet screenshot — must exist at repo root)
#   README.md             (documentation)
#   files/<UUID>/         (installable applet files)
#     applet.js
#     helpers.js
#     metadata.json
#     settings-schema.json
#     stylesheet.css
#     icon.png
#
# Usage: ./build-spices.sh [--author <github-username>]
#
# After building, copy dist/<UUID>/ into your fork of cinnamon-spices-applets
# and open a PR.

set -eo pipefail

UUID="multirow-panel-launchers@cinnamon"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$SCRIPT_DIR/dist/$UUID"

# Default author — override with --author flag
AUTHOR="science"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --author) AUTHOR="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Applet source files to include in the installable package
APPLET_FILES=(applet.js helpers.js metadata.json settings-schema.json stylesheet.css icon.png)

echo "Building Spices package for $UUID..."
echo "  Author: $AUTHOR"
echo ""

# 1. Validate source files exist
MISSING=()
for f in "${APPLET_FILES[@]}"; do
    if [ ! -f "$SCRIPT_DIR/$f" ]; then
        MISSING+=("$f")
    fi
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "ERROR: Missing required files: ${MISSING[*]}"
    exit 1
fi
echo "  Source files: OK"

# 2. Validate icon.png is square
if command -v identify &>/dev/null; then
    DIMS=$(identify -format "%wx%h" "$SCRIPT_DIR/icon.png" 2>/dev/null || echo "")
    W=$(echo "$DIMS" | cut -dx -f1)
    H=$(echo "$DIMS" | cut -dx -f2)
    if [ "$W" != "$H" ]; then
        echo "ERROR: icon.png must be square (got ${W}x${H})"
        exit 1
    fi
    echo "  icon.png: ${W}x${H} (square OK)"
else
    echo "  icon.png: skipping dimension check (install imagemagick for validation)"
fi

# 3. Validate metadata.json has no forbidden fields
for field in icon dangerous last-edited; do
    if python3 -c "import json,sys; d=json.load(open('$SCRIPT_DIR/metadata.json')); sys.exit(0 if '$field' not in d else 1)" 2>/dev/null; then
        :
    else
        echo "ERROR: metadata.json contains forbidden field '$field'"
        exit 1
    fi
done
echo "  metadata.json: no forbidden fields"

# 4. Check screenshot.png exists
if [ ! -f "$SCRIPT_DIR/screenshot.png" ]; then
    echo ""
    echo "WARNING: screenshot.png not found at repo root."
    echo "  Take a screenshot of the applet on a panel and save it as screenshot.png"
    echo "  The Spices website uses this as the listing preview."
    echo "  Continuing without it..."
    echo ""
    HAS_SCREENSHOT=false
else
    echo "  screenshot.png: OK"
    HAS_SCREENSHOT=true
fi

# 5. Clean and create dist directory
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/files/$UUID"

# 6. Copy applet files into files/UUID/
for f in "${APPLET_FILES[@]}"; do
    cp "$SCRIPT_DIR/$f" "$DIST_DIR/files/$UUID/$f"
done
echo "  Copied applet files to dist/$UUID/files/$UUID/"

# 7. Create info.json (website metadata)
cat > "$DIST_DIR/info.json" <<EOF
{
    "author": "$AUTHOR"
}
EOF
echo "  Created info.json (author: $AUTHOR)"

# 8. Copy README.md
cp "$SCRIPT_DIR/README.md" "$DIST_DIR/README.md"
echo "  Copied README.md"

# 9. Copy screenshot.png if it exists
if [ "$HAS_SCREENSHOT" = true ]; then
    cp "$SCRIPT_DIR/screenshot.png" "$DIST_DIR/screenshot.png"
    echo "  Copied screenshot.png"
fi

# 10. Verify the files/ directory contains ONLY the UUID subdirectory
EXTRA_FILES=$(find "$DIST_DIR/files" -maxdepth 1 -not -name "files" -not -name "$UUID" 2>/dev/null || true)
if [ -n "$EXTRA_FILES" ]; then
    echo "ERROR: files/ directory contains unexpected entries: $EXTRA_FILES"
    exit 1
fi
echo "  files/ directory: clean (UUID only)"

echo ""
echo "Build complete: dist/$UUID/"
echo ""
echo "Contents:"
find "$DIST_DIR" -type f | sort | sed "s|$DIST_DIR/||" | sed 's/^/  /'
echo ""
echo "Next steps:"
echo "  1. Fork https://github.com/linuxmint/cinnamon-spices-applets"
echo "  2. Copy dist/$UUID/ into the root of your fork"
echo "  3. Run: ./validate-spice $UUID"
echo "  4. Commit and open a PR titled: $UUID: Initial submission"
