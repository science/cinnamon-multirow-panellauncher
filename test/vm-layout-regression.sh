#!/bin/bash
# Behavioral regression test for MRPL layout cascade bug.
#
# The bug (WIP regression): with production config
# (override=16, max-rows=3, max-width=180, 14 launchers), the layout starves:
# _getCellWidth returns the 0 sentinel → _updateContainerWidth bails → myactor
# has no explicit width → FlowLayout allocates children at h≈4 → _updateIconSize
# ratchets the icon down to 1px. Result: dot-sized launchers in the panel.
#
# This test asserts the live runtime state after Cinnamon loads with that
# exact production config. It should FAIL against the WIP code and PASS
# after the fix.
#
# Runs directly on the VM (uses dbus-send, no SSH). Invoke with:
#   ./test/vm-layout-regression.sh

set -eo pipefail

UUID="multirow-panel-launchers@cinnamon"
GREEN='\033[0;32m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

PASS=0
FAIL=0

cinnamon_eval() {
    # Runs a one-liner JS via Cinnamon D-Bus Eval. Echoes the returned string.
    # Cinnamon wraps the returned string in an extra pair of quotes, so strip
    # both the dbus-send quotes and the inner JSON-ish quotes.
    DISPLAY=:0 dbus-send --session --dest=org.Cinnamon --type=method_call \
        --print-reply /org/Cinnamon org.Cinnamon.Eval string:"$1" 2>&1 \
        | sed -n 's/^ *string "\(.*\)"$/\1/p' | tail -1 \
        | sed -e 's/^"//' -e 's/"$//'
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        echo -e "  ${GREEN}PASS${NC} $label  (got: $actual)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label  expected=$expected, got=$actual"
        FAIL=$((FAIL + 1))
    fi
}

assert_ge() {
    local label="$1" threshold="$2" actual="$3"
    if [[ "$actual" =~ ^-?[0-9]+$ ]] && (( actual >= threshold )); then
        echo -e "  ${GREEN}PASS${NC} $label  (got: $actual, threshold: ≥$threshold)"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}FAIL${NC} $label  expected ≥$threshold, got=$actual"
        FAIL=$((FAIL + 1))
    fi
}

echo -e "${CYAN}=== MRPL layout regression test — production config ===${NC}"
echo ""

# Sanity: applet loaded?
uuid=$(cinnamon_eval 'try { String(imports.ui.appletManager.get_role_provider("panellauncher")._uuid); } catch(e) { String(e); }')
assert_eq "applet is loaded and holds panellauncher role" "$UUID" "$uuid"

# Capture state
probe='try { let app = imports.ui.appletManager.get_role_provider("panellauncher"); let l = app._launchers[0]; let alloc = app.myactor.get_allocation_box(); "icon_size="+app.icon_size+",launchers="+app._launchers.length+",myW="+(alloc.x2-alloc.x1)+",myH="+(alloc.y2-alloc.y1)+",natH="+l.actor.get_preferred_height(-1)[1]+",iconSize0="+l.icon.icon_size+",launcherH="+l.actor.height; } catch(e) { String(e); }'
state=$(cinnamon_eval "$probe")
echo -e "${CYAN}Runtime state:${NC} $state"

# Parse
icon_size=$(echo "$state" | grep -oP 'icon_size=\K[0-9]+')
launchers=$(echo "$state" | grep -oP 'launchers=\K[0-9]+')
myW=$(echo "$state" | grep -oP 'myW=\K[0-9]+')
myH=$(echo "$state" | grep -oP 'myH=\K[0-9]+')
natH=$(echo "$state" | grep -oP 'natH=\K[0-9]+')
iconSize0=$(echo "$state" | grep -oP 'iconSize0=\K[0-9]+')
launcherH=$(echo "$state" | grep -oP 'launcherH=\K[0-9]+')

echo ""
echo -e "${CYAN}Assertions:${NC}"

# The applet-level icon_size is set by _recalcIconSize: override=16, but
# capped so 3 rows of (icon + padding) fit in the panel. On a 48px VM panel
# that's ~13px; on a 60px+ panel it's 16px. The important assertion is that
# icons render at least as large as the auto-size floor (12px), never below.
assert_ge "app.icon_size is at or above 12px floor" "12" "$icon_size"
if (( icon_size <= 16 )); then
    echo -e "  ${GREEN}PASS${NC} app.icon_size is ≤ override (16)  (got: $icon_size — capped to fit if lower)"
    PASS=$((PASS + 1))
else
    echo -e "  ${RED}FAIL${NC} app.icon_size exceeds override (16)  got=$icon_size"
    FAIL=$((FAIL + 1))
fi

assert_ge "at least one launcher loaded" "1" "$launchers"

# Container width: production expects 5 cols × cellW at icon_size=16 with
# themed padding. 4 cols minimum (something big enough that 14 icons ÷ 3 rows
# = 5 cols works). Starved state gives myW < 50.
assert_ge "myactor.width is not starved (≥ 3 × icon_size)" "$((16 * 3))" "$myW"

# Container height: should be panel-like (48). Starved gives myH=4–16.
assert_ge "myactor.height is panel-like (≥ 40)" "40" "$myH"

# CRITICAL: icon's rendered size matches app.icon_size (no runaway clamping).
assert_eq "launcher icon.icon_size matches app.icon_size (not clamped down)" "$icon_size" "$iconSize0"

# Launcher height: should be at least icon_size (typically icon_size + padding).
# Starved state gives launcherH=4.
assert_ge "launcher actor.height is at least icon_size" "$icon_size" "$launcherH"

# Grid shape: launchers × max-rows must produce ceil(N/maxRows) cols and
# at most maxRows rows. Compute expected from runtime config so the test
# travels across host (15 launchers) and VM (14 launchers) configs.
shape_probe='try { let app = imports.ui.appletManager.get_role_provider("panellauncher"); let rows = {}; let cols = new Set(); app._launchers.forEach(l => { let b = l.actor.get_allocation_box(); let row = Math.round(b.y1); let col = Math.round(b.x1); rows[row] = (rows[row] || 0) + 1; cols.add(col); }); "rows="+Object.keys(rows).length+",cols="+cols.size+",maxRows="+app.maxRows+",n="+app._launchers.length; } catch(e) { String(e); }'
shape=$(cinnamon_eval "$shape_probe")
rows=$(echo "$shape" | grep -oP 'rows=\K[0-9]+')
cols=$(echo "$shape" | grep -oP 'cols=\K[0-9]+')
maxRows=$(echo "$shape" | grep -oP 'maxRows=\K[0-9]+')
n=$(echo "$shape" | grep -oP 'n=\K[0-9]+')
expected_cols=$(( (n + maxRows - 1) / maxRows ))
if (( n <= maxRows )); then expected_cols=$n; fi
assert_eq "grid row count (n=$n, maxRows=$maxRows)" "$maxRows" "$rows"
assert_eq "grid column count (ceil($n/$maxRows) = $expected_cols)" "$expected_cols" "$cols"

# Rendered-cols-mismatch watchdog: walk children grouped by Y allocation,
# count cols in the first row, assert it matches calcContainerColumns.
# This is the same algorithm the runtime watchdog uses (_verifyLayout).
cols_probe='try { let app = imports.ui.appletManager.get_role_provider("panellauncher"); let children = app.myactor.get_children(); if (children.length < 2) { "skip"; } else { let firstY = Math.round(children[0].get_allocation_box().y1); let actualCols = 0; for (let c of children) if (Math.round(c.get_allocation_box().y1) === firstY) actualCols++; let n = app.myactor.get_n_children(); let expected = (n <= app.maxRows) ? n : Math.ceil(n / app.maxRows); "actual="+actualCols+",expected="+expected; } } catch(e) { String(e); }'
cols_state=$(cinnamon_eval "$cols_probe")
actual_cols=$(echo "$cols_state" | grep -oP 'actual=\K[0-9]+')
exp_cols=$(echo "$cols_state" | grep -oP 'expected=\K[0-9]+')
assert_eq "rendered-cols watchdog: actualCols matches expectedCols (no FlowLayout disagreement)" "$exp_cols" "$actual_cols"

# Heal-path smoke test: invoke _updateContainerWidth(true) directly to verify
# the max-survey code path runs without throwing. Returns the resulting width.
heal_probe='try { let app = imports.ui.appletManager.get_role_provider("panellauncher"); app._updateContainerWidth(true); String(Math.round(app.myactor.width)); } catch(e) { String(e); }'
heal_w=$(cinnamon_eval "$heal_probe")
assert_ge "_updateContainerWidth(true) heal-path returns positive width" "$icon_size" "$heal_w"

echo ""
if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}ALL $PASS PASSED${NC}"
    exit 0
else
    echo -e "${RED}FAILED: $FAIL / $((PASS + FAIL))${NC}"
    exit 1
fi
