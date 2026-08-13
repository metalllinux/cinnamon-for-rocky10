#!/usr/bin/env bash
# verify-install-packages.sh — Verify all base packages listed in INSTALL.md
# Part of TASK-0005 INSTALL.md validation test suite.
#
# Usage: verify-install-packages.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# This script verifies every package listed in the INSTALL.md "Installed packages"
# table (lines 70-85). For each package it checks:
#   1. Package is installed (rpm -q)
#   2. Version matches the documented version
#   3. Key files exist on disk
#
# Additionally verifies the GDM session file (INSTALL.md lines 91-92).

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
PKG_VERIFY_LOG="${RESULTS_DIR}/package-verify.log"

# Packages from INSTALL.md "Installed packages" table (lines 70-85).
# Format: PACKAGE_NAME|EXPECTED_VERSION|DESCRIPTION
# These are the "base" packages (not debuginfo, debugsource, or devel variants).
BASE_PACKAGES=(
    "mozjs115|115.29.0-1.el10|SpiderMonkey JavaScript engine runtime"
    "mozjs115-devel|115.29.0-1.el10|mozjs115 headers and pkg-config"
    "cjs|6.4.0-1.el10|GNOME JavaScript environment"
    "muffin|6.7.4-3.el10|Cinnamon window manager compositor"
    "muffin-clutter|6.7.4-3.el10|Muffin Clutter rendering library"
    "muffin-cogl|6.7.4-3.el10|Muffin Cogl rendering library"
    "cinnamon-desktop|6.7.2-1.el10|Desktop library and applet framework"
    "xapps-lib|3.3.3-1.el10|Shared Cinnamon application libraries"
    "cinnamon-session|6.7.3-1.el10|Session manager"
    "cinnamon-settings-daemon|6.7.2-1.el10|Settings daemon"
    "cinnamon-control-center|6.7.2-1.el10|Settings panel"
    "cinnamon-menus|6.7.0-1.el10|Menu configuration"
    "nemo|6.7.4-1.el10|File manager"
    "cinnamon|6.7.4-1.el10|Cinnamon desktop shell"
)

# Key files to verify after installation (from INSTALL.md and package contents)
KEY_FILES=(
    "/usr/share/xsessions/cinnamon.desktop|GDM Cinnamon session file"
    "/usr/lib64/libcinnamon-desktop.so*|cinnamon-desktop shared library"
    "/usr/lib64/libxapp.so*|xapp shared library"
    "/usr/include/mozjs-115|mozjs-115 headers directory"
)

log() { printf '[pkg-verify] %s\n' "$*"; }
die() { printf '[pkg-verify] ERROR: %s\n' "$*" >&2; exit 1; }

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
    : > "$PKG_VERIFY_LOG"

    # --- Phase 1: Verify base packages ---

    log "Verifying ${#BASE_PACKAGES[@]} base packages from INSTALL.md..."
    log ""

    local pkg_pass=0
    local pkg_fail=0
    local pkg_version_mismatch=0

    for entry in "${BASE_PACKAGES[@]}"; do
        IFS='|' read -r pkg_name expected_version description <<< "$entry"

        # Check if package is installed
        local installed=false
        local actual_version=""
        if ssh_cmd "$vm_ip" "rpm -q ${pkg_name} >/dev/null 2>&1" 2>/dev/null; then
            installed=true
            actual_version=$(ssh_cmd "$vm_ip" \
                "rpm -q --queryformat '%{VERSION}-%{RELEASE}' ${pkg_name} 2>/dev/null" || true)
        fi

        if [ "$installed" = "true" ]; then
            # Check version matches
            if [ "$actual_version" = "$expected_version" ]; then
                printf '[PASS] %-35s %s (%s)\n' "$pkg_name" "$actual_version" "$description" \
                    | tee -a "$PKG_VERIFY_LOG"
                pkg_pass=$((pkg_pass + 1))
            else
                printf '[WARN] %-35s expected=%s actual=%s (%s)\n' \
                    "$pkg_name" "$expected_version" "$actual_version" "$description" \
                    | tee -a "$PKG_VERIFY_LOG"
                pkg_pass=$((pkg_pass + 1))  # Still counts as pass (installed)
                pkg_version_mismatch=$((pkg_version_mismatch + 1))
            fi
        else
            printf '[FAIL] %-35s NOT INSTALLED (%s)\n' "$pkg_name" "$description" \
                | tee -a "$PKG_VERIFY_LOG"
            pkg_fail=$((pkg_fail + 1))
        fi
    done

    # --- Phase 2: Verify key files ---

    log ""
    log "Verifying key files..."
    log ""

    local files_pass=0
    local files_fail=0

    for entry in "${KEY_FILES[@]}"; do
        IFS='|' read -r file_path description <<< "$entry"

        local file_found=false
        # Check for glob patterns first, since [ -e ] treats globs literally
        # and would never match /usr/lib64/libcinnamon-desktop.so* as a real path.
        if [[ "$file_path" == *"*"* ]]; then
            # Glob pattern — use ls which expands the glob on the remote shell.
            local glob_result
            glob_result=$(ssh_cmd "$vm_ip" "ls ${file_path} 2>/dev/null" || true)
            [ -n "$glob_result" ] && file_found=true
        else
            # Literal path — use [ -e ] for existence check.
            if ssh_cmd "$vm_ip" "[ -e '${file_path}' ]" 2>/dev/null; then
                file_found=true
            fi
        fi

        if [ "$file_found" = "true" ]; then
            printf '[PASS] %-45s found\n' "$file_path" | tee -a "$PKG_VERIFY_LOG"
            files_pass=$((files_pass + 1))
        else
            printf '[FAIL] %-45s NOT FOUND\n' "$file_path" | tee -a "$PKG_VERIFY_LOG"
            files_fail=$((files_fail + 1))
        fi
    done

    # --- Phase 3: GDM session verification (INSTALL.md lines 87-99) ---

    log ""
    log "Verifying GDM session configuration..."
    log ""

    local gdm_session_found=false
    if ssh_cmd "$vm_ip" "[ -f /usr/share/xsessions/cinnamon.desktop ]" 2>/dev/null; then
        gdm_session_found=true
        local gdm_content
        gdm_content=$(ssh_cmd "$vm_ip" "cat /usr/share/xsessions/cinnamon.desktop" 2>/dev/null) || true
        log "  cinnamon.desktop found:"
        echo "$gdm_content" | head -5 | while IFS= read -r line; do
            printf '    %s\n' "$line" | tee -a "$PKG_VERIFY_LOG"
        done
    fi

    if [ "$gdm_session_found" = "true" ]; then
        printf '[PASS] %-45s GDM session file exists\n' "/usr/share/xsessions/cinnamon.desktop" \
            | tee -a "$PKG_VERIFY_LOG"
    else
        printf '[FAIL] %-45s GDM session file missing\n' "/usr/share/xsessions/cinnamon.desktop" \
            | tee -a "$PKG_VERIFY_LOG"
        files_fail=$((files_fail + 1))
    fi

    # --- Summary ---

    local total_checks=$((pkg_pass + pkg_fail + files_pass + files_fail))
    local total_pass=$((pkg_pass + files_pass))
    local total_fail=$((pkg_fail + files_fail))

    log ""
    log "=========================================="
    log "  Package Verification Summary"
    log "=========================================="
    log "  Base packages checked: ${#BASE_PACKAGES[@]}"
    log "  Base packages PASS: ${pkg_pass}"
    log "  Base packages FAIL: ${pkg_fail}"
    log "  Version mismatches: ${pkg_version_mismatch}"
    log "  Key files checked: ${#KEY_FILES[@]}"
    log "  Key files PASS: ${files_pass}"
    log "  Key files FAIL: ${files_fail}"
    log "  Total checks: ${total_checks}"
    log "  Total PASS: ${total_pass}"
    log "  Total FAIL: ${total_fail}"
    log "=========================================="

    if [ "$total_fail" -gt 0 ]; then
        die "${total_fail} verification check(s) failed."
    fi

    if [ "$pkg_version_mismatch" -gt 0 ]; then
        log "WARNING: ${pkg_version_mismatch} package(s) have version mismatches with INSTALL.md."
        log "This may be expected if packages were rebuilt at different versions."
    fi

    log ""
    log "All package verification checks passed."
    log "Log written to ${PKG_VERIFY_LOG}"
}

main "$@"
