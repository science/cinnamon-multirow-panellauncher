# Multi-Row Panel Launchers

A Cinnamon desktop applet that wraps panel launcher icons into multiple rows, making better use of tall panels.

Forked from the stock `panel-launchers@cinnamon.org` applet. Uses `Clutter.FlowLayout` (the same technique as [multirow-window-list](https://github.com/science/cinnamon-multirow-windowlist)) to wrap launcher icons into a 2D grid instead of a single row.

## Features

- **Multi-row wrapping**: Icons wrap into 1–4 rows based on available space
- **Auto-sizing**: Icons auto-scale to fit the panel height and row count
- **Manual override**: Optional icon size override (0–64px)
- **Max width cap**: Limit the launcher area width — excess icons overflow into a popup
- **Overflow popup**: When max-width is set and there are too many launchers to fit, a chevron button appears. Click it to open a popup grid with the remaining launchers.
- **Hover/click feedback**: All launcher icons (both in the panel and overflow popup) show visual feedback on hover (border highlight) and click (background tint)
- **Drag and drop**: Reorder launchers within the 2D grid (panel and overflow popup)
- **"Add to Panel"**: Works with Cinnamon menu's right-click "Add to Panel" feature
- **Vertical panel support**: Falls back to standard vertical layout

## Requirements

- Cinnamon 6.0+ (tested on 6.0.4)
- Ubuntu 24.04 or similar

## Installation

```bash
git clone https://github.com/science/cinnamon-multirow-panellauncher.git
cd cinnamon-multirow-panellauncher
./install.sh
```

The install script validates files, checks your Cinnamon version, creates a symlink, and warns if the stock panel-launchers applet is still active (both claim the `panellauncher` role — only one should be enabled at a time).

After installing:
1. Right-click the panel → Applets
2. Search for "Multi-Row Panel Launchers"
3. Add it to your panel
4. Remove the stock "Panel launchers" applet if present
5. Restart Cinnamon: `Alt+F2` → `r` → Enter

## Configuration

Right-click the applet → Configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum rows | 2 | Number of rows for launcher icons (1–4) |
| Icon size override | 0 (auto) | Manual icon size in pixels (0 = auto-scale to row height) |
| Max width | 0 (no limit) | Maximum width for launcher area in pixels. When set, excess launchers appear in an overflow popup. |
| Allow dragging | On | Enable drag-and-drop reordering |

**Tips:**
- Set **max-width** to constrain how much panel space the launchers use. A chevron appears when icons overflow, opening a popup grid on click.
- Set **max rows = 1** for a single-row layout that matches the stock applet but adds overflow support.
- **Icon size override = 0** (the default) auto-scales icons to `floor(panelHeight / rows) - 4` pixels. Override for a fixed size.
- The applet's runtime config (launcher list + settings) is stored at `~/.config/cinnamon/spices/multirow-panel-launchers@cinnamon/<panel-id>.json`. Back this up if you want to preserve your launcher list across reinstalls.

## Uninstallation

```bash
./uninstall.sh
```

Safe to run from a TTY if Cinnamon has crashed. Removes the applet from the enabled-applets dconf list and deletes the symlink.

## Development

### Running tests

```bash
npm test   # 148 tests across 4 test files
```

Tests cover helper function math, settings schema validation, static safety checks on applet.js (cleanup, signals, metadata, FlowLayout, DND, hover feedback, overflow architecture), and sandboxed install/uninstall integration.

### Project structure

```
applet.js              # Main applet (GJS/Clutter/St)
helpers.js             # Pure functions (testable in Node.js)
metadata.json          # UUID, name, role
settings-schema.json   # Cinnamon settings schema
stylesheet.css         # CSS (hover uses inline styles due to important:true)
icon.png               # Applet icon (128x128, square)
install.sh             # Install with validation
uninstall.sh           # Safe uninstall
build-spices.sh        # Build Spices-compatible package for submission
test/
  helpers.test.js      # Unit tests for helper functions (70 tests)
  schema.test.js       # Metadata + settings validation (11 tests)
  applet-lint.test.js  # Static safety checks on applet.js (47 tests)
  install-uninstall.test.js  # Sandboxed integration tests (20 tests)
```

## Publishing to Cinnamon Spices

This applet can be submitted to the [Cinnamon Spices](https://cinnamon-spices.linuxmint.com/applets) marketplace, making it installable from Cinnamon's built-in System Settings > Applets > Download tab.

To build a Spices-compatible package:

```bash
./build-spices.sh
```

This creates `dist/multirow-panel-launchers@cinnamon/` with the nested `files/UUID/` layout that the Spices monorepo requires. Copy that directory into your fork of [linuxmint/cinnamon-spices-applets](https://github.com/linuxmint/cinnamon-spices-applets) and open a PR.

Before submitting, you'll need a `screenshot.png` at the repo root showing the applet on a panel. The build script will include it automatically if present.

## License

ISC
