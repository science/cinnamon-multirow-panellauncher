# Multi-Row Panel Launchers — Cinnamon Applet

## Project

Cinnamon 6.0.4 desktop applet (forked from stock `panel-launchers@cinnamon.org`) that wraps launcher icons into multiple rows using `Clutter.FlowLayout`. Status: **Alpha**.

- **UUID**: `multirow-panel-launchers@cinnamon`
- **Target**: Cinnamon 6.0+ on Ubuntu 24.04

## Key Files

| File | Purpose |
|------|---------|
| `applet.js` | Main applet code (GJS/Clutter/St) |
| `helpers.js` | Pure computation functions (no GJS deps, testable in Node) |
| `metadata.json` | Applet UUID, name, role |
| `settings-schema.json` | User-configurable settings (max-rows, icon-size-override) |
| `install.sh` | Install with validation — checks files, Cinnamon version, creates symlink, warns about role conflicts |
| `uninstall.sh` | Safe removal — strips from dconf + deletes symlink. Works from TTY if Cinnamon crashed |
| `test/helpers.test.js` | Unit tests for helper functions |
| `test/schema.test.js` | Settings schema validation tests |
| `test/applet-lint.test.js` | Safety checks (cleanup, signals, FlowLayout, DND) |
| `test/install-uninstall.test.js` | Sandboxed install/uninstall integration tests |

## Commands

- **Run tests**: `npm test` (77 tests, Node.js 18+)
- **Install**: `./install.sh` (validates files, creates symlink, warns about stock applet conflict)
- **Uninstall**: `./uninstall.sh` (removes from dconf + deletes symlink; safe from TTY if Cinnamon crashed)
- **Restart Cinnamon**: `Alt+F2 → r → Enter` or from TTY: `DISPLAY=:0 cinnamon --replace &`
- **Applet dir**: `~/.local/share/cinnamon/applets/multirow-panel-launchers@cinnamon`
- **dconf key**: `/org/cinnamon/enabled-applets` (list of active applets)
- **Stock applet UUID**: `panel-launchers@cinnamon.org` (has same `panellauncher` role — only one should be active)

## Architecture

- `helpers.js` exports pure functions (`calcLauncherIconSize`, `calcNeededRows`, `calcGridDropIndex`) used by both `applet.js` and Node tests
- `applet.js` uses `require('./helpers')` for GJS, `module.exports` for Node — same file, dual runtime
- `LaunchersBox` uses `Clutter.Actor` + `Clutter.FlowLayout` for horizontal panels, `Clutter.BoxLayout` for vertical
- `_onAllocationChanged()` feeds allocation width to FlowLayout to trigger wrapping
- `min_width = 0` prevents panel zone squeeze (same fix as multirow-windowlist)
- DND uses Euclidean distance to child allocation centers for 2D grid reorder (internal only)
- `acceptNewLauncher()` supports Cinnamon menu's "Add to Panel" via the `panellauncher` role

## Known Constraints (Cinnamon 6.0.4)

- `this.actor.get_size()` returns inflated preferred size — use `get_allocation_box()` for actual width
- `on_applet_removed_from_panel()` must destroy all launchers + disconnect signals (prevents GC crashes)
- FlowLayout's `min_width` inflates to total content width — must override to 0

## VM Testing

A libvirt/KVM VM (`cinnamon-dev`) mirrors the host environment (Ubuntu 24.04 + Cinnamon 6.0.4). The host `~/dev` is mounted read-write at `/mnt/host-dev/` via virtio-fs — code changes are instantly visible to the VM.

### VM Management

```bash
./vm/vm-ctl.sh start          # Start VM
./vm/vm-ctl.sh stop           # Graceful shutdown
./vm/vm-ctl.sh ssh [cmd]      # SSH into VM
./vm/vm-ctl.sh viewer         # Open SPICE desktop viewer
./vm/vm-ctl.sh snapshot <n>   # Create snapshot
./vm/vm-ctl.sh revert <n>     # Revert to snapshot
```
