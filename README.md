# Multi-Row Panel Launchers

A Cinnamon desktop applet that wraps panel launcher icons into multiple rows, making better use of tall panels.

Forked from the stock `panel-launchers@cinnamon.org` applet. Uses `Clutter.FlowLayout` (the same technique as [multirow-window-list](https://github.com/science/cinnamon-multirow-windowlist)) to wrap launcher icons into a 2D grid instead of a single row.

## Features

- **Multi-row wrapping**: Icons wrap into 1–4 rows based on available space
- **Auto-sizing**: Icons auto-scale to fit the panel height and row count
- **Manual override**: Optional icon size override (0–64px)
- **Drag and drop**: Reorder launchers within the 2D grid
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
4. Remove the stock "Panel launchers" applet
5. Restart Cinnamon: `Alt+F2` → `r` → Enter

## Configuration

Right-click the applet → Configure:

| Setting | Default | Description |
|---------|---------|-------------|
| Maximum rows | 2 | Number of rows for launcher icons (1–4) |
| Icon size override | 0 (auto) | Manual icon size in pixels (0 = auto-scale) |
| Allow dragging | On | Enable drag-and-drop reordering |

## Uninstallation

```bash
./uninstall.sh
```

Safe to run from a TTY if Cinnamon has crashed. Removes the applet from the enabled-applets dconf list and deletes the symlink.

## Development

### Running tests

```bash
npm test   # 77 tests across 4 test files
```

### Project structure

```
applet.js              # Main applet (GJS/Clutter/St)
helpers.js             # Pure functions (testable in Node.js)
metadata.json          # UUID, name, role
settings-schema.json   # Cinnamon settings schema
install.sh             # Install with validation
uninstall.sh           # Safe uninstall
test/
  helpers.test.js      # Unit tests for helper functions
  schema.test.js       # Metadata + settings validation
  applet-lint.test.js  # Static safety checks on applet.js
  install-uninstall.test.js  # Sandboxed integration tests
vm -> ../cinnamon-multirow-windowlist/vm  # Shared VM infra
```

## License

ISC
