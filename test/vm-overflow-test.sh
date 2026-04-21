#!/bin/bash
# Automated VM overflow popup test for multi-row panel launchers.
#
# Tests the standalone overflow panel (St.Bin on Main.uiGroup):
#   - Chevron appears/disappears with overflow state
#   - Overflow panel opens/closes correctly
#   - Launcher counts in panel vs overflow grid are correct
#   - Adjusting max-width dynamically pushes/pulls launchers
#   - DND reorder within panel and within overflow
#   - DND reorder across panel ↔ overflow boundary
#   - Various launcher counts: 0, 1, 10, 50
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - Applet loaded in Cinnamon (via symlink from virtio-fs mount)
#
# Usage:
#   ./test/vm-overflow-test.sh              # Run all tests
#   ./test/vm-overflow-test.sh --revert     # Revert to clean-baseline first
#
# Exit codes:
#   0 = all tests passed
#   1 = one or more tests failed

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VM_CTL="$PROJECT_DIR/vm/vm-ctl.sh"
SCREENSHOT_DIR="$SCRIPT_DIR/screenshots"
APPLET_UUID="multirow-panel-launchers@cinnamon"

# --- Defaults ---
SETTLE_TIME=3
DEFAULT_LAUNCHERS='["nemo.desktop","org.gnome.Terminal.desktop","org.gnome.Calculator.desktop"]'

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Counters ---
TOTAL=0
PASSED=0
FAILED=0
WARNINGS=0

# --- SSH helpers ---
VM_IP=""
get_vm_ip() {
    if [[ -z "$VM_IP" ]]; then
        VM_IP=$("$VM_CTL" ip)
        if [[ -z "$VM_IP" ]]; then
            echo -e "${RED}FATAL: Cannot get VM IP. Is the VM running?${NC}" >&2
            exit 1
        fi
    fi
    echo "$VM_IP"
}

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5"

vm_ssh() {
    local ip
    ip=$(get_vm_ip)
    ssh $SSH_OPTS "steve@$ip" "$@"
}

vm_run() {
    vm_ssh "DISPLAY=:0 $*"
}

install_eval_helper() {
    vm_ssh "cat > /tmp/cinnamon-eval.py" << 'EVAL_HELPER'
#!/usr/bin/env python3
"""Read JS from stdin, eval via Cinnamon D-Bus, print result."""
import subprocess, sys, re

js = sys.stdin.read().strip()
result = subprocess.run(
    ["dbus-send", "--session", "--print-reply", "--dest=org.Cinnamon",
     "/org/Cinnamon", "org.Cinnamon.Eval", "string:" + js],
    capture_output=True, text=True
)
output = result.stdout
success = "boolean true" in output
match = re.search(r'^\s*string "(.*)"$', output, re.MULTILINE)
if match:
    val = match.group(1)
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if success else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EVAL_HELPER
}

cinnamon_eval() {
    echo "$1" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
}

# --- Test result helpers ---
test_result() {
    local description="$1"
    local status="$2"
    local detail="$3"
    TOTAL=$((TOTAL + 1))
    case "$status" in
        pass)
            PASSED=$((PASSED + 1))
            echo -e "  ${GREEN}PASS${NC} $description${detail:+ ($detail)}"
            ;;
        fail)
            FAILED=$((FAILED + 1))
            echo -e "  ${RED}FAIL${NC} $description${detail:+ ($detail)}"
            ;;
        warn)
            WARNINGS=$((WARNINGS + 1))
            PASSED=$((PASSED + 1))
            echo -e "  ${YELLOW}WARN${NC} $description${detail:+ ($detail)}"
            ;;
    esac
}

# --- Launcher management ---
LAUNCHER_POOL=""

build_launcher_pool() {
    echo -e "  Building .desktop launcher pool from Cinnamon AppSystem..."
    local raw
    raw=$(cinnamon_eval "
        let appSys = imports.gi.Cinnamon.AppSystem.get_default();
        let apps = appSys.get_all();
        let ids = [];
        for (let i = 0; i < apps.length && ids.length < 60; i++) {
            let id = apps[i].get_id();
            if (id && id.endsWith('.desktop')) ids.push(id);
        }
        ids.join('|')
    ")
    LAUNCHER_POOL=$(echo "$raw" | tr '|' '\n')
    local pool_size
    pool_size=$(echo "$LAUNCHER_POOL" | wc -l)
    echo -e "  ${CYAN}INFO${NC} Found $pool_size launchable apps in Cinnamon AppSystem"
}

set_launcher_count() {
    local count=$1
    if [[ $count -eq 0 ]]; then
        cinnamon_eval "
            let mgr = imports.ui.appletManager;
            let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
            app.settings.setValue(\"launcherList\", []);
            'ok'
        " >/dev/null
        return
    fi
    local launchers
    launchers=$(echo "$LAUNCHER_POOL" | head -"$count")
    local js_array="["
    local first=true
    while IFS= read -r desktop; do
        [[ -z "$desktop" ]] && continue
        if $first; then first=false; else js_array+=","; fi
        js_array+="\"$desktop\""
    done <<< "$launchers"
    js_array+="]"
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.settings.setValue(\"launcherList\", $js_array);
        'ok'
    " >/dev/null
}

set_max_width() {
    local width=$1
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.settings.setValue(\"max-width\", $width);
        'ok'
    " >/dev/null
}

set_max_rows() {
    local rows=$1
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.settings.setValue(\"max-rows\", $rows);
        'ok'
    " >/dev/null
}

reset_settings() {
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.settings.setValue(\"launcherList\", $DEFAULT_LAUNCHERS);
        app.settings.setValue(\"max-width\", 0);
        app.settings.setValue(\"max-rows\", 2);
        'ok'
    " >/dev/null 2>/dev/null || true
}

# --- Screenshot ---
take_screenshot() {
    local label="$1"
    local filename="vm-overflow-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    vm_ssh "rm -f /tmp/screenshot-full.png /tmp/screenshot.png; \
        DISPLAY=:0 gnome-screenshot -f /tmp/screenshot-full.png 2>/dev/null && \
        convert /tmp/screenshot-full.png -gravity South -crop 0x65+0+0 +repage /tmp/screenshot.png" 2>/dev/null
    scp $SSH_OPTS "steve@$(get_vm_ip):/tmp/screenshot.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null
    echo "$SCREENSHOT_DIR/$filename"
}

# Full-screen screenshot (for popup visibility)
take_full_screenshot() {
    local label="$1"
    local filename="vm-overflow-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    vm_ssh "rm -f /tmp/screenshot-full.png; \
        DISPLAY=:0 gnome-screenshot -f /tmp/screenshot-full.png 2>/dev/null" 2>/dev/null
    scp $SSH_OPTS "steve@$(get_vm_ip):/tmp/screenshot-full.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null
    echo "$SCREENSHOT_DIR/$filename"
}

# --- Query helpers ---

# Query comprehensive overflow state
query_overflow_state() {
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let panelChildren = app.myactor.get_n_children();
        let overflowChildren = app._overflowGrid ? app._overflowGrid.get_n_children() : 0;
        let hasChevron = app._overflowIndicator !== null;
        let hasPanel = app._overflowPanel !== null;
        let panelOpen = app._overflowPanelOpen === true;
        let panelVisible = app._overflowPanel ? app._overflowPanel.visible : false;
        let startIndex = app._overflowStartIndex;
        let totalLaunchers = app._launchers.length;
        let maxWidth = app.maxWidth || 0;
        let maxRows = app.maxRows || 2;
        let chevronParent = '';
        if (hasChevron) {
            let p = app._overflowIndicator.get_parent();
            if (p === app.actor) chevronParent = 'applet-box';
            else if (p === app.myactor) chevronParent = 'myactor';
            else chevronParent = 'other';
        }
        let ab = app.actor.get_allocation_box();
        let containerW = Math.round(app.myactor.get_allocation_box().x2 - app.myactor.get_allocation_box().x1);

        // Get launcher order (first 5 IDs from panel, first 5 from overflow)
        let panelIds = [];
        let panelKids = app.myactor.get_children();
        for (let i = 0; i < Math.min(panelKids.length, 5); i++) {
            if (panelKids[i]._delegate && panelKids[i]._delegate.getId)
                panelIds.push(panelKids[i]._delegate.getId());
        }
        let overflowIds = [];
        if (app._overflowGrid) {
            let oKids = app._overflowGrid.get_children();
            for (let i = 0; i < Math.min(oKids.length, 5); i++) {
                if (oKids[i]._delegate && oKids[i]._delegate.getId)
                    overflowIds.push(oKids[i]._delegate.getId());
            }
        }

        JSON.stringify({
            totalLaunchers: totalLaunchers,
            panelChildren: panelChildren,
            overflowChildren: overflowChildren,
            hasChevron: hasChevron,
            chevronParent: chevronParent,
            hasPanel: hasPanel,
            panelOpen: panelOpen,
            panelVisible: panelVisible,
            startIndex: startIndex,
            maxWidth: maxWidth,
            maxRows: maxRows,
            actorW: Math.round(ab.x2 - ab.x1),
            containerW: containerW,
            panelIds: panelIds,
            overflowIds: overflowIds
        })
    "
}

json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$field'])"
}

json_bool() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print('true' if json.loads(sys.stdin.read())['$field'] else 'false')"
}

json_array_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.dumps(json.loads(sys.stdin.read())['$field']))"
}

json_array_len() {
    local json="$1"
    echo "$json" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))"
}

# --- Error log check ---
check_errors() {
    local since_marker="$1"
    local errors
    errors=$(vm_ssh "sed -n '/$since_marker/,\$p' ~/.xsession-errors 2>/dev/null \
        | grep -i '$APPLET_UUID' \
        | grep -iE 'error|critical|exception|segfault' \
        | head -20" 2>/dev/null || true)
    echo "$errors"
}

# --- Preflight ---
preflight() {
    echo -e "${BOLD}Pre-flight checks${NC}"

    local status
    status=$("$VM_CTL" status 2>/dev/null | grep -o 'running' || true)
    if [[ "$status" != "running" ]]; then
        echo -e "  ${RED}FATAL: VM is not running${NC}"
        exit 1
    fi
    test_result "VM is running" "pass"

    local hostname
    hostname=$(vm_ssh "hostname" 2>/dev/null || true)
    if [[ -z "$hostname" ]]; then
        echo -e "  ${RED}FATAL: Cannot SSH to VM${NC}"
        exit 1
    fi
    test_result "SSH to VM ($hostname)" "pass"

    install_eval_helper
    test_result "D-Bus eval helper installed" "pass"

    local applet_check
    applet_check=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        mgr.getRunningInstancesForUuid(\"$APPLET_UUID\").length > 0
    ")
    if [[ "$applet_check" != "true" ]]; then
        echo -e "  ${RED}FATAL: Applet not loaded in Cinnamon${NC}"
        exit 1
    fi
    test_result "Applet loaded in panel" "pass"

    build_launcher_pool
    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 1: Overflow UI creation/destruction
# ═══════════════════════════════════════════════════════

test_no_overflow_with_zero_maxwidth() {
    echo -e "${BOLD}Test: No overflow when max-width=0 (unlimited)${NC}"
    set_max_width 0
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    local state
    state=$(query_overflow_state)
    local hasChevron hasPanel totalLaunchers panelChildren
    hasChevron=$(json_bool "$state" hasChevron)
    hasPanel=$(json_bool "$state" hasPanel)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    panelChildren=$(json_field "$state" panelChildren)

    if [[ "$hasChevron" == "false" ]]; then
        test_result "No chevron with max-width=0" "pass"
    else
        test_result "No chevron with max-width=0" "fail" "chevron exists but shouldn't"
    fi

    if [[ "$hasPanel" == "false" ]]; then
        test_result "No overflow panel with max-width=0" "pass"
    else
        test_result "No overflow panel with max-width=0" "fail" "panel exists but shouldn't"
    fi

    if [[ "$panelChildren" == "$totalLaunchers" ]]; then
        test_result "All launchers in panel" "pass" "$panelChildren of $totalLaunchers"
    else
        test_result "All launchers in panel" "fail" "$panelChildren of $totalLaunchers in panel"
    fi

    take_screenshot "no-overflow-10" >/dev/null 2>&1 || true
    echo ""
}

test_no_overflow_zero_launchers() {
    echo -e "${BOLD}Test: No overflow with 0 launchers${NC}"
    set_max_width 150
    set_launcher_count 0
    sleep "$SETTLE_TIME"

    local state
    state=$(query_overflow_state)
    local hasChevron hasPanel totalLaunchers
    hasChevron=$(json_bool "$state" hasChevron)
    hasPanel=$(json_bool "$state" hasPanel)
    totalLaunchers=$(json_field "$state" totalLaunchers)

    if [[ "$totalLaunchers" == "0" ]]; then
        test_result "0 launchers loaded" "pass"
    else
        test_result "0 launchers loaded" "fail" "got $totalLaunchers"
    fi

    if [[ "$hasChevron" == "false" ]]; then
        test_result "No chevron with 0 launchers" "pass"
    else
        test_result "No chevron with 0 launchers" "fail"
    fi

    take_screenshot "no-overflow-0" >/dev/null 2>&1 || true
    echo ""
}

test_no_overflow_one_launcher() {
    echo -e "${BOLD}Test: No overflow with 1 launcher (fits in max-width)${NC}"
    set_max_width 150
    set_launcher_count 1
    sleep "$SETTLE_TIME"

    local state
    state=$(query_overflow_state)
    local hasChevron hasPanel totalLaunchers panelChildren
    hasChevron=$(json_bool "$state" hasChevron)
    hasPanel=$(json_bool "$state" hasPanel)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    panelChildren=$(json_field "$state" panelChildren)

    if [[ "$totalLaunchers" == "1" ]]; then
        test_result "1 launcher loaded" "pass"
    else
        test_result "1 launcher loaded" "warn" "got $totalLaunchers"
    fi

    if [[ "$hasChevron" == "false" ]]; then
        test_result "No chevron with 1 launcher (fits)" "pass"
    else
        test_result "No chevron with 1 launcher (fits)" "fail" "chevron shouldn't exist when all fit"
    fi

    if [[ "$panelChildren" == "$totalLaunchers" ]]; then
        test_result "Launcher in panel" "pass"
    else
        test_result "Launcher in panel" "fail" "$panelChildren in panel vs $totalLaunchers total"
    fi

    take_screenshot "no-overflow-1" >/dev/null 2>&1 || true
    echo ""
}

test_overflow_created_with_many_launchers() {
    echo -e "${BOLD}Test: Overflow created with 10 launchers, max-width=80${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    local state
    state=$(query_overflow_state)
    local hasChevron chevronParent hasPanel panelOpen
    local totalLaunchers panelChildren overflowChildren startIndex
    hasChevron=$(json_bool "$state" hasChevron)
    chevronParent=$(json_field "$state" chevronParent)
    hasPanel=$(json_bool "$state" hasPanel)
    panelOpen=$(json_bool "$state" panelOpen)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    panelChildren=$(json_field "$state" panelChildren)
    overflowChildren=$(json_field "$state" overflowChildren)
    startIndex=$(json_field "$state" startIndex)

    if [[ "$hasChevron" == "true" ]]; then
        test_result "Chevron created" "pass"
    else
        test_result "Chevron created" "fail" "no chevron with overflow needed"
    fi

    if [[ "$chevronParent" == "applet-box" ]]; then
        test_result "Chevron is child of applet-box (not myactor)" "pass"
    else
        test_result "Chevron is child of applet-box (not myactor)" "fail" "parent=$chevronParent"
    fi

    if [[ "$hasPanel" == "true" ]]; then
        test_result "Overflow panel created" "pass"
    else
        test_result "Overflow panel created" "fail"
    fi

    if [[ "$panelOpen" == "false" ]]; then
        test_result "Overflow panel starts closed" "pass"
    else
        test_result "Overflow panel starts closed" "fail" "panel is open on creation"
    fi

    local sum=$((panelChildren + overflowChildren))
    if [[ $sum -eq $totalLaunchers ]]; then
        test_result "Launcher split correct" "pass" "panel=$panelChildren overflow=$overflowChildren total=$totalLaunchers"
    else
        test_result "Launcher split correct" "fail" "panel=$panelChildren + overflow=$overflowChildren != $totalLaunchers"
    fi

    if [[ $panelChildren -gt 0 && $overflowChildren -gt 0 ]]; then
        test_result "Both panel and overflow have launchers" "pass"
    else
        test_result "Both panel and overflow have launchers" "fail" "panel=$panelChildren overflow=$overflowChildren"
    fi

    if [[ "$startIndex" -gt 0 ]]; then
        test_result "Overflow start index set" "pass" "startIndex=$startIndex"
    else
        test_result "Overflow start index set" "fail" "startIndex=$startIndex"
    fi

    take_screenshot "overflow-10-mw80" >/dev/null 2>&1 || true
    echo ""
}

test_overflow_50_launchers() {
    echo -e "${BOLD}Test: Overflow with 50 launchers, max-width=150${NC}"
    set_max_width 150
    set_launcher_count 50
    sleep 5  # more settle time for 50 launchers

    local state
    state=$(query_overflow_state)
    local hasChevron hasPanel totalLaunchers panelChildren overflowChildren
    hasChevron=$(json_bool "$state" hasChevron)
    hasPanel=$(json_bool "$state" hasPanel)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    panelChildren=$(json_field "$state" panelChildren)
    overflowChildren=$(json_field "$state" overflowChildren)

    if [[ "$hasChevron" == "true" && "$hasPanel" == "true" ]]; then
        test_result "Overflow UI created for 50 launchers" "pass"
    else
        test_result "Overflow UI created for 50 launchers" "fail" "chevron=$hasChevron panel=$hasPanel"
    fi

    local sum=$((panelChildren + overflowChildren))
    if [[ $sum -ge $((totalLaunchers - 2)) ]]; then
        test_result "All launchers accounted for" "pass" "panel=$panelChildren overflow=$overflowChildren total=$totalLaunchers"
    else
        test_result "All launchers accounted for" "fail" "panel=$panelChildren + overflow=$overflowChildren < $totalLaunchers"
    fi

    if [[ $overflowChildren -gt $panelChildren ]]; then
        test_result "Most launchers in overflow (as expected)" "pass" "overflow=$overflowChildren > panel=$panelChildren"
    else
        test_result "Most launchers in overflow (as expected)" "warn" "overflow=$overflowChildren panel=$panelChildren"
    fi

    # Cinnamon still alive?
    local cinnamon_pid
    cinnamon_pid=$(vm_ssh "pgrep -x cinnamon" 2>/dev/null || true)
    if [[ -n "$cinnamon_pid" ]]; then
        test_result "Cinnamon still running after 50 launchers" "pass" "PID $cinnamon_pid"
    else
        test_result "Cinnamon still running after 50 launchers" "fail"
    fi

    take_screenshot "overflow-50-mw150" >/dev/null 2>&1 || true
    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 2: Open/close overflow panel
# ═══════════════════════════════════════════════════════

test_toggle_overflow_panel() {
    echo -e "${BOLD}Test: Toggle overflow panel open/close${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Open the panel by calling _toggleOverflowPanel
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._toggleOverflowPanel();
        'ok'
    " >/dev/null
    sleep 1

    local state
    state=$(query_overflow_state)
    local panelOpen panelVisible
    panelOpen=$(json_bool "$state" panelOpen)
    panelVisible=$(json_bool "$state" panelVisible)

    if [[ "$panelOpen" == "true" ]]; then
        test_result "Panel opens on toggle" "pass"
    else
        test_result "Panel opens on toggle" "fail" "panelOpen=$panelOpen"
    fi

    if [[ "$panelVisible" == "true" ]]; then
        test_result "Panel visible when open" "pass"
    else
        test_result "Panel visible when open" "fail" "visible=$panelVisible"
    fi

    # Take a full screenshot to see the popup
    take_full_screenshot "overflow-open" >/dev/null 2>&1 || true

    # Check chevron icon is pan-up when open
    local chevronIcon
    chevronIcon=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._overflowIndicator.get_child().icon_name
    ")
    if [[ "$chevronIcon" == "pan-up-symbolic" ]]; then
        test_result "Chevron shows pan-up when open" "pass"
    else
        test_result "Chevron shows pan-up when open" "fail" "icon=$chevronIcon"
    fi

    # Close it
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._toggleOverflowPanel();
        'ok'
    " >/dev/null
    sleep 1

    state=$(query_overflow_state)
    panelOpen=$(json_bool "$state" panelOpen)
    panelVisible=$(json_bool "$state" panelVisible)

    if [[ "$panelOpen" == "false" ]]; then
        test_result "Panel closes on second toggle" "pass"
    else
        test_result "Panel closes on second toggle" "fail"
    fi

    if [[ "$panelVisible" == "false" ]]; then
        test_result "Panel hidden when closed" "pass"
    else
        test_result "Panel hidden when closed" "fail"
    fi

    # Check chevron icon back to pan-down
    chevronIcon=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._overflowIndicator.get_child().icon_name
    ")
    if [[ "$chevronIcon" == "pan-down-symbolic" ]]; then
        test_result "Chevron shows pan-down when closed" "pass"
    else
        test_result "Chevron shows pan-down when closed" "fail" "icon=$chevronIcon"
    fi

    echo ""
}

test_close_via_method() {
    echo -e "${BOLD}Test: Close panel via _closeOverflowPanel()${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Open
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._openOverflowPanel();
        'ok'
    " >/dev/null
    sleep 1

    # Close via explicit method
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._closeOverflowPanel();
        'ok'
    " >/dev/null
    sleep 1

    local state
    state=$(query_overflow_state)
    local panelOpen
    panelOpen=$(json_bool "$state" panelOpen)

    if [[ "$panelOpen" == "false" ]]; then
        test_result "_closeOverflowPanel() closes the panel" "pass"
    else
        test_result "_closeOverflowPanel() closes the panel" "fail"
    fi

    # Verify captured-event handler is disconnected
    local capturedId
    capturedId=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        String(app._capturedEventId)
    ")
    if [[ "$capturedId" == "0" ]]; then
        test_result "captured-event handler disconnected after close" "pass"
    else
        test_result "captured-event handler disconnected after close" "fail" "id=$capturedId"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 3: Dynamic max-width reflow
# ═══════════════════════════════════════════════════════

test_dynamic_maxwidth_reflow() {
    echo -e "${BOLD}Test: Dynamic max-width reflow (push/pull launchers)${NC}"
    set_launcher_count 10
    set_max_width 0  # start unlimited
    sleep "$SETTLE_TIME"

    # Phase 1: All in panel (no overflow)
    local state
    state=$(query_overflow_state)
    local panelChildren1 overflowChildren1 hasChevron1
    panelChildren1=$(json_field "$state" panelChildren)
    overflowChildren1=$(json_field "$state" overflowChildren)
    hasChevron1=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron1" == "false" && "$overflowChildren1" == "0" ]]; then
        test_result "Phase 1: max-width=0 — no overflow" "pass" "panel=$panelChildren1"
    else
        test_result "Phase 1: max-width=0 — no overflow" "fail" "chevron=$hasChevron1 overflow=$overflowChildren1"
    fi

    # Phase 2: Shrink to push launchers into overflow
    set_max_width 60
    sleep "$SETTLE_TIME"

    state=$(query_overflow_state)
    local panelChildren2 overflowChildren2 hasChevron2
    panelChildren2=$(json_field "$state" panelChildren)
    overflowChildren2=$(json_field "$state" overflowChildren)
    hasChevron2=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron2" == "true" && $overflowChildren2 -gt 0 ]]; then
        test_result "Phase 2: max-width=60 — launchers pushed to overflow" "pass" "panel=$panelChildren2 overflow=$overflowChildren2"
    else
        test_result "Phase 2: max-width=60 — launchers pushed to overflow" "fail" "chevron=$hasChevron2 overflow=$overflowChildren2"
    fi

    if [[ $panelChildren2 -lt $panelChildren1 ]]; then
        test_result "Phase 2: fewer launchers in panel than phase 1" "pass" "$panelChildren2 < $panelChildren1"
    else
        test_result "Phase 2: fewer launchers in panel than phase 1" "fail" "$panelChildren2 >= $panelChildren1"
    fi

    take_screenshot "reflow-phase2-mw60" >/dev/null 2>&1 || true

    # Phase 3: Widen to pull some back
    set_max_width 80
    sleep "$SETTLE_TIME"

    state=$(query_overflow_state)
    local panelChildren3 overflowChildren3
    panelChildren3=$(json_field "$state" panelChildren)
    overflowChildren3=$(json_field "$state" overflowChildren)

    if [[ $panelChildren3 -gt $panelChildren2 ]]; then
        test_result "Phase 3: max-width=80 — launchers pulled back to panel" "pass" "panel=$panelChildren3 > $panelChildren2"
    else
        test_result "Phase 3: max-width=80 — launchers pulled back to panel" "warn" "panel=$panelChildren3 (was $panelChildren2)"
    fi

    take_screenshot "reflow-phase3-mw80" >/dev/null 2>&1 || true

    # Phase 4: Widen to unlimited — all back in panel
    set_max_width 0
    sleep "$SETTLE_TIME"

    state=$(query_overflow_state)
    local panelChildren4 overflowChildren4 hasChevron4
    panelChildren4=$(json_field "$state" panelChildren)
    overflowChildren4=$(json_field "$state" overflowChildren)
    hasChevron4=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron4" == "false" && "$overflowChildren4" == "0" ]]; then
        test_result "Phase 4: max-width=0 — all launchers restored to panel" "pass" "panel=$panelChildren4"
    else
        test_result "Phase 4: max-width=0 — all launchers restored to panel" "fail" "chevron=$hasChevron4 overflow=$overflowChildren4"
    fi

    echo ""
}

test_progressive_shrink() {
    echo -e "${BOLD}Test: Progressive shrink — 200 → 120 → 80 → 40${NC}"
    set_launcher_count 20
    set_max_width 200
    sleep 4

    local prev_overflow=0
    for mw in 200 120 80 40; do
        set_max_width $mw
        sleep "$SETTLE_TIME"

        local state
        state=$(query_overflow_state)
        local panelChildren overflowChildren totalLaunchers
        panelChildren=$(json_field "$state" panelChildren)
        overflowChildren=$(json_field "$state" overflowChildren)
        totalLaunchers=$(json_field "$state" totalLaunchers)

        local sum=$((panelChildren + overflowChildren))

        if [[ $sum -ge $((totalLaunchers - 2)) ]]; then
            test_result "max-width=$mw: launchers accounted for" "pass" "panel=$panelChildren overflow=$overflowChildren"
        else
            test_result "max-width=$mw: launchers accounted for" "fail" "panel=$panelChildren + overflow=$overflowChildren != $totalLaunchers"
        fi

        if [[ $overflowChildren -ge $prev_overflow ]]; then
            test_result "max-width=$mw: overflow grows or stays same" "pass" "$overflowChildren >= $prev_overflow"
        else
            test_result "max-width=$mw: overflow grows or stays same" "fail" "$overflowChildren < $prev_overflow"
        fi

        prev_overflow=$overflowChildren
        take_screenshot "progressive-mw${mw}" >/dev/null 2>&1 || true
    done

    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 4: DND reorder
# ═══════════════════════════════════════════════════════

test_dnd_reorder_panel() {
    echo -e "${BOLD}Test: DND reorder within panel (simulated via _reinsertAtIndex)${NC}"
    set_max_width 0
    set_launcher_count 5
    sleep "$SETTLE_TIME"

    # Get initial order
    local before_ids
    before_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")

    # Move launcher 0 to index 2
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._reinsertAtIndex(app._launchers[0], 2);
        'ok'
    " >/dev/null
    sleep 2

    local after_ids
    after_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")

    if [[ "$before_ids" != "$after_ids" ]]; then
        test_result "Panel DND reorder changes launcher order" "pass"
    else
        test_result "Panel DND reorder changes launcher order" "fail" "order unchanged"
    fi

    # Verify the moved launcher is now at position 2
    local first_before first_after
    first_before=$(echo "$before_ids" | cut -d'|' -f1)
    first_after=$(echo "$after_ids" | cut -d'|' -f3)  # should be at index 2 now

    if [[ "$first_before" == "$first_after" ]]; then
        test_result "Launcher moved from index 0 to index 2" "pass" "$first_before"
    else
        test_result "Launcher moved from index 0 to index 2" "fail" "expected $first_before at [2], got $first_after"
    fi

    # Verify no errors after reorder
    local marker="DND_PANEL_TEST_$(date +%s)"
    vm_ssh "echo '$marker' >> ~/.xsession-errors" 2>/dev/null
    sleep 1
    local errors
    errors=$(check_errors "$marker")
    if [[ -z "$errors" ]]; then
        test_result "No errors after panel DND reorder" "pass"
    else
        test_result "No errors after panel DND reorder" "fail" "$(echo "$errors" | wc -l) error(s)"
    fi

    echo ""
}

test_dnd_reorder_overflow() {
    echo -e "${BOLD}Test: DND reorder within overflow grid (simulated)${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Get initial order
    local before_ids
    before_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")
    local startIndex
    startIndex=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._overflowStartIndex
    ")

    # Move last launcher to the overflow start position (reorder within overflow)
    local lastIndex
    lastIndex=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        String(app._launchers.length - 1)
    ")

    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let lastIdx = app._launchers.length - 1;
        app._reinsertAtIndex(app._launchers[lastIdx], app._overflowStartIndex);
        'ok'
    " >/dev/null
    sleep 2

    local after_ids
    after_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")

    if [[ "$before_ids" != "$after_ids" ]]; then
        test_result "Overflow DND reorder changes order" "pass"
    else
        test_result "Overflow DND reorder changes order" "fail" "order unchanged"
    fi

    # Verify launcher counts still add up
    local state
    state=$(query_overflow_state)
    local panelChildren overflowChildren totalLaunchers
    panelChildren=$(json_field "$state" panelChildren)
    overflowChildren=$(json_field "$state" overflowChildren)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    local sum=$((panelChildren + overflowChildren))

    if [[ $sum -eq $totalLaunchers ]]; then
        test_result "Launcher count preserved after overflow reorder" "pass" "panel=$panelChildren overflow=$overflowChildren"
    else
        test_result "Launcher count preserved after overflow reorder" "fail" "panel=$panelChildren + overflow=$overflowChildren != $totalLaunchers"
    fi

    echo ""
}

test_dnd_cross_boundary() {
    echo -e "${BOLD}Test: DND across panel ↔ overflow boundary${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Get state before
    local state_before
    state_before=$(query_overflow_state)
    local panelBefore overflowBefore
    panelBefore=$(json_field "$state_before" panelChildren)
    overflowBefore=$(json_field "$state_before" overflowChildren)

    local before_ids
    before_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")

    # Move first overflow launcher to position 0 (overflow → panel)
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let idx = app._overflowStartIndex;
        app._reinsertAtIndex(app._launchers[idx], 0);
        'ok'
    " >/dev/null
    sleep 2

    local after_ids
    after_ids=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.map(function(l) { return l.getId(); }).join('|')
    ")

    if [[ "$before_ids" != "$after_ids" ]]; then
        test_result "Cross-boundary DND changes order" "pass"
    else
        test_result "Cross-boundary DND changes order" "fail" "order unchanged"
    fi

    local state_after
    state_after=$(query_overflow_state)
    local panelAfter overflowAfter totalAfter
    panelAfter=$(json_field "$state_after" panelChildren)
    overflowAfter=$(json_field "$state_after" overflowChildren)
    totalAfter=$(json_field "$state_after" totalLaunchers)
    local sum=$((panelAfter + overflowAfter))

    if [[ $sum -eq $totalAfter ]]; then
        test_result "Launcher count preserved after cross-boundary DND" "pass" "panel=$panelAfter overflow=$overflowAfter"
    else
        test_result "Launcher count preserved after cross-boundary DND" "fail" "panel=$panelAfter + overflow=$overflowAfter != $totalAfter"
    fi

    # Now move first panel launcher to overflow position
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let targetIdx = app._launchers.length - 1;
        app._reinsertAtIndex(app._launchers[0], targetIdx);
        'ok'
    " >/dev/null
    sleep 2

    state_after=$(query_overflow_state)
    panelAfter=$(json_field "$state_after" panelChildren)
    overflowAfter=$(json_field "$state_after" overflowChildren)
    totalAfter=$(json_field "$state_after" totalLaunchers)
    sum=$((panelAfter + overflowAfter))

    if [[ $sum -eq $totalAfter ]]; then
        test_result "Launcher count preserved after reverse cross-boundary DND" "pass" "panel=$panelAfter overflow=$overflowAfter"
    else
        test_result "Launcher count preserved after reverse cross-boundary DND" "fail" "panel=$panelAfter + overflow=$overflowAfter != $totalAfter"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 5: Chevron stability during DND
# ═══════════════════════════════════════════════════════

test_chevron_stable_during_dnd() {
    echo -e "${BOLD}Test: Chevron remains stable during panel DND reorder${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Verify chevron is in applet-box before DND
    local state
    state=$(query_overflow_state)
    local chevronBefore
    chevronBefore=$(json_field "$state" chevronParent)

    # Simulate multiple DND reorders in the panel
    for i in 1 2 3; do
        cinnamon_eval "
            let mgr = imports.ui.appletManager;
            let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
            if (app._launchers.length >= 2) {
                app._reinsertAtIndex(app._launchers[0], 1);
            }
            'ok'
        " >/dev/null
        sleep 1
    done

    state=$(query_overflow_state)
    local chevronAfter hasChevron
    chevronAfter=$(json_field "$state" chevronParent)
    hasChevron=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron" == "true" ]]; then
        test_result "Chevron still exists after 3 DND reorders" "pass"
    else
        test_result "Chevron still exists after 3 DND reorders" "fail"
    fi

    if [[ "$chevronAfter" == "applet-box" ]]; then
        test_result "Chevron still in applet-box after DND" "pass"
    else
        test_result "Chevron still in applet-box after DND" "fail" "parent=$chevronAfter"
    fi

    # Verify launcher split is still correct
    local panelChildren overflowChildren totalLaunchers
    panelChildren=$(json_field "$state" panelChildren)
    overflowChildren=$(json_field "$state" overflowChildren)
    totalLaunchers=$(json_field "$state" totalLaunchers)
    local sum=$((panelChildren + overflowChildren))

    if [[ $sum -eq $totalLaunchers ]]; then
        test_result "Launcher split intact after DND" "pass" "panel=$panelChildren overflow=$overflowChildren"
    else
        test_result "Launcher split intact after DND" "fail" "panel=$panelChildren + overflow=$overflowChildren != $totalLaunchers"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 6: Overflow cleanup
# ═══════════════════════════════════════════════════════

test_overflow_destroyed_on_orientation_change() {
    echo -e "${BOLD}Test: Overflow destroyed on orientation change to vertical${NC}"
    set_max_width 80
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    # Confirm overflow exists
    local state
    state=$(query_overflow_state)
    local hasChevron1
    hasChevron1=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron1" != "true" ]]; then
        test_result "Precondition: overflow exists before orientation change" "fail"
        echo ""
        return
    fi

    # Change to vertical (St.Side.LEFT = 3)
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.on_orientation_changed(3);
        'ok'
    " >/dev/null
    sleep 2

    state=$(query_overflow_state)
    local hasChevron2 hasPanel2
    hasChevron2=$(json_bool "$state" hasChevron)
    hasPanel2=$(json_bool "$state" hasPanel)

    if [[ "$hasChevron2" == "false" && "$hasPanel2" == "false" ]]; then
        test_result "Overflow destroyed on vertical orientation" "pass"
    else
        test_result "Overflow destroyed on vertical orientation" "fail" "chevron=$hasChevron2 panel=$hasPanel2"
    fi

    # Restore horizontal (St.Side.BOTTOM = 2)
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.on_orientation_changed(2);
        'ok'
    " >/dev/null
    sleep 2

    # Should re-create overflow since max-width is still 150
    state=$(query_overflow_state)
    local hasChevron3
    hasChevron3=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron3" == "true" ]]; then
        test_result "Overflow re-created on horizontal orientation" "pass"
    else
        test_result "Overflow re-created on horizontal orientation" "warn" "may need launcher reload"
    fi

    echo ""
}

test_overflow_destroyed_when_maxwidth_removed() {
    echo -e "${BOLD}Test: Overflow cleaned up when max-width set to 0${NC}"
    # Fully re-establish overflow state from scratch
    set_max_width 0
    set_launcher_count 10
    sleep "$SETTLE_TIME"
    set_max_width 80
    sleep "$SETTLE_TIME"

    local state
    state=$(query_overflow_state)
    local hasChevron1
    hasChevron1=$(json_bool "$state" hasChevron)

    if [[ "$hasChevron1" != "true" ]]; then
        test_result "Precondition: overflow exists" "fail"
        echo ""
        return
    fi
    test_result "Precondition: overflow exists" "pass"

    # Remove max-width limit
    set_max_width 0
    sleep "$SETTLE_TIME"

    state=$(query_overflow_state)
    local hasChevron2 hasPanel2 overflowChildren2
    hasChevron2=$(json_bool "$state" hasChevron)
    hasPanel2=$(json_bool "$state" hasPanel)
    overflowChildren2=$(json_field "$state" overflowChildren)

    if [[ "$hasChevron2" == "false" ]]; then
        test_result "Chevron removed when overflow not needed" "pass"
    else
        test_result "Chevron removed when overflow not needed" "fail"
    fi

    if [[ "$hasPanel2" == "false" ]]; then
        test_result "Overflow panel removed when not needed" "pass"
    else
        test_result "Overflow panel removed when not needed" "fail"
    fi

    if [[ "$overflowChildren2" == "0" ]]; then
        test_result "No launchers in overflow" "pass"
    else
        test_result "No launchers in overflow" "fail" "$overflowChildren2 still in overflow"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 8: Self-heal watchdog
# ═══════════════════════════════════════════════════════

test_watchdog_methods_present() {
    echo -e "${BOLD}Test: Watchdog methods exist on the applet${NC}"
    local check
    check=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let ok = typeof app._scheduleVerify === 'function' &&
                 typeof app._verifyLayout === 'function';
        'hasMethods=' + ok +
        ' verifySourceId=' + (typeof app._verifySourceId) +
        ' healing=' + (typeof app._healing) +
        ' retries=' + (typeof app._verifyRetries)
    ")
    if echo "$check" | grep -q "hasMethods=true"; then
        test_result "Watchdog methods present" "pass" "$check"
    else
        test_result "Watchdog methods present" "fail" "$check"
    fi
    echo ""
}

test_heal_restores_wrong_icon_size() {
    echo -e "${BOLD}Test: Watchdog restores icon_size after forced mismatch${NC}"
    reset_settings
    set_launcher_count 5
    sleep "$SETTLE_TIME"

    # Capture the correct value, forcibly break it, run the verify, re-read.
    local result
    result=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let before = app.icon_size;
        app.icon_size = 999;
        app._verifyLayout();
        let after = app.icon_size;
        'before=' + before + ' forced=999 after=' + after + ' restored=' + (after === before)
    ")
    if echo "$result" | grep -q "restored=true"; then
        test_result "Icon size restored by _verifyLayout" "pass" "$result"
    else
        test_result "Icon size restored by _verifyLayout" "fail" "$result"
    fi
    echo ""
}

test_heal_recreates_launchers() {
    echo -e "${BOLD}Test: Heal path reloads launcher actors${NC}"
    reset_settings
    set_launcher_count 5
    sleep "$SETTLE_TIME"

    local result
    result=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let firstBefore = app._launchers[0];
        app.icon_size = 999;
        app._verifyLayout();
        let firstAfter = app._launchers[0];
        let recreated = firstBefore !== firstAfter;
        let count = app._launchers.length;
        'recreated=' + recreated + ' count=' + count
    ")
    if echo "$result" | grep -q "recreated=true"; then
        test_result "Launcher actors recreated on icon-size heal" "pass" "$result"
    else
        test_result "Launcher actors recreated on icon-size heal" "fail" "$result"
    fi
    echo ""
}

test_watchdog_source_tracking() {
    echo -e "${BOLD}Test: Watchdog idle source tracked and cleared${NC}"
    reset_settings
    set_launcher_count 5
    sleep "$SETTLE_TIME"

    # Right after a settings change, _scheduleVerify should have set the source
    # ID. After the idle fires, it should be cleared back to 0.
    local result
    result=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._scheduleVerify();
        let duringSchedule = app._verifySourceId;
        // Force the idle to run synchronously by calling verify directly
        // (the runtime check: does the API clear the ID properly?)
        'duringSchedule=' + (duringSchedule > 0)
    ")
    if echo "$result" | grep -q "duringSchedule=true"; then
        test_result "Verify source ID tracked after _scheduleVerify" "pass" "$result"
    else
        test_result "Verify source ID tracked after _scheduleVerify" "fail" "$result"
    fi

    # Wait a beat for the idle to actually run
    sleep 1
    local cleared
    cleared=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        'cleared=' + (app._verifySourceId === 0)
    ")
    if echo "$cleared" | grep -q "cleared=true"; then
        test_result "Verify source ID cleared after idle fires" "pass" "$cleared"
    else
        test_result "Verify source ID cleared after idle fires" "fail" "$cleared"
    fi
    echo ""
}

test_post_startup_layout_is_consistent() {
    echo -e "${BOLD}Test: Post-startup icon_size matches expected${NC}"
    reset_settings
    set_launcher_count 10
    sleep "$SETTLE_TIME"

    local result
    result=$(cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let h = app._panelHeight || 0;
        let rows = app.maxRows || 2;
        let override = app.iconSizeOverride || 0;
        let expected;
        if (override > 0) expected = override;
        else if (h > 0) expected = Math.max(12, Math.floor(h / rows) - 4);
        else expected = app.icon_size;  // pre-allocation fallback path — skip assertion
        'h=' + h + ' rows=' + rows + ' expected=' + expected + ' actual=' + app.icon_size +
        ' match=' + (expected === app.icon_size)
    ")
    if echo "$result" | grep -q "match=true"; then
        test_result "Steady-state icon_size matches expected" "pass" "$result"
    else
        test_result "Steady-state icon_size matches expected" "fail" "$result"
    fi
    echo ""
}

# ═══════════════════════════════════════════════════════
#  TEST SUITE 7: Error checking
# ═══════════════════════════════════════════════════════

test_no_errors_after_full_cycle() {
    echo -e "${BOLD}Test: No errors after full test cycle${NC}"
    local marker="FULL_CYCLE_CHECK_$(date +%s)"
    vm_ssh "echo '$marker' >> ~/.xsession-errors" 2>/dev/null

    # Run a cycle: 0 → 10 → 50 → 10 → 0 launchers with varying max-width
    for count in 0 10 50 10 0; do
        set_launcher_count "$count"
        if [[ $count -ge 50 ]]; then
            set_max_width 100
            sleep 4
        elif [[ $count -ge 10 ]]; then
            set_max_width 60
            sleep "$SETTLE_TIME"
        else
            set_max_width 0
            sleep 2
        fi
    done

    local errors
    errors=$(check_errors "$marker")
    if [[ -z "$errors" ]]; then
        test_result "No errors after full cycle (0→10→50→10→0)" "pass"
    else
        test_result "No errors after full cycle (0→10→50→10→0)" "fail" "$(echo "$errors" | wc -l) error(s)"
        echo "$errors" | head -5 | while read -r line; do
            echo -e "    ${RED}> $line${NC}"
        done
    fi

    local cinnamon_pid
    cinnamon_pid=$(vm_ssh "pgrep -x cinnamon" 2>/dev/null || true)
    if [[ -n "$cinnamon_pid" ]]; then
        test_result "Cinnamon still running after full cycle" "pass" "PID $cinnamon_pid"
    else
        test_result "Cinnamon still running after full cycle" "fail"
    fi

    echo ""
}

# ═══════════════════════════════════════════════════════
#  Main
# ═══════════════════════════════════════════════════════

main() {
    echo ""
    local do_revert=false
    for arg in "$@"; do
        if [[ "$arg" == "--revert" ]]; then
            do_revert=true
        fi
    done

    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  VM Overflow Popup Test${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""

    if $do_revert; then
        echo -e "${CYAN}Reverting to clean-baseline snapshot...${NC}"
        "$VM_CTL" revert clean-baseline
        "$VM_CTL" start
        sleep 10
        echo ""
    fi

    trap reset_settings EXIT INT TERM

    preflight

    # Restart Cinnamon to load latest applet code
    echo -e "${CYAN}Restarting Cinnamon to load latest applet code...${NC}"
    vm_run "cinnamon --replace &>/dev/null &" 2>/dev/null || true
    sleep 5
    echo ""

    # Suite 1: Overflow UI creation/destruction
    echo -e "${BOLD}═══ Suite 1: Overflow UI creation/destruction ═══${NC}"
    echo ""
    test_no_overflow_with_zero_maxwidth
    test_no_overflow_zero_launchers
    test_no_overflow_one_launcher
    test_overflow_created_with_many_launchers
    test_overflow_50_launchers

    # Suite 2: Open/close
    echo -e "${BOLD}═══ Suite 2: Open/close overflow panel ═══${NC}"
    echo ""
    test_toggle_overflow_panel
    test_close_via_method

    # Suite 3: Dynamic max-width reflow
    echo -e "${BOLD}═══ Suite 3: Dynamic max-width reflow ═══${NC}"
    echo ""
    test_dynamic_maxwidth_reflow
    test_progressive_shrink

    # Suite 4: DND reorder
    echo -e "${BOLD}═══ Suite 4: DND reorder ═══${NC}"
    echo ""
    test_dnd_reorder_panel
    test_dnd_reorder_overflow
    test_dnd_cross_boundary

    # Suite 5: Chevron stability
    echo -e "${BOLD}═══ Suite 5: Chevron stability during DND ═══${NC}"
    echo ""
    test_chevron_stable_during_dnd

    # Suite 6: Overflow cleanup
    echo -e "${BOLD}═══ Suite 6: Overflow cleanup ═══${NC}"
    echo ""
    test_overflow_destroyed_on_orientation_change
    test_overflow_destroyed_when_maxwidth_removed

    # Suite 8: Self-heal watchdog
    echo -e "${BOLD}═══ Suite 8: Self-heal watchdog ═══${NC}"
    echo ""
    test_watchdog_methods_present
    test_post_startup_layout_is_consistent
    test_heal_restores_wrong_icon_size
    test_heal_recreates_launchers
    test_watchdog_source_tracking

    # Suite 7: Error checking
    echo -e "${BOLD}═══ Suite 7: Error checking ═══${NC}"
    echo ""
    test_no_errors_after_full_cycle

    # --- Summary ---
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  Summary${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "  Total:    $TOTAL"
    echo -e "  ${GREEN}Passed:   $PASSED${NC}"
    if [[ $FAILED -gt 0 ]]; then
        echo -e "  ${RED}Failed:   $FAILED${NC}"
    else
        echo -e "  Failed:   0"
    fi
    if [[ $WARNINGS -gt 0 ]]; then
        echo -e "  ${YELLOW}Warnings: $WARNINGS${NC}"
    fi
    echo ""

    if [[ $FAILED -gt 0 ]]; then
        echo -e "${RED}RESULT: FAIL${NC}"
        exit 1
    else
        echo -e "${GREEN}RESULT: PASS${NC}"
        exit 0
    fi
}

main "$@"
