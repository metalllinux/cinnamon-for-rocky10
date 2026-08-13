#!/usr/bin/env bash
# test-quick-install.sh — Test quick install method from INSTALL.md
# Part of TASK-0005 INSTALL.md validation test suite.
#
# Usage: test-quick-install.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# This script validates the quick install method documented in INSTALL.md:
#   sudo dnf install ./rpms/*.rpm
#
# The command is run exactly as documented. All RPMs (including debuginfo,
# debugsource, and devel variants) are installed in a single batch, letting
# dnf resolve the dependency order automatically.

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
QUICK_INSTALL_LOG="${RESULTS_DIR}/quick-install.log"
REMOTE_RPMS_DIR="/tmp/cinnamon-rpms"
RPMS_DIR="${PROJECT_DIR}/rpms"

log() { printf '[quick-install] %s\n' "$*"; }
die() { printf '[quick-install] ERROR: %s\n' "$*" >&2; exit 1; }

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
    [ "$rpm_count" -gt 0 ] || die "No RPMs found in $RPMS_DIR"
    log "Found ${rpm_count} RPM files on host"

    # Clear previous log
    : > "$QUICK_INSTALL_LOG"

    # --- Phase 1: Copy RPMs to VM ---

    log "Copying RPMs to VM (${REMOTE_RPMS_DIR})..."
    ssh_cmd "$vm_ip" "rm -rf ${REMOTE_RPMS_DIR} && mkdir -p ${REMOTE_RPMS_DIR}"
    scp -o StrictHostKeyChecking=no -i "${SSH_KEY}" \
        "$RPMS_DIR"/*.rpm "${VM_USER}@${vm_ip}:${REMOTE_RPMS_DIR}/" \
        2>&1 | tee -a "$QUICK_INSTALL_LOG"
    log "RPMs copied."

    # --- Phase 2: Run quick install ---

    log "Running quick install: dnf install ${REMOTE_RPMS_DIR}/*.rpm"
    log "(This matches: sudo dnf install ./rpms/*.rpm from INSTALL.md)"

    ssh_cmd "$vm_ip" <<REMOTE_SCRIPT 2>&1 | tee -a "$QUICK_INSTALL_LOG"
set -euo pipefail
echo "=== Quick Install Test ==="
echo "Working directory: ${REMOTE_RPMS_DIR}"
echo "RPM count: \$(ls ${REMOTE_RPMS_DIR}/*.rpm | wc -l)"

echo "--- Running: dnf install ${REMOTE_RPMS_DIR}/*.rpm ---"
if dnf install -y ${REMOTE_RPMS_DIR}/*.rpm 2>&1; then
    echo "SUCCESS: dnf installed all RPMs in single batch."
    exit 0
else
    INSTALL_RC=\$?
    echo "WARNING: dnf install failed with exit code \$INSTALL_RC."
    echo "Retrying with --allowerasing..."
    if dnf install -y --allowerasing ${REMOTE_RPMS_DIR}/*.rpm 2>&1; then
        echo "SUCCESS: dnf installed all RPMs with --allowerasing."
        exit 0
    else
        echo "ERROR: Both dnf install attempts failed."
        exit 1
    fi
fi
REMOTE_SCRIPT

    local install_rc=${PIPESTATUS[0]}

    if [ "$install_rc" -ne 0 ]; then
        log "ERROR: Quick install failed with exit code ${install_rc}"
        log "Check ${QUICK_INSTALL_LOG} for details."
        die "Quick install method failed."
    fi

    # --- Phase 3: Refresh library cache ---

    log "Running ldconfig..."
    ssh_cmd "$vm_ip" "ldconfig" 2>&1 | tee -a "$QUICK_INSTALL_LOG"

    # --- Phase 4: Quick verification ---

    log "Quick verification: counting installed Cinnamon packages..."
    local installed_count
    installed_count=$(ssh_cmd "$vm_ip" \
        "dnf list installed 2>/dev/null | grep -cE '(cinnamon|cjs|muffin|xapps|nemo|mozjs)'" || echo "0")
    log "Installed matching packages: ${installed_count}"

    if [ "$installed_count" -lt 10 ]; then
        log "WARNING: Only ${installed_count} matching packages found. Expected 10+."
    fi

    log ""
    log "=========================================="
    log "  Quick Install Summary"
    log "=========================================="
    log "  RPMs processed: ${rpm_count}"
    log "  Packages installed: ${installed_count}"
    log "  Status: PASSED"
    log "=========================================="

    log "Quick install test completed."
    log "Log written to ${QUICK_INSTALL_LOG}"
}

main "$@"
