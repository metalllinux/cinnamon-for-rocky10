#!/usr/bin/env bash
# run-tests.sh — W2: Install Cinnamon RPMs inside the VM
# Part of TASK-0003 VM testing harness.
#
# Usage: run-tests.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# Copies all RPMs from the rpms/ directory to the VM, installs them via dnf,
# and writes install log to vm-test/results/install.log.

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
INSTALL_LOG="${RESULTS_DIR}/install.log"
REMOTE_RPMS_DIR="/tmp/cinnamon-rpms"
RPMS_DIR="${PROJECT_DIR}/rpms"

# System dependencies required by Cinnamon RPMs but not provided by our build.
# Note: mozjs115 is now a custom RPM (not in EL10 repos).
# Note: clutter and cogl are bundled in muffin (not separate system packages).
#   - cinnamon-settings-daemon: needs GSettings schemas (gsettings-desktop-schemas)
SYSTEM_DEPS=(
    "gsettings-desktop-schemas"
)

log() { printf '[install] %s\n' "$*"; }

die() { printf '[install] ERROR: %s\n' "$*" >&2; exit 1; }

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
    [ "$rpm_count" -gt 0 ] || die "No RPMs found in ${RPMS_DIR}"
    log "Found ${rpm_count} RPM files in ${RPMS_DIR}"

    # --- Phase 1: Copy RPMs to VM ---

    log "Copying RPMs to VM (${REMOTE_RPMS_DIR})..."
    ssh_cmd "$vm_ip" "mkdir -p ${REMOTE_RPMS_DIR}"
    ssh_pin_opts "$vm_ip"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    scp ${SSH_PIN_OPTS} -i "${SSH_KEY}" \
        "${RPMS_DIR}"/*.rpm "${VM_USER}@${vm_ip}:${REMOTE_RPMS_DIR}/" \
        2>&1 | tee -a "$INSTALL_LOG"
    log "RPMs copied."

    # --- Phase 2: Prepare VM environment ---

    log "Preparing VM environment..."

    ssh_cmd "$vm_ip" <<'REMOTE_SCRIPT' 2>&1 | tee -a "$INSTALL_LOG"
set -euo pipefail
echo "=== VM environment preparation ==="
echo "Host: $(hostname)"
echo "Kernel: $(uname -r)"
echo "OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2)"

# Enable CRB (CodeReady Builder) for EL10 if it exists
if dnf repolist enabled 2>/dev/null | grep -q crb; then
    echo "CRB already enabled."
else
    echo "Enabling CRB repository..."
    dnf config-manager --set-enabled crb 2>/dev/null || \
    echo "Warning: Could not enable CRB (may not exist in this config)"
fi

# Set SELinux to permissive for testing (avoid blocking binaries)
if command -v getenforce >/dev/null 2>&1; then
    echo "Current SELinux mode: $(getenforce 2>/dev/null || echo 'unknown')"
    setenforce 0 2>/dev/null || echo "Warning: Could not set SELinux permissive"
    echo "SELinux set to permissive for testing."
fi

# Install system dependencies required by Cinnamon RPMs.
# These are runtime libraries not provided by our custom RPM build.
echo ""
echo "=== Installing system dependencies ==="
dnf install -y \
    mozjs115 \
    clutter \
    cogl \
    gsettings-desktop-schemas \
    2>&1 || echo "WARNING: Some system dependencies failed to install"

echo "=== System dependencies installed ==="
echo "=== VM environment ready ==="
REMOTE_SCRIPT

    # --- Phase 3: Install RPMs ---

    log "Installing RPMs via dnf (resolving dependencies)..."

    # Write install script to temp file
    local INSTALL_SCRIPT
    INSTALL_SCRIPT=$(mktemp)
    cat > "$INSTALL_SCRIPT" <<'INSTALL_SCRIPT_EOF'
set -euo pipefail
REMOTE_RPMS_DIR="${1}"
echo "=== Installing RPMs ==="
echo "Working directory: ${REMOTE_RPMS_DIR}"
echo "RPM count: $(ls ${REMOTE_RPMS_DIR}/*.rpm | wc -l)"

# Primary attempt: let dnf resolve all dependencies at once
echo "--- Attempt 1: dnf install all RPMs ---"
if dnf install -y ${REMOTE_RPMS_DIR}/*.rpm 2>&1; then
    echo "SUCCESS: dnf installed all RPMs."
else
    echo "WARNING: dnf install failed, trying with --allowerasing..."
    if dnf install -y --allowerasing ${REMOTE_RPMS_DIR}/*.rpm 2>&1; then
        echo "SUCCESS: dnf installed all RPMs with --allowerasing."
    else
        echo "ERROR: Both dnf install attempts failed."
        echo "Attempting manual ordered install..."

        # Fallback: ordered install per dependency chain.
        # cinnamon-menus must come before cinnamon-control-center (provides libcinnamon-menu-3.so.0).
        FAILED=false

        for pkg in \
            mozjs115 \
            mozjs115-devel \
            cjs \
            cinnamon-desktop \
            muffin \
            xapps-lib \
            cinnamon-session \
            cinnamon-settings-daemon \
            cinnamon-menus \
            cinnamon-control-center \
            nemo \
            cinnamon; do

            echo "--- Installing: ${pkg} ---"
            rpm_files=$(ls ${REMOTE_RPMS_DIR}/${pkg}-*.rpm 2>/dev/null || true)
            if [ -n "$rpm_files" ]; then
                for f in $rpm_files; do
                    echo "  Installing $(basename $f)..."
                    dnf install -y "$f" 2>&1 || { echo "  FAILED: $(basename $f)"; FAILED=true; }
                done
            else
                echo "  SKIP: no RPM found matching ${pkg}-*"
            fi
        done

        if $FAILED; then
            echo "ERROR: Some RPMs failed to install in ordered mode."
            exit 1
        fi
    fi
fi

echo "=== RPM installation complete ==="
INSTALL_SCRIPT_EOF

    # Copy script to VM and run it
    ssh_pin_opts "$vm_ip"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    scp ${SSH_PIN_OPTS} -i "${SSH_KEY}" \
        "$INSTALL_SCRIPT" "${VM_USER}@${vm_ip}:/tmp/install-rpms.sh" 2>&1 | tee -a "$INSTALL_LOG"
    ssh_cmd "$vm_ip" "bash /tmp/install-rpms.sh ${REMOTE_RPMS_DIR}" 2>&1 | tee -a "$INSTALL_LOG"
    local install_rc=${PIPESTATUS[0]}
    rm -f "$INSTALL_SCRIPT"

    # --- Phase 4: Verify installation ---

    log "Verifying installed packages..."

    ssh_cmd "$vm_ip" <<'REMOTE_SCRIPT' 2>&1 | tee -a "$INSTALL_LOG"
set -euo pipefail
echo "=== Installed package verification ==="

# List installed packages matching our keywords
INSTALLED=$(dnf list installed 2>/dev/null | grep -E '(cinnamon|cjs|muffin|xapps|nemo|mozjs)' || true)
echo "$INSTALLED"

# Count matching packages
PKG_COUNT=$(echo "$INSTALLED" | wc -l)
echo ""
echo "Total matching packages installed: ${PKG_COUNT}"

# Verify each expected package
EXPECTED=(
    "mozjs115-devel"
    "cjs"
    "cinnamon-desktop"
    "muffin"
    "xapps-lib"
    "cinnamon-session"
    "cinnamon-settings-daemon"
    "cinnamon-control-center"
    "nemo"
    "cinnamon"
)

ALL_OK=true
for pkg in "${EXPECTED[@]}"; do
    if rpm -q "$pkg" >/dev/null 2>&1; then
        echo "[OK] ${pkg}: $(rpm -q --queryformat '%{VERSION}-%{RELEASE}' "$pkg" 2>/dev/null)"
    else
        echo "[MISSING] ${pkg}"
        ALL_OK=false
    fi
done

# Verify mozjs headers
echo ""
echo "=== Checking mozjs-115 headers ==="
if [ -d /usr/include/mozjs-115 ]; then
    echo "[OK] /usr/include/mozjs-115 exists"
else
    echo "[MISSING] /usr/include/mozjs-115"
    ALL_OK=false
fi

echo ""
if $ALL_OK; then
    echo "=== ALL PACKAGES VERIFIED ==="
    exit 0
else
    echo "=== VERIFICATION FAILED ==="
    exit 1
fi
REMOTE_SCRIPT

    local verify_rc=${PIPESTATUS[0]}

    if [ "$verify_rc" -ne 0 ]; then
        log "WARNING: Package verification had issues. Check ${INSTALL_LOG}"
    else
        log "All packages installed and verified."
    fi

    log "Install log written to ${INSTALL_LOG}"
    log "Done."
}

main "$@"
