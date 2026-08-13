#!/usr/bin/env bash
# test-install-prerequisites.sh — Install prerequisites listed in INSTALL.md on VM
# Part of TASK-0005 INSTALL.md validation test suite.
#
# Usage: test-install-prerequisites.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# This script reproduces the exact prerequisite steps from INSTALL.md:
#   1. Enable CRB repository
#   2. Install base dependencies
#
# The prerequisite package list is extracted from INSTALL.md and maintained here
# as a constant. If INSTALL.md changes, update PREREQ_PACKAGES accordingly.

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
PREREQ_LOG="${RESULTS_DIR}/prerequisites.log"

# Prerequisite packages listed in INSTALL.md, line 16-21.
# These are system-level dependencies that must be installed from EL10 repos
# before the Cinnamon RPMs can function.
#
# Alternatives considered:
#   - Parse INSTALL.md dynamically: rejected. Fragile against formatting changes,
#     and makes the script harder to audit for correctness.
#   - Copy from run-tests.sh SYSTEM_DEPS: rejected. That list is incomplete for
#     INSTALL.md validation (run-tests.sh only adds gsettings-desktop-schemas).
#
# This list matches INSTALL.md exactly. Keep in sync.
PREREQ_PACKAGES=(
    gtk3
    glib2
    graphene
    libX11
    libXrandr
    libXdamage
    libXext
    libXfixes
    libXi
    libXtst
    libICE
    libSM
    libxkbfile
    libwacom
    pipewire
    libdrm
    pulseaudio-libs
    libcanberra
    systemd
    gobject-introspection
    iso-codes
    xkeyboard-config
    cairo
    pango
    harfbuzz
    gdk-pixbuf2
    libxml2
    dbus
    atk
    at-spi2-atk
    fontconfig
    mesa-libEGL
    json-glib
    startup-notification  # INSTALL.md says "libstartup-notification" but EL10 package is "startup-notification"
    readline
)

log() { printf '[prereq] %s\n' "$*"; }
die() { printf '[prereq] ERROR: %s\n' "$*" >&2; exit 1; }

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

    # Clear previous log
    : > "$PREREQ_LOG"

    log "Installing prerequisites from INSTALL.md..."
    log "  Package count: ${#PREREQ_PACKAGES[@]}"

    # Step 1: Enable CRB repository (INSTALL.md line 10-12)
    log "Step 1: Enabling CRB repository..."
    ssh_cmd "$vm_ip" <<'REMOTE_SCRIPT' 2>&1 | tee -a "$PREREQ_LOG"
set -euo pipefail
echo "=== Enabling CRB repository ==="

# Check if CRB exists and enable it
if dnf repolist all 2>/dev/null | grep -q '\(crb\|crb-*\|powertools\|powertools-*\)'; then
    echo "CRB/repository found. Enabling..."
    if dnf config-manager --set-enabled crb 2>/dev/null; then
        echo "CRB enabled successfully."
    else
        echo "Warning: dnf config-manager --set-enabled crb failed."
        echo "Trying powertools fallback..."
        dnf config-manager --set-enabled powertools 2>/dev/null || \
            echo "Warning: Could not enable CRB or powertools."
    fi
else
    echo "Note: CRB repository not found in current repo list."
    echo "This may be acceptable for minimal cloud images."
fi

echo "=== CRB setup complete ==="
REMOTE_SCRIPT

    # Step 2: Install base dependencies (INSTALL.md line 16-21)
    log "Step 2: Installing base dependencies (${#PREREQ_PACKAGES[@]} packages)..."

    # Build the package list string for the remote command
    local pkg_list
    pkg_list=$(printf '%s ' "${PREREQ_PACKAGES[@]}")

    ssh_cmd "$vm_ip" "dnf install -y ${pkg_list}" 2>&1 | tee -a "$PREREQ_LOG"
    local dnf_rc=${PIPESTATUS[0]}

    if [ "$dnf_rc" -ne 0 ]; then
        log "ERROR: dnf install returned exit code ${dnf_rc}"
        log "Check ${PREREQ_LOG} for details."
        die "Prerequisite installation failed."
    fi

    # Step 3: Verify each prerequisite package is installed
    log "Step 3: Verifying prerequisite packages..."

    local missing=0
    for pkg in "${PREREQ_PACKAGES[@]}"; do
        if ssh_cmd "$vm_ip" "rpm -q ${pkg} >/dev/null 2>&1" 2>/dev/null; then
            printf '[OK]   %s\n' "$pkg" | tee -a "$PREREQ_LOG"
        else
            printf '[MISS] %s\n' "$pkg" | tee -a "$PREREQ_LOG"
            missing=$((missing + 1))
        fi
    done

    # Summary
    log ""
    log "=========================================="
    log "  Prerequisites Summary"
    log "=========================================="
    log "  Total packages: ${#PREREQ_PACKAGES[@]}"
    log "  Missing: ${missing}"
    log "=========================================="

    if [ "$missing" -gt 0 ]; then
        die "${missing} prerequisite package(s) failed to install."
    fi

    log "All prerequisites installed and verified."
    log "Log written to ${PREREQ_LOG}"
}

main "$@"
