#!/bin/bash
# Automated VM panel zone test for multi-row panel launchers.
#
# Tests that FlowLayout min_width = 0 override prevents panel zone squeeze
# across varying launcher counts: 0, 1, 5, 10, 20, 50.
#
# Prerequisites:
#   - VM "cinnamon-dev" running (./vm/vm-ctl.sh start)
#   - Applet loaded in Cinnamon (via symlink from virtio-fs mount)
#
# Usage:
#   ./test/vm-panel-test.sh              # Run all test cases
#   ./test/vm-panel-test.sh --revert     # Revert to clean-baseline first
#   ./test/vm-panel-test.sh 0 1 50       # Run specific launcher counts only
#
# Each test case:
#   1. Sets launcherList to N entries via Cinnamon D-Bus eval
#   2. Waits for panel to settle
#   3. Queries panel zone widths, launcher positions, and applet state
#   4. Asserts panel zone integrity and launcher loading
#   5. Takes a screenshot for visual reference
#   6. Moves on to next count (cleanup restores defaults at end)
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
DEFAULT_COUNTS=(0 1 5 10 20 50)
SETTLE_TIME=3          # seconds to wait after setting launchers
MIN_RIGHT_WIDTH=100    # right zone must be at least this wide (px)
MIN_LEFT_WIDTH=50      # left zone must be at least this wide (px)

# Default launchers to restore after tests
DEFAULT_LAUNCHERS='["nemo.desktop","firefox.desktop","org.gnome.Terminal.desktop"]'

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
# Get VM IP once and cache it
VM_IP=""
get_vm_ip() {
    if [[ -z "$VM_IP" ]]; then
        VM_IP=$("$VM_CTL" ip)
        if [[ -z "$VM_IP" ]]; then
            echo -e "${RED}FATAL: Cannot get VM IP. Is the VM running?${NC}" >&2
            echo "  Start with: $VM_CTL start" >&2
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

# Run a command on the VM with DISPLAY set
vm_run() {
    vm_ssh "DISPLAY=:0 $*"
}

# Install a Python helper on the VM for quoting-safe D-Bus eval.
# JS code goes through stdin, avoiding all shell quoting issues.
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
    # Strip outer escaped quotes if present (D-Bus returns "\"value\"")
    if val.startswith('"') and val.endswith('"'):
        val = val[1:-1]
    # Un-escape D-Bus string escaping (\" -> ", \\\\ -> \\)
    val = val.replace('\\"', '"').replace('\\\\', '\\')
    print(val)
    sys.exit(0 if success else 1)
else:
    print("PARSE_ERROR: " + output, file=sys.stderr)
    sys.exit(1)
EVAL_HELPER
}

# Evaluate JavaScript in the running Cinnamon process via D-Bus.
# JS is piped through stdin to avoid shell quoting issues.
cinnamon_eval() {
    echo "$1" | vm_ssh "DISPLAY=:0 python3 /tmp/cinnamon-eval.py"
}

# --- Test result helpers ---
test_result() {
    local description="$1"
    local status="$2"    # pass, fail, warn
    local detail="$3"    # optional detail message
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
            PASSED=$((PASSED + 1))  # warnings still count as passed
            echo -e "  ${YELLOW}WARN${NC} $description${detail:+ ($detail)}"
            ;;
    esac
}

# --- Launcher management ---

# Launcher pool: .desktop files available in the VM
LAUNCHER_POOL=""

build_launcher_pool() {
    echo -e "  Building .desktop launcher pool from Cinnamon AppSystem..."
    # Query Cinnamon's AppSystem for apps it actually knows about.
    # Raw filesystem listings include OnlyShowIn=XFCE etc. that Cinnamon skips.
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
    # Split pipe-delimited output into newline-delimited list
    LAUNCHER_POOL=$(echo "$raw" | tr '|' '\n')
    local pool_size
    pool_size=$(echo "$LAUNCHER_POOL" | wc -l)
    echo -e "  ${CYAN}INFO${NC} Found $pool_size launchable apps in Cinnamon AppSystem"
    if [[ $pool_size -lt 50 ]]; then
        echo -e "  ${YELLOW}WARN${NC} Fewer than 50 apps available — count=50 test may have fewer launchers"
    fi
}

# Set launcher list to first N entries from pool via settings setValue
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

    # Build JS array of first N .desktop filenames
    local launchers
    launchers=$(echo "$LAUNCHER_POOL" | head -"$count")
    local js_array="["
    local first=true
    while IFS= read -r desktop; do
        [[ -z "$desktop" ]] && continue
        if $first; then
            first=false
        else
            js_array+=","
        fi
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

# Restore default 3-launcher list
reset_launchers() {
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app.settings.setValue(\"launcherList\", $DEFAULT_LAUNCHERS);
        'ok'
    " >/dev/null 2>/dev/null || true
}

# Count loaded launchers via D-Bus eval
count_launchers() {
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        app._launchers.length
    "
}

# --- Screenshot ---
take_screenshot() {
    local label="$1"
    local filename="vm-panel-${label}.png"
    mkdir -p "$SCREENSHOT_DIR"
    # gnome-screenshot captures the composited output reliably;
    # xwd misses it. Crop to bottom 65px to show just the panel.
    vm_ssh "rm -f /tmp/screenshot-full.png /tmp/screenshot.png; \
        DISPLAY=:0 gnome-screenshot -f /tmp/screenshot-full.png 2>/dev/null && \
        convert /tmp/screenshot-full.png -gravity South -crop 0x65+0+0 +repage /tmp/screenshot.png" 2>/dev/null
    scp $SSH_OPTS "steve@$(get_vm_ip):/tmp/screenshot.png" "$SCREENSHOT_DIR/$filename" 2>/dev/null
    echo "$SCREENSHOT_DIR/$filename"
}

# --- Panel state query ---
# Returns JSON with panel zone data and launcher info
query_panel_state() {
    cinnamon_eval "
        let mgr = imports.ui.appletManager;
        let app = mgr.getRunningInstancesForUuid(\"$APPLET_UUID\")[0];
        let rb = Main.panel._rightBox.get_allocation_box();
        let lb = Main.panel._leftBox.get_allocation_box();
        let children = app.myactor.get_children();
        let yValues = {};
        children.forEach(function(c) {
            let y = Math.round(c.get_allocation_box().y1);
            yValues[y] = (yValues[y] || 0) + 1;
        });
        let ab = app.actor.get_allocation_box();
        JSON.stringify({
            screenWidth: global.screen_width,
            panelHeight: Main.panel.height,
            leftWidth: Math.round(lb.x2 - lb.x1),
            leftX1: Math.round(lb.x1),
            rightWidth: Math.round(rb.x2 - rb.x1),
            rightX1: Math.round(rb.x1),
            rightX2: Math.round(rb.x2),
            centerWidth: Math.round(Main.panel._centerBox.get_width()),
            minWidth: app.myactor.min_width,
            launcherCount: app._launchers.length,
            childCount: children.length,
            iconSize: app.icon_size,
            maxRows: app.maxRows,
            actorW: Math.round(ab.x2 - ab.x1),
            containerW: Math.round(app.myactor.get_allocation_box().x2 - app.myactor.get_allocation_box().x1),
            containerH: Math.round(app.myactor.get_allocation_box().y2 - app.myactor.get_allocation_box().y1),
            rowDistribution: yValues
        })
    "
}

# Extract a JSON field (simple jq-free parser)
json_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; print(json.loads(sys.stdin.read())['$field'])"
}

# Extract a nested JSON field (for rowDistribution — returns the dict as JSON)
json_dict_field() {
    local json="$1"
    local field="$2"
    echo "$json" | python3 -c "import sys,json; d=json.loads(sys.stdin.read())['$field']; print(json.dumps(d))"
}

# Count keys in a JSON dict (number of distinct rows)
json_dict_len() {
    local json="$1"
    echo "$json" | python3 -c "import sys,json; print(len(json.loads(sys.stdin.read())))"
}

# --- Error log check ---
# Check .xsession-errors for applet-specific errors since a given timestamp
check_errors() {
    local since_marker="$1"
    local errors
    errors=$(vm_ssh "sed -n '/$since_marker/,\$p' ~/.xsession-errors 2>/dev/null \
        | grep -i '$APPLET_UUID' \
        | grep -iE 'error|critical|exception|segfault' \
        | head -20" 2>/dev/null || true)
    echo "$errors"
}

# --- Pre-flight checks ---
preflight() {
    echo -e "${BOLD}Pre-flight checks${NC}"

    # VM running?
    local status
    status=$("$VM_CTL" status 2>/dev/null | grep -o 'running' || true)
    if [[ "$status" != "running" ]]; then
        echo -e "  ${RED}FATAL: VM is not running${NC}"
        echo "  Start with: $VM_CTL start"
        exit 1
    fi
    test_result "VM is running" "pass"

    # SSH works?
    local hostname
    hostname=$(vm_ssh "hostname" 2>/dev/null || true)
    if [[ -z "$hostname" ]]; then
        echo -e "  ${RED}FATAL: Cannot SSH to VM${NC}"
        exit 1
    fi
    test_result "SSH to VM ($hostname)" "pass"

    # Install D-Bus eval helper
    install_eval_helper
    test_result "D-Bus eval helper installed" "pass"

    # Applet loaded?
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

    # D-Bus eval working?
    local state
    state=$(query_panel_state)
    if [[ -z "$state" || "$state" == *"PARSE_ERROR"* ]]; then
        echo -e "  ${RED}FATAL: Cannot query panel state via D-Bus${NC}"
        exit 1
    fi
    local sw
    sw=$(json_field "$state" screenWidth)
    test_result "D-Bus panel query works (screen ${sw}px)" "pass"

    # Build launcher pool
    build_launcher_pool

    echo ""
}

# --- Run one test case ---
run_test_case() {
    local launcher_count=$1
    echo -e "${BOLD}Test case: ${CYAN}${launcher_count} launchers${NC}"

    # Drop a marker in xsession-errors so we can check for new errors
    local marker="VM_PANEL_TEST_MARKER_${launcher_count}_$(date +%s)"
    vm_ssh "echo '$marker' >> ~/.xsession-errors" 2>/dev/null

    # Set launcher count
    set_launcher_count "$launcher_count"

    # Wait for panel to settle
    local wait_time=$SETTLE_TIME
    if [[ $launcher_count -ge 20 ]]; then
        wait_time=$((SETTLE_TIME + 1))
    fi
    if [[ $launcher_count -ge 50 ]]; then
        wait_time=$((SETTLE_TIME + 2))
    fi
    sleep "$wait_time"

    # Verify launcher count
    local actual_launchers
    actual_launchers=$(count_launchers)
    if [[ $launcher_count -eq 0 ]]; then
        if [[ "$actual_launchers" == "0" ]]; then
            test_result "No launchers loaded" "pass"
        else
            test_result "No launchers loaded" "fail" "found $actual_launchers"
        fi
    elif [[ $actual_launchers -ge $((launcher_count - 2)) && $actual_launchers -le $launcher_count ]]; then
        test_result "Launchers loaded" "pass" "requested=$launcher_count actual=$actual_launchers"
    else
        test_result "Launchers loaded" "warn" "requested=$launcher_count actual=$actual_launchers (some .desktop may not resolve)"
    fi

    # Query panel state
    local state
    state=$(query_panel_state)

    local screen_w left_w center_w right_w right_x2 min_w
    local lc child_count icon_sz max_rows actor_w container_w container_h
    local row_dist row_count
    screen_w=$(json_field "$state" screenWidth)
    left_w=$(json_field "$state" leftWidth)
    center_w=$(json_field "$state" centerWidth)
    right_w=$(json_field "$state" rightWidth)
    right_x2=$(json_field "$state" rightX2)
    min_w=$(json_field "$state" minWidth)
    lc=$(json_field "$state" launcherCount)
    child_count=$(json_field "$state" childCount)
    icon_sz=$(json_field "$state" iconSize)
    max_rows=$(json_field "$state" maxRows)
    actor_w=$(json_field "$state" actorW)
    container_w=$(json_field "$state" containerW)
    container_h=$(json_field "$state" containerH)
    row_dist=$(json_dict_field "$state" rowDistribution)
    row_count=$(json_dict_len "$row_dist")

    echo -e "  ${CYAN}INFO${NC} zones: left=${left_w}px center=${center_w}px right=${right_w}px | screen=${screen_w}px"
    echo -e "  ${CYAN}INFO${NC} launchers: count=$lc children=$child_count icon=${icon_sz}px maxRows=$max_rows"
    echo -e "  ${CYAN}INFO${NC} applet: actorW=${actor_w}px container=${container_w}x${container_h}px | rows=$row_count distribution=$row_dist"

    # --- Assertions ---

    # 1. min_width must be 0 (the FlowLayout squeeze fix)
    if [[ "$min_w" == "0" || "$min_w" == "0.0" ]]; then
        test_result "myactor.min_width == 0" "pass"
    else
        test_result "myactor.min_width == 0" "fail" "got $min_w"
    fi

    # 2. Right zone must be fully on-screen
    if [[ $right_x2 -le $screen_w ]]; then
        test_result "Right zone on-screen" "pass" "x2=${right_x2} <= screen=${screen_w}"
    else
        test_result "Right zone on-screen" "fail" "x2=${right_x2} > screen=${screen_w} — pushed off!"
    fi

    # 3. Right zone must have minimum usable width
    if [[ $right_w -ge $MIN_RIGHT_WIDTH ]]; then
        test_result "Right zone width >= ${MIN_RIGHT_WIDTH}px" "pass" "${right_w}px"
    else
        test_result "Right zone width >= ${MIN_RIGHT_WIDTH}px" "fail" "only ${right_w}px"
    fi

    # 4. Left zone must have minimum usable width
    if [[ $left_w -ge $MIN_LEFT_WIDTH ]]; then
        test_result "Left zone width >= ${MIN_LEFT_WIDTH}px" "pass" "${left_w}px"
    else
        test_result "Left zone width >= ${MIN_LEFT_WIDTH}px" "fail" "only ${left_w}px"
    fi

    # 5. Total zone widths should not exceed screen width
    local total=$((left_w + center_w + right_w))
    if [[ $total -le $((screen_w + 5)) ]]; then   # 5px tolerance for rounding
        test_result "Total zone width <= screen" "pass" "${total}px <= ${screen_w}px"
    else
        test_result "Total zone width <= screen" "fail" "${total}px > ${screen_w}px — overflow!"
    fi

    # 6. Launcher count matches expected (within tolerance for missing .desktop)
    if [[ $launcher_count -eq 0 ]]; then
        if [[ "$lc" == "0" ]]; then
            test_result "Launcher count matches" "pass" "0"
        else
            test_result "Launcher count matches" "fail" "expected 0, got $lc"
        fi
    else
        local diff=$((launcher_count - lc))
        if [[ $diff -lt 0 ]]; then diff=$((-diff)); fi
        if [[ $diff -le 2 ]]; then
            test_result "Launcher count matches" "pass" "expected=$launcher_count actual=$lc"
        else
            test_result "Launcher count matches" "warn" "expected=$launcher_count actual=$lc (${diff} missing .desktop files)"
        fi
    fi

    # 7. For 10+ launchers: multi-row must be engaged (icons at distinct y positions)
    if [[ $launcher_count -ge 10 ]]; then
        if [[ $row_count -ge 2 ]]; then
            test_result "Multi-row engaged" "pass" "$row_count rows"
        else
            test_result "Multi-row engaged" "warn" "only $row_count row(s) with $launcher_count launchers"
        fi
    fi

    # 8. Check for errors
    local errors
    errors=$(check_errors "$marker")
    if [[ -z "$errors" ]]; then
        test_result "No applet errors in log" "pass"
    else
        test_result "No applet errors in log" "fail" "$(echo "$errors" | wc -l) error(s)"
        echo "$errors" | head -5 | while read -r line; do
            echo -e "    ${RED}> $line${NC}"
        done
    fi

    # 9. For count=50: verify Cinnamon hasn't crashed
    if [[ $launcher_count -ge 50 ]]; then
        local cinnamon_pid
        cinnamon_pid=$(vm_ssh "pgrep -x cinnamon" 2>/dev/null || true)
        if [[ -n "$cinnamon_pid" ]]; then
            test_result "Cinnamon still running" "pass" "PID $cinnamon_pid"
        else
            test_result "Cinnamon still running" "fail" "Cinnamon process not found!"
        fi
    fi

    # 10. Content-proportional width: for small counts, applet should not inflate to zone width
    if [[ $launcher_count -eq 0 ]]; then
        if [[ $actor_w -lt 50 ]]; then
            test_result "Applet width proportional to content" "pass" "${actor_w}px (0 launchers)"
        else
            test_result "Applet width proportional to content" "fail" "${actor_w}px — should be <50px with 0 launchers"
        fi
    elif [[ $launcher_count -eq 1 ]]; then
        if [[ $actor_w -lt 80 ]]; then
            test_result "Applet width proportional to content" "pass" "${actor_w}px (1 launcher)"
        else
            test_result "Applet width proportional to content" "fail" "${actor_w}px — should be <80px with 1 launcher"
        fi
    elif [[ $launcher_count -le 5 ]]; then
        if [[ $actor_w -lt 250 ]]; then
            test_result "Applet width proportional to content" "pass" "${actor_w}px ($launcher_count launchers)"
        else
            test_result "Applet width proportional to content" "fail" "${actor_w}px — should be <250px with $launcher_count launchers"
        fi
    fi

    # 11. Take screenshot
    local screenshot_file
    screenshot_file=$(take_screenshot "${launcher_count}launchers" 2>/dev/null) || true
    if [[ -f "$screenshot_file" ]]; then
        echo -e "  ${CYAN}INFO${NC} screenshot: $screenshot_file"
    fi

    echo ""
}

# --- Main ---
main() {
    echo ""
    # Parse args
    local do_revert=false
    local counts=()
    for arg in "$@"; do
        if [[ "$arg" == "--revert" ]]; then
            do_revert=true
        elif [[ "$arg" =~ ^[0-9]+$ ]]; then
            counts+=("$arg")
        fi
    done
    if [[ ${#counts[@]} -eq 0 ]]; then
        counts=("${DEFAULT_COUNTS[@]}")
    fi

    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  VM Panel Zone Test — Panel Launchers${NC}"
    echo -e "${BOLD}══════════════════════════════════════════════${NC}"
    echo ""

    # Optional: revert to clean baseline
    if $do_revert; then
        echo -e "${CYAN}Reverting to clean-baseline snapshot...${NC}"
        "$VM_CTL" revert clean-baseline
        "$VM_CTL" start
        sleep 10   # wait for boot + Cinnamon
        echo ""
    fi

    # Ensure launchers are restored on exit (even on error/interrupt)
    trap reset_launchers EXIT INT TERM

    preflight

    # Restart Cinnamon to ensure latest code is loaded
    echo -e "${CYAN}Restarting Cinnamon to load latest applet code...${NC}"
    vm_run "cinnamon --replace &>/dev/null &" 2>/dev/null || true
    sleep 5
    echo ""

    for count in "${counts[@]}"; do
        run_test_case "$count"
    done

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
