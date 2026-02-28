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
| `settings-schema.json` | User-configurable settings (max-rows, icon-size-override, max-width) |
| `install.sh` | Install with validation — checks files, Cinnamon version, creates symlink, warns about role conflicts |
| `uninstall.sh` | Safe removal — strips from dconf + deletes symlink. Works from TTY if Cinnamon crashed |
| `test/helpers.test.js` | Unit tests for helper functions (56 tests) |
| `test/schema.test.js` | Settings schema validation tests (10 tests) |
| `test/applet-lint.test.js` | Safety checks: cleanup, signals, FlowLayout, DND, hover, overflow, backup (44 tests) |
| `test/install-uninstall.test.js` | Sandboxed install/uninstall integration tests (20 tests) |
| `restore-config.sh` | Restore launcher config after Cinnamon ID change (reads backup, merges into current instance) |

## Commands

- **Run tests**: `npm test` (148 tests, Node.js 18+)
- **Install**: `./install.sh` (validates files, creates symlink, warns about stock applet conflict)
- **Uninstall**: `./uninstall.sh` (removes from dconf + deletes symlink; safe from TTY if Cinnamon crashed)
- **Restore config**: `./restore-config.sh` (after panel reset; `--dry-run` to preview)
- **Restart Cinnamon**: `Alt+F2 → r → Enter` or from TTY: `DISPLAY=:0 cinnamon --replace &`
- **Applet dir**: `~/.local/share/cinnamon/applets/multirow-panel-launchers@cinnamon`
- **dconf key**: `/org/cinnamon/enabled-applets` (list of active applets)
- **Stock applet UUID**: `panel-launchers@cinnamon.org` (has same `panellauncher` role — only one should be active)

## Architecture

- `helpers.js` exports pure functions (`calcLauncherIconSize`, `calcNeededRows`, `calcContainerWidth`, `calcVisibleLauncherCount`, `calcGridDropIndex`) used by both `applet.js` and Node tests
- `applet.js` uses `require('./helpers')` for GJS, `module.exports` for Node — same file, dual runtime
- `LaunchersBox` uses `Clutter.Actor` + `Clutter.FlowLayout` for horizontal panels, `Clutter.BoxLayout` for vertical
- `_onAllocationChanged()` feeds allocation width to FlowLayout to trigger wrapping
- `min_width = 0` prevents panel zone squeeze (same fix as multirow-windowlist)
- DND uses Euclidean distance to child allocation centers for 2D grid reorder (internal only)
- `acceptNewLauncher()` supports Cinnamon menu's "Add to Panel" via the `panellauncher` role
- Overflow popup: `St.Bin` on `global.stage` with `pushModal`/`popModal` for input routing; chevron is child of `this.actor` (applet-box), separate from FlowLayout/DND
- Hover/click feedback: `_connectHoverFeedback` applies inline styles via enter/leave/button-press/button-release events on ALL launchers

## Known Constraints (Cinnamon 6.0.4)

- `this.actor.get_size()` returns inflated preferred size — use `get_allocation_box()` for actual width
- `on_applet_removed_from_panel()` must destroy all launchers + disconnect signals (prevents GC crashes)
- FlowLayout's `min_width` inflates to total content width — must override to 0
- Overlay actors on `Main.uiGroup` are occluded by `global.top_window_group` in Clutter's pick pass — floating UI that needs hover/click must be placed on `global.stage` directly
- `launcher.actor` uses `important: true` — theme CSS overrides stylesheet.css, so hover effects must use inline `set_style()` rather than CSS pseudo-classes

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

### Restarting Cinnamon on the VM

```bash
# Must set DISPLAY — ssh sessions don't have it
./vm/vm-ctl.sh ssh "DISPLAY=:0 nohup cinnamon --replace >/tmp/cinnamon.log 2>&1 &"
sleep 3  # wait for startup
```

Check it's running: `./vm/vm-ctl.sh ssh "pgrep -x cinnamon"`

### Panel index

The panel is keyed by ID, not zero-indexed. Check which key:
```bash
./vm/vm-ctl.sh ssh "DISPLAY=:0 dbus-send ... Eval string:'Object.keys(Main.panelManager.panels)'"
# Returns e.g. "1" — use panels[1], not panels[0]
```

### D-Bus Eval (Looking Glass remotely)

Query live applet state via the Cinnamon Eval D-Bus interface:

```bash
./vm/vm-ctl.sh ssh "DISPLAY=:0 dbus-send --session --dest=org.Cinnamon \
  --type=method_call --print-reply /org/Cinnamon org.Cinnamon.Eval \
  string:'<javascript expression>'"
```

**Return format**: `boolean true/false` + `string "result"`. `true` means eval succeeded. Use `try { ... } catch(e) { String(e) }` to catch errors — unhandled exceptions return `false` + `"{}"`.

**Tips**:
- Always wrap in `try/catch` — bare property access on undefined returns `false` + `"{}"`
- Use `String(value)` for the final expression (not `JSON.stringify` — it fails on GObject types)
- Multi-statement evals: separate with semicolons, last expression is the return value

**Finding the applet instance**:
```js
let p = Main.panelManager.panels[1];
let app = p._leftBox.get_children()[2]._delegate;
// Verify: app._uuid === "multirow-panel-launchers@cinnamon"
```

**Useful queries**:
```js
// Launcher count and overflow state
app._launchers.length + " launchers, overflow=" + app._overflowPanelOpen

// Screen coordinates of a launcher (for xdotool targeting)
let alloc = Cinnamon.util_get_transformed_allocation(app._launchers[0].actor);
Math.round((alloc.x1 + alloc.x2) / 2) + "," + Math.round((alloc.y1 + alloc.y2) / 2)

// Check if hover feedback is connected
app._launchers[0].actor._hoverFeedbackIds ? true : false

// Check inline style during hover
app._launchers[1].actor.get_style() || "(none)"
```

### xdotool — Simulating Mouse Input

xdotool works for testing hover, click, and keyboard events on the VM. **Must set DISPLAY**.

```bash
./vm/vm-ctl.sh ssh "export DISPLAY=:0; xdotool mousemove 85 769"
./vm/vm-ctl.sh ssh "export DISPLAY=:0; xdotool click 1"              # left click
./vm/vm-ctl.sh ssh "export DISPLAY=:0; xdotool mousedown 1"          # hold button
./vm/vm-ctl.sh ssh "export DISPLAY=:0; xdotool mouseup 1"            # release
./vm/vm-ctl.sh ssh "export DISPLAY=:0; xdotool key Escape"           # key press
```

**Important caveats**:
- xdotool uses `XWarpPointer` which doesn't always generate MotionNotify events for pure Clutter actors. It works reliably for panel chrome (which has X11 input regions) and when `pushModal` is active (FULLSCREEN mode routes all X11 events through Clutter).
- For overflow popup testing: open the popup first (which activates pushModal), then xdotool hover/click works on popup children.
- Always move away first (`xdotool mousemove 400 400`) before moving to target, to ensure enter/leave events fire.

### Taking Screenshots

Use ImageMagick `import` on the VM, then pipe back via ssh:

```bash
# Full screenshot
./vm/vm-ctl.sh ssh "export DISPLAY=:0; import -window root /tmp/screenshot.png"

# Crop a region (width x height + x_offset + y_offset)
./vm/vm-ctl.sh ssh "convert /tmp/screenshot.png -crop 160x80+30+745 /tmp/cropped.png"

# Copy to host (scp won't work if key auth isn't set up — use cat pipe)
./vm/vm-ctl.sh ssh "cat /tmp/cropped.png" > /tmp/cropped.png
```

### Combined Test Pattern: Move + Verify + Screenshot

The most effective VM test pattern combines xdotool input, D-Bus state verification, and screenshot capture:

```bash
./vm/vm-ctl.sh ssh "export DISPLAY=:0; \
  xdotool mousemove 400 400; sleep 0.3; \
  xdotool mousemove 85 769; sleep 0.5; \
  dbus-send --session --dest=org.Cinnamon --type=method_call --print-reply \
    /org/Cinnamon org.Cinnamon.Eval string:'
try {
    let p = Main.panelManager.panels[1];
    let app = p._leftBox.get_children()[2]._delegate;
    let l = app._launchers[1];
    \"hover=\" + l.actor.hover + \", style=\" + (l.actor.get_style() || \"none\");
} catch(e) { String(e); }
'"
```

This pattern: (1) moves cursor away to reset state, (2) moves to target, (3) queries live hover + style via D-Bus. Add `import -window root` before the D-Bus query to capture a screenshot of the visual state.

### Disabling VM Screensaver

The screensaver auto-locks during testing. Disable both:
```bash
./vm/vm-ctl.sh ssh "DISPLAY=:0 dconf write /org/cinnamon/desktop/screensaver/lock-enabled false"
./vm/vm-ctl.sh ssh "DISPLAY=:0 dconf write /org/cinnamon/desktop/screensaver/idle-activation-enabled false"
```
