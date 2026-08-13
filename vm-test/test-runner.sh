#!/usr/bin/env bash
# test-runner.sh — W4: Orchestrator for Cinnamon VM testing
# Part of TASK-0003 VM testing harness.
#
# Usage: test-runner.sh [--provision] [--install] [--verify] [--destroy]
#   Without flags: runs all phases (provision, install, verify) sequentially.
#   With flags: runs only the specified phase(s).
#   --destroy: destroys the VM after all other phases complete.
#
# Output is captured to vm-test/results/ with timestamps.

set -euo pipefail

# --- Constants ---

PROJECT_DIR="${HOME}/Linux/projects/cinnamon-for-rocky10"
VM_TEST_DIR="${PROJECT_DIR}/vm-test"
RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
SCRIPTS=(
    "provision-vm.sh"
    "run-tests.sh"
    "verify-binaries.sh"
)

# --- Flags ---

DO_PROVISION=false
DO_INSTALL=false
DO_VERIFY=false
DO_DESTROY=false
VM_IP=""

# --- Helpers ---

log() { printf '[runner] %s\n' "$*"; }
die() { printf '[runner] ERROR: %s\n' "$*" >&2; exit 1; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Runs the Cinnamon RPM VM test suite. Without options, runs all phases.

Options:
  --provision    Provision a fresh Rocky Linux 10.2 VM (slow, ~20-30 min)
  --install      Copy RPMs to VM and install them
  --verify       Run binary verification (ldd, --version checks)
  --destroy      Destroy the VM after completing other phases
  --ip IP        Use specific VM IP instead of auto-detection
  -h, --help     Show this help

Examples:
  $(basename "$0")                  # Run all phases
  $(basename "$0") --install --verify  # Skip provisioning, just test
  $(basename "$0") --provision --destroy # Provision and then clean up
EOF
}

# --- Parse arguments ---

parse_args() {
    if [ $# -eq 0 ]; then
        DO_PROVISION=true
        DO_INSTALL=true
        DO_VERIFY=true
        return
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --provision)  DO_PROVISION=true; shift ;;
            --install)    DO_INSTALL=true; shift ;;
            --verify)     DO_VERIFY=true; shift ;;
            --destroy)    DO_DESTROY=true; shift ;;
            --ip)         VM_IP="${2:-}"; shift 2 ;;
            -h|--help)    show_usage; exit 0 ;;
            *)            die "Unknown option: $1" ;;
        esac
    done

    if ! $DO_PROVISION && ! $DO_INSTALL && ! $DO_VERIFY && ! $DO_DESTROY; then
        die "No phases selected. Use --provision, --install, --verify, or --destroy."
    fi
}

# --- Phase runners ---

run_provision() {
    log "============================================"
    log "  Phase 1: VM Provisioning"
    log "============================================"
    log "Started at: $(timestamp)"

    local provision_log="${RESULTS_DIR}/provision.log"
    mkdir -p "$RESULTS_DIR"

    if "$VM_TEST_DIR/provision-vm.sh" 2>&1 | tee "$provision_log"; then
        log "Provisioning completed successfully."

        # Capture VM IP for subsequent phases
        if [ -z "$VM_IP" ]; then
            VM_IP=$(grep 'IP:' "$provision_log" | tail -1 | awk '{print $NF}')
            if [ -n "$VM_IP" ]; then
                log "Captured VM IP: ${VM_IP}"
            fi
        fi
    else
        die "Provisioning failed. Check ${provision_log}"
    fi

    log "Finished at: $(timestamp)"
}

run_install() {
    log "============================================"
    log "  Phase 2: RPM Installation"
    log "============================================"
    log "Started at: $(timestamp)"

    local install_log="${RESULTS_DIR}/install.log"
    mkdir -p "$RESULTS_DIR"

    : > "$install_log"
    echo "Install phase started at: $(timestamp)" >> "$install_log"

    if "$VM_TEST_DIR/run-tests.sh" "${VM_IP}" 2>&1 | tee -a "$install_log"; then
        log "Installation completed successfully."
    else
        log "WARNING: Installation had errors. Check ${install_log}"
        die "Installation failed. Aborting remaining phases."
    fi

    echo "Install phase completed at: $(timestamp)" >> "$install_log"
    log "Finished at: $(timestamp)"
}

run_verify() {
    log "============================================"
    log "  Phase 3: Binary Verification"
    log "============================================"
    log "Started at: $(timestamp)"

    local verify_log="${RESULTS_DIR}/verify.log"
    mkdir -p "$RESULTS_DIR"

    : > "$verify_log"
    echo "Verification phase started at: $(timestamp)" >> "$verify_log"

    local verify_rc=0
    "$VM_TEST_DIR/verify-binaries.sh" "${VM_IP}" 2>&1 | tee -a "$verify_log" || verify_rc=$?

    echo "Verification phase completed at: $(timestamp)" >> "$verify_log"
    echo "Exit code: ${verify_rc}" >> "$verify_log"

    if [ "$verify_rc" -eq 0 ]; then
        log "All verification checks passed."
    else
        log "Some verification checks failed. See ${verify_log}"
    fi

    log "Finished at: $(timestamp)"
    return "$verify_rc"
}

run_destroy() {
    log "============================================"
    log "  Cleanup: Destroying VM"
    log "============================================"

    if "$VM_TEST_DIR/provision-vm.sh" --destroy 2>&1; then
        log "VM destroyed."
    else
        log "WARNING: VM destroy had issues (may already be gone)."
    fi
}

# --- Final summary ---

print_summary() {
    local verify_rc="${1:-0}"

    log ""
    log "======================================================"
    log "  Test Suite Summary"
    log "======================================================"
    log "  Timestamp: $(timestamp)"
    log "  VM IP: ${VM_IP:-unknown}"
    log "  Results directory: ${RESULTS_DIR}"
    log ""

    # List result files
    log "  Result files:"
    for f in "$RESULTS_DIR"/*.log; do
        if [ -f "$f" ]; then
            local lines
            lines=$(wc -l < "$f")
            log "    $(basename "$f"): ${lines} lines"
        fi
    done

    log ""

    # Show verify log summary if it exists
    if [ -f "$RESULTS_DIR/verify.log" ]; then
        local pass_count fail_count skip_count
        pass_count=$(grep -c '^\[PASS\]' "$RESULTS_DIR/verify.log" 2>/dev/null || echo 0)
        fail_count=$(grep -c '^\[FAIL\]' "$RESULTS_DIR/verify.log" 2>/dev/null || echo 0)
        skip_count=$(grep -c '^\[SKIP\]' "$RESULTS_DIR/verify.log" 2>/dev/null || echo 0)
        log "  Verification: ${pass_count} passed, ${fail_count} failed, ${skip_count} skipped"
    fi

    log "======================================================"

    if [ "$verify_rc" -ne 0 ]; then
        log "  RESULT: SOME CHECKS FAILED"
        return 1
    fi

    log "  RESULT: ALL CHECKS PASSED"
    return 0
}

# --- Main ---

main() {
    parse_args "$@"

    log "Cinnamon VM Test Runner"
    log "Started at: $(timestamp)"
    log "Project: ${PROJECT_DIR}"
    log ""

    mkdir -p "$RESULTS_DIR"
    echo "Test run started at: $(timestamp)" > "${RESULTS_DIR}/test-run.log"

    local final_rc=0

    if $DO_PROVISION; then
        run_provision
    fi

    if $DO_INSTALL; then
        run_install
    fi

    if $DO_VERIFY; then
        run_verify || final_rc=$?
    fi

    if $DO_DESTROY; then
        run_destroy
    fi

    print_summary "$final_rc" || final_rc=$?

    exit "$final_rc"
}

main "$@"
