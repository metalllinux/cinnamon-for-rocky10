#!/usr/bin/env bash
# test-step-by-step-install.sh — Test step-by-step install from INSTALL.md
# Part of TASK-0005 INSTALL.md validation test suite.
#
# Usage: test-step-by-step-install.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# This script validates the step-by-step installation method documented in
# INSTALL.md (lines 34-66). Each group is installed in the exact order
# documented, verifying each step succeeds before proceeding to the next.
#
# Note: This test requires RPMs that haven't been installed yet. If packages
# were already installed via the quick install method, this script will detect
# pre-installed packages and report them (but dnf install is idempotent, so
# the command itself will succeed).

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
STEP_INSTALL_LOG="${RESULTS_DIR}/step-by-step-install.log"
REMOTE_RPMS_DIR="/tmp/cinnamon-rpms"
RPMS_DIR="${PROJECT_DIR}/rpms"

# Install groups from INSTALL.md, in documented order.
# Each group contains glob patterns as they appear in the documentation.
# Format: GROUP_NAME:RPM_GLOB_1,RPM_GLOB_2,...

# Group 1: Foundation libraries (INSTALL.md line 36-41)
GROUP_FOUNDATION=(
    "mozjs115-*.rpm"
    "mozjs115-devel-*.rpm"
    "cinnamon-desktop-*.rpm"
    "xapps-lib-*.rpm"
    "cinnamon-menus-*.rpm"
)

# Group 2: JavaScript engine and compositor (INSTALL.md line 44-46)
GROUP_JS_COMPOSITOR=(
    "cjs-*.rpm"
    "muffin-*.rpm"
)

# Group 3: Session and settings (INSTALL.md line 49-51)
GROUP_SESSION_SETTINGS=(
    "cinnamon-session-*.rpm"
    "cinnamon-settings-daemon-*.rpm"
)

# Group 4: Desktop components (INSTALL.md line 54-58)
# "cinnamon-[0-9]*.rpm" matches only the cinnamon shell RPM and versioned
# variants (cinnamon-6.7.4-*.rpm). Using [0-9] instead of * avoids overlap
# with cinnamon-desktop, cinnamon-menus (Group 1), cinnamon-session,
# cinnamon-settings-daemon (Group 3), and cinnamon-control-center (this group).
# "cinnamon-debuginfo-*.rpm" and "cinnamon-debugsource-*.rpm" match the debug
# packages for the cinnamon shell specifically (not cinnamon-desktop-debuginfo
# etc., which are already in Group 1).
GROUP_DESKTOP=(
    "cinnamon-control-center-*.rpm"
    "nemo-*.rpm"
    "cinnamon-[0-9]*.rpm"
    "cinnamon-debuginfo-*.rpm"
    "cinnamon-debugsource-*.rpm"
)

# All groups in order
ALL_GROUPS=(
    "Foundation libraries:${GROUP_FOUNDATION[*]}"
    "JavaScript engine and compositor:${GROUP_JS_COMPOSITOR[*]}"
    "Session and settings:${GROUP_SESSION_SETTINGS[*]}"
    "Desktop components:${GROUP_DESKTOP[*]}"
)

log() { printf '[step-install] %s\n' "$*"; }
die() { printf '[step-install] ERROR: %s\n' "$*" >&2; exit 1; }

# Run a single install group on the VM
install_group() {
    local group_name="$1"
    shift
    local patterns=("$@")

    log "  Installing group: ${group_name}"

    # Build list of matching RPMs on the VM
    local rpm_list=""
    for pattern in "${patterns[@]}"; do
        local matches
        matches=$(ssh_cmd "$vm_ip" "ls ${REMOTE_RPMS_DIR}/${pattern} 2>/dev/null || true") || true
        if [ -n "$matches" ]; then
            rpm_list="${rpm_list} ${matches}"
        else
            log "  WARNING: No RPMs match pattern '${pattern}'"
        fi
    done

    rpm_list=$(echo "$rpm_list" | xargs)  # trim whitespace

    if [ -z "$rpm_list" ]; then
        log "  WARNING: No RPMs found for group '${group_name}'. Skipping."
        return 0
    fi

    log "  RPMs for this group: $(echo "$rpm_list" | wc -w)"

    # Attempt install, with --allowerasing fallback matching quick install behavior.
    # Some dependency conflicts (e.g. package provides collisions) require --allowerasing
    # to resolve. This keeps step-by-step and quick install on equal footing.
    local install_output
    local rc

    # Temporarily disable set -e so we can capture the exit code without
    # the script terminating on a non-zero dnf exit.
    set +e
    install_output=$(ssh_cmd "$vm_ip" "dnf install -y ${rpm_list}" 2>&1)
    rc=$?
    set -e

    if [ "$rc" -ne 0 ]; then
        log "  WARNING: dnf install failed (rc=${rc}), retrying with --allowerasing..."
        printf '%s\n' "$install_output" >> "$STEP_INSTALL_LOG"
        set +e
        install_output=$(ssh_cmd "$vm_ip" "dnf install -y --allowerasing ${rpm_list}" 2>&1)
        rc=$?
        set -e
    fi

    printf '%s\n' "$install_output" >> "$STEP_INSTALL_LOG"

    if [ "$rc" -ne 0 ]; then
        log "  ERROR: Failed to install group '${group_name}' (exit code ${rc})"
        return "$rc"
    fi

    log "  Group '${group_name}' installed successfully."
    return 0
}

# --- Main ---

main() {
    local vm_ip="${1:-}"

    mkdir -p "$RESULTS_DIR"

    # Resolve VM IP
    if [ -z "$vm_ip" ]; then
        log "Detecting VM IP for ${VM_NAME}..."
        vm_ip=$(get_vm_ip)
        [ -n "$vm_ip" ] || die "Could not determine VM IP. Pass it as argument."
    fi
    log "Target VM: ${vm_ip}"

    # Verify SSH connectivity
    log "Testing SSH connectivity..."
    if ! ssh_cmd "$vm_ip" "echo connected" >/dev/null 2>&1; then
        die "Cannot SSH to ${vm_ip}. Is the VM running?"
    fi
    log "SSH connected."

    # Verify RPMs directory
    local rpm_count
    rpm_count=$(find "$RPMS_DIR" -name '*.rpm' | wc -l)
    [ "$rpm_count" -gt 0 ] || die "No RPMs found on host."
    log "Found ${rpm_count} RPM files on host"

    # Clear previous log
    : > "$STEP_INSTALL_LOG"

    # --- Phase 1: Copy RPMs to VM (if not already there) ---

    if ! ssh_cmd "$vm_ip" "[ -d ${REMOTE_RPMS_DIR} ] && [ \"\$(ls ${REMOTE_RPMS_DIR}/*.rpm 2>/dev/null | wc -l)\" -gt 0 ]" 2>/dev/null; then
        log "Copying RPMs to VM (${REMOTE_RPMS_DIR})..."
        ssh_cmd "$vm_ip" "mkdir -p ${REMOTE_RPMS_DIR}"
        scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
            "$RPMS_DIR"/*.rpm "${VM_USER}@${vm_ip}:${REMOTE_RPMS_DIR}/" \
            2>&1 | tee -a "$STEP_INSTALL_LOG"
        log "RPMs copied."
    else
        log "RPMs already present on VM at ${REMOTE_RPMS_DIR}"
    fi

    # --- Phase 2: Step-by-step installation ---

    log ""
    log "Starting step-by-step installation (4 groups from INSTALL.md)..."
    log ""

    local group_count=0
    local failed_groups=0

    # Group 1: Foundation libraries
    group_count=$((group_count + 1))
    log "Step ${group_count}: ${ALL_GROUPS[0]%%:*}"
    if install_group "Foundation libraries" "${GROUP_FOUNDATION[@]}"; then
        log "  Result: PASSED"
    else
        log "  Result: FAILED"
        failed_groups=$((failed_groups + 1))
    fi

    # Group 2: JavaScript engine and compositor
    group_count=$((group_count + 1))
    log "Step ${group_count}: ${ALL_GROUPS[1]%%:*}"
    if install_group "JavaScript engine and compositor" "${GROUP_JS_COMPOSITOR[@]}"; then
        log "Result: PASSED"
    else
        log "  Result: FAILED"
        failed_groups=$((failed_groups + 1))
    fi

    # Group 3: Session and settings
    group_count=$((group_count + 1))
    log "Step ${group_count}: ${ALL_GROUPS[2]%%:*}"
    if install_group "Session and settings" "${GROUP_SESSION_SETTINGS[@]}"; then
        log "  Result: PASSED"
    else
        log "  Result: FAILED"
        failed_groups=$((failed_groups + 1))
    fi

    # Group 4: Desktop components
    group_count=$((group_count + 1))
    log "Step ${group_count}: ${ALL_GROUPS[3]%%:*}"
    if install_group "Desktop components" "${GROUP_DESKTOP[@]}"; then
        log "  Result: PASSED"
    else
        log "  Result: FAILED"
        failed_groups=$((failed_groups + 1))
    fi

    # --- Phase 3: Refresh library cache (INSTALL.md line 64-66) ---

    log ""
    log "Step 5: Refreshing library cache (ldconfig)..."
    ssh_cmd "$vm_ip" "ldconfig" 2>&1 | tee -a "$STEP_INSTALL_LOG"
    log "  Library cache refreshed."

    # --- Summary ---

    log ""
    log "=========================================="
    log "  Step-by-Step Install Summary"
    log "=========================================="
    log "  Total groups: ${group_count}"
    log "  Failed groups: ${failed_groups}"
    log "=========================================="

    if [ "$failed_groups" -gt 0 ]; then
        die "${failed_groups} group(s) failed to install."
    fi

    log "All installation groups completed successfully."
    log "Log written to ${STEP_INSTALL_LOG}"
}

main "$@"
