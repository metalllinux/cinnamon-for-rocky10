#!/usr/bin/env bash
# verify-binaries.sh — W3: Verify Cinnamon RPM binaries inside the VM
# Part of TASK-0003 VM testing harness.
#
# Usage: verify-binaries.sh [VM_IP]
#   VM_IP: optional IP override. Auto-detected from libvirt DHCP leases if omitted.
#
# For each expected binary, runs:
#   1. ldd check for missing shared libraries
#   2. --version or --help invocation to confirm the binary runs
#
# X11-dependent binaries are wrapped in xvfb-run.
# Results written to vm-test/results/verify.log in structured PASS/FAIL format.

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
VERIFY_LOG="${RESULTS_DIR}/verify.log"

# Binary definitions: name|version_flag|needs_xvfb
# needs_xvfb: yes for X11-dependent binaries, no for CLI tools
# Note: cinnamon-settings-daemon installs as csd-* binaries, not a single
# cinnamon-settings-daemon binary. We check csd-xsettings as representative.
# cinnamon-session exits 1 on --version by design (it is a session manager,
# not a CLI tool). We check it with ldd only.
BINARY_DEFS=(
    "cjs|--version|no"
    "muffin|--version|yes"
    "cinnamon-session|NONE|no"
    "csd-xsettings|NONE|no"
    "cinnamon-control-center|--version|yes"
    "nemo|--version|yes"
    "cinnamon|--version|yes"
)

# Library checks: path_pattern|description
# Use dot (.) not hyphen (-) for versioned shared libraries.
LIB_CHECKS=(
    "/usr/lib64/libcinnamon-desktop.so*|cinnamon-desktop library"
    "/usr/lib64/libxapp.so*|xapp library"
)

# SSH helper — uses key-based auth.
ssh_cmd() {
    local target="$1"; shift
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 -i "${SSH_KEY}" "${VM_USER}@${target}" "$@"
}

log() { printf '[verify] %s\n' "$*"; }

die() { printf '[verify] ERROR: %s\n' "$*" >&2; exit 1; }

# --- Main ---

main() {
    local vm_ip="${1:-}"

    mkdir -p "$RESULTS_DIR"

    if [ -z "$vm_ip" ]; then
        log "Detecting VM IP..."
        vm_ip=$(get_vm_ip)
        [ -n "$vm_ip" ] || die "Could not determine VM IP."
    fi
    log "Target VM: ${vm_ip}"

    # Verify connectivity
    if ! ssh_cmd "$vm_ip" "echo connected" >/dev/null 2>&1; then
        die "Cannot SSH to ${vm_ip}."
    fi

    # Clear previous results
    : > "$VERIFY_LOG"

    log "Starting binary verification..."

    # --- Install xvfb-run inside VM if needed ---
    # EL10 does not ship xorg-x11-server-Xvfb in standard repos.
    # Attempt install but do not fail if unavailable.

    log "Ensuring Xvfb is available inside VM..."
    ssh_cmd "$vm_ip" <<'REMOTE' || true
if ! command -v xvfb-run >/dev/null 2>&1; then
    echo "Attempting to install xorg-x11-server-Xvfb..."
    if dnf install -y xorg-x11-server-Xvfb 2>&1; then
        echo "Xvfb installed successfully."
    else
        echo "WARNING: Xvfb not available in this repository set."
        echo "X11-dependent binary tests will be skipped."
    fi
fi
REMOTE

    # Check if xvfb-run is actually available in the VM
    local xvfb_available=false
    if ssh_cmd "$vm_ip" "command -v xvfb-run >/dev/null 2>&1" 2>/dev/null; then
        xvfb_available=true
        log "Xvfb is available."
    else
        log "WARNING: Xvfb is not available. X11-dependent --version checks will be skipped."
    fi

    # --- Binary checks ---

    local total_checks=0
    local pass_count=0
    local fail_count=0
    local skip_count=0

    log "Checking binaries..."

    for entry in "${BINARY_DEFS[@]}"; do
        IFS='|' read -r binary version_flag needs_xvfb <<< "$entry"

        # --- Step 1: Check if binary exists in VM ---
        # Shadow blocker fix: verify binary exists before running ldd or --version.
        # Without this check, a missing binary causes ldd to receive no argument,
        # which prints a usage message (no "not found" text), resulting in false PASS.
        local bin_path
        bin_path=$(ssh_cmd "$vm_ip" "command -v ${binary} 2>/dev/null" || true)

        if [ -z "$bin_path" ]; then
            # Binary not found — fail both checks immediately.
            total_checks=$((total_checks + 1))
            printf '[FAIL] %-40s ldd: binary not found\n' "${binary}"
            fail_count=$((fail_count + 1))

            total_checks=$((total_checks + 1))
            printf '[FAIL] %-40s %s: binary not found\n' "${binary}" "${version_flag}"
            fail_count=$((fail_count + 1))
            continue
        fi

        # Mark version check as N/A for binaries with no useful version flag
        local do_version=true
        if [ "$version_flag" = "NONE" ]; then
            do_version=false
        fi

        # --- Step 2: ldd check (binary exists, use resolved path) ---
        # Note: ldd does NOT need Xvfb. It reads the ELF binary without executing it.

        total_checks=$((total_checks + 1))
        log "  ldd check: ${binary} (${bin_path})"

        local ldd_result
        ldd_result=$(ssh_cmd "$vm_ip" \
            "ldd '${bin_path}' 2>&1 | grep 'not found'" || true)

        local missing_libs=0
        if [ -n "$ldd_result" ]; then
            missing_libs=$(echo "$ldd_result" | wc -l)
        fi

        if [ "$missing_libs" -eq 0 ]; then
            printf '[PASS] %-40s ldd: 0 missing libraries\n' "${binary}"
            pass_count=$((pass_count + 1))
        else
            printf '[FAIL] %-40s ldd: %d missing libraries\n' "${binary}" "$missing_libs"
            if [ -n "$ldd_result" ]; then
                echo "       Details:"
                echo "$ldd_result" | head -5 | while IFS= read -r line; do
                    echo "         $line"
                done
            fi
            fail_count=$((fail_count + 1))
        fi

        # --- Step 3: version check (binary exists) ---

        total_checks=$((total_checks + 1))

        # Skip: no useful version flag for this binary.
        if [ "$do_version" = "false" ]; then
            log "  version check: ${binary} -- SKIP (no --version flag)"
            printf '[SKIP] %-40s version: no version flag for this binary\n' \
                "${binary}"
            skip_count=$((skip_count + 1))
        # Skip X11-dependent binaries if Xvfb is not available.
        elif [ "$needs_xvfb" = "yes" ] && [ "$xvfb_available" = "false" ]; then
            log "  version check: ${binary} ${version_flag} -- SKIP (Xvfb unavailable)"
            printf '[SKIP] %-40s %s: Xvfb not available in EL10 repos\n' \
                "${binary}" "${version_flag}"
            skip_count=$((skip_count + 1))
        else
            log "  version check: ${binary} ${version_flag}"

            # Capture both exit code and output in a single remote invocation.
            # Remote command: capture output, echo exit code on first line,
            # then print the captured output. Local parsing splits on first line.
            local version_combined
            if [ "$needs_xvfb" = "yes" ]; then
                version_combined=$(ssh_cmd "$vm_ip" \
                    "OUT=\$(xvfb-run -a ${binary} ${version_flag} 2>&1); echo \"\$?\"; printf '%s' \"\$OUT\"" || true)
            else
                version_combined=$(ssh_cmd "$vm_ip" \
                    "OUT=\$(${binary} ${version_flag} 2>&1); echo \"\$?\"; printf '%s' \"\$OUT\"" || true)
            fi

            local version_rc
            version_rc=$(echo "$version_combined" | head -1)
            version_rc=${version_rc:-1}
            local version_output
            version_output=$(echo "$version_combined" | tail -n +2)

            # Shadow blocker fix: check exit code AND output content.
            # Previously, error output like "bash: cjs: command not found" was
            # treated as a valid version string because it was non-empty.
            # Now we verify binary existence first (Step 1), and here we check
            # both the exit code and output to avoid false positives.
            if [ "$version_rc" -eq 0 ] && [ -n "$version_output" ]; then
                local version_line
                version_line=$(echo "$version_output" | head -1 | sed 's/^[[:space:]]*//')
                printf '[PASS] %-40s %s: %s\n' "${binary}" "${version_flag}" "$version_line"
                pass_count=$((pass_count + 1))
            else
                printf '[FAIL] %-40s %s: exit code %d, output: %s\n' \
                    "${binary}" "${version_flag}" "$version_rc" "${version_output:-<empty>}"
                fail_count=$((fail_count + 1))
            fi
        fi
    done

    # --- Library checks ---

    log "Checking libraries..."

    for check in "${LIB_CHECKS[@]}"; do
        IFS='|' read -r path_pattern description <<< "$check"
        total_checks=$((total_checks + 1))

        local lib_result
        lib_result=$(ssh_cmd "$vm_ip" "ls ${path_pattern} 2>/dev/null || true") || true

        if [ -n "$lib_result" ]; then
            printf '[PASS] %-40s library: found\n' "$description"
            pass_count=$((pass_count + 1))
        else
            printf '[FAIL] %-40s library: not found\n' "$description"
            fail_count=$((fail_count + 1))
        fi
    done

    # --- Summary ---

    local summary_rc=0
    log ""
    log "=========================================="
    log "  Verification Summary"
    log "=========================================="
    log "  Total checks: ${total_checks}"
    log "  PASS: ${pass_count}"
    log "  FAIL: ${fail_count}"
    log "  SKIP: ${skip_count}"
    log "=========================================="

    if [ "$fail_count" -gt 0 ]; then
        summary_rc=1
    fi

    printf '\n=== SUMMARY ===\nTotal: %d | PASS: %d | FAIL: %d | SKIP: %d\n' \
        "$total_checks" "$pass_count" "$fail_count" "$skip_count"

    log "Results written to ${VERIFY_LOG}"

    return "$summary_rc"
}

main "$@"
