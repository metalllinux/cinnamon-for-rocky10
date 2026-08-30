#!/usr/bin/env bash
# validate-install.sh — Orchestrator for INSTALL.md validation (TASK-0005)
#
# Usage: validate-install.sh [--help] [OPTIONS]
#
# This script orchestrates the full INSTALL.md validation process:
#   1. Provisions fresh Rocky Linux 10.2 VMs with minimal dependencies
#   2. Installs prerequisites from INSTALL.md
#   3. Tests the quick install method (VM-1)
#   4. Tests the step-by-step install method (VM-2)
#   5. Verifies all base packages on both VMs
#   6. Runs binary verification on both VMs
#   7. Generates a consolidated test report
#
# Two VMs are used to test each installation method independently on a
# fresh system. VM-1 tests the quick install, VM-2 tests step-by-step.
#
# Options:
#   --skip-provision   Skip provisioning (use existing VMs)
#   --skip-quick       Skip quick install test
#   --skip-stepbystep  Skip step-by-step install test
#   --skip-verify      Skip binary verification
#   --skip-destroy     Skip VM cleanup after tests
#   --help             Show usage

set -euo pipefail

# Force system libvirt connection (session pool has no networks defined)
export LIBVIRT_DEFAULT_URI=qemu:///system

# Source shared constants and functions (TASK-0008 fix batch A: the
# host-key pinning machinery, ssh_pin_opts / seed_vm_pin). The local
# redefinitions below keep the same values as lib.sh.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=vm-test/lib.sh
source "${SCRIPT_DIR}/lib.sh"

# --- Constants ---

PROJECT_DIR="${HOME}/Linux/projects/cinnamon-for-rocky10"
VM_TEST_DIR="${PROJECT_DIR}/vm-test"
RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
SSH_KEY="${HOME}/.ssh/cinnamon-test-key"
VM_USER="root"

# VM names for the two test paths
VM_QUICK="cinnamon-test-quick"
VM_STEPBYSTEP="cinnamon-test-stepbystep"

# --- Flags ---

SKIP_PROVISION=false
SKIP_QUICK=false
SKIP_STEPBYSTEP=false
SKIP_VERIFY=false
SKIP_DESTROY=false

# --- Helpers ---

log() { printf '[orchestrator] %s\n' "$*" >&2; }
die() { printf '[orchestrator] ERROR: %s\n' "$*" >&2; exit 1; }
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

show_usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

INSTALL.md Validation Orchestrator (TASK-0005)

Runs the full installation validation test suite on fresh Rocky Linux 10.2 VMs.
Two VMs are provisioned to test each installation method independently.

Options:
  --skip-provision   Skip VM provisioning (use existing VMs)
  --skip-quick       Skip quick install method test
  --skip-stepbystep  Skip step-by-step install test
  --skip-verify      Skip binary verification
  --skip-destroy     Skip VM cleanup after tests
  --help             Show this help

Test phases:
  1. Provision fresh VMs (minimal Rocky Linux 10.2)
  2. Install prerequisites from INSTALL.md
  3. Quick install test: sudo dnf install ./rpms/*.rpm
  4. Step-by-step install test (4 groups, dependency order)
  5. Package verification (all 14 base packages)
  6. Binary verification (ldd + --version checks)
  7. Cleanup

Examples:
  $(basename "$0")                        # Run full validation
  $(basename "$0") --skip-provision       # Use existing VMs
  $(basename "$0") --skip-stepbystep      # Only test quick install
  $(basename "$0") --skip-destroy         # Keep VMs for debugging
EOF
}

# Parse arguments
parse_args() {
    if [ $# -eq 0 ]; then
        return
    fi

    while [ $# -gt 0 ]; do
        case "$1" in
            --skip-provision)   SKIP_PROVISION=true; shift ;;
            --skip-quick)       SKIP_QUICK=true; shift ;;
            --skip-stepbystep)  SKIP_STEPBYSTEP=true; shift ;;
            --skip-verify)      SKIP_VERIFY=true; shift ;;
            --skip-destroy)     SKIP_DESTROY=true; shift ;;
            --help|-h)          show_usage; exit 0 ;;
            *)                  die "Unknown option: $1" ;;
        esac
    done
}

# Get VM IP from libvirt DHCP leases
get_vm_ip() {
    local vm_name="$1"
    local vm_mac
    vm_mac=$(virsh domiflist "${vm_name}" 2>/dev/null \
        | grep 'vnet\|virtio' \
        | awk '{print $5}' \
        | head -1) || true

    if [ -n "$vm_mac" ]; then
        virsh net-dhcp-leases default 2>/dev/null \
            | grep "${vm_mac}" \
            | awk '{print $5}' \
            | cut -d/ -f1 \
            | tail -1 || true
    fi
}

# Wait for VM IP and SSH
wait_for_vm() {
    local vm_name="$1"
    local max_wait="${2:-300}"
    local interval=10
    local elapsed=0
    local vm_ip=""
    local disk_path="${IMG_DIR}/${vm_name}.qcow2"

    log "Waiting for ${vm_name} to become available (timeout: ${max_wait}s)..."

    while [ "$elapsed" -lt "$max_wait" ]; do
        vm_ip=$(get_vm_ip "$vm_name")
        if [ -n "$vm_ip" ]; then
            # Pinned first contact (TASK-0008, Omega finding 1): seed
            # the per-VM host-key pin file out-of-band from the disk
            # image, then probe with StrictHostKeyChecking=yes. A
            # missing pin file while the guest is still booting reads
            # as "not ready yet" and the loop retries (see lib.sh).
            if seed_vm_pin "$vm_name" "$disk_path"; then
                ssh_pin_opts "$vm_ip" "$vm_name"
                # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
                if ssh ${SSH_PIN_OPTS} -o ConnectTimeout=5 -o BatchMode=yes \
                   -i "${SSH_KEY}" "${VM_USER}@${vm_ip}" \
                   "echo ready" >/dev/null 2>&1; then
                    log "${vm_name} is ready at ${vm_ip} after ${elapsed}s (host key pinned from ${disk_path})."
                    echo "$vm_ip"
                    return 0
                fi
            fi
        fi
        sleep "$interval"
        elapsed=$((elapsed + interval))
        log "  ... ${elapsed}s elapsed, retrying..."
    done

    die "${vm_name} never became ready within ${max_wait}s (host key must be readable from ${disk_path})."
}

# Provision a single VM for install testing
provision_single_vm() {
    local vm_name="$1"
    local disk_path="/var/lib/libvirt/images/cinnamon-test/${vm_name}.qcow2"
    local cloud_image="/var/lib/libvirt/images/cinnamon-test/Rocky-10-GenericCloud.qcow2"

    log "Provisioning ${vm_name}..."

    # Destroy if already exists
    virsh destroy "${vm_name}" 2>/dev/null || true
    virsh undefine "${vm_name}" --remove-all-storage 2>/dev/null || true

    # Check prerequisites
    [ -f "$cloud_image" ] || die "Cloud image not found at ${cloud_image}"
    # Key hygiene before the fleet key is injected into the VM
    # (TASK-0008, Omega finding 2).
    assert_ssh_key "${SSH_KEY}"
    [ -f "${SSH_KEY}.pub" ] || die "SSH key not found at ${SSH_KEY}.pub"

    # Copy cloud image
    cp "$cloud_image" "$disk_path"

    # Customize disk
    virt-customize -a "$disk_path" \
        --ssh-inject "root:file:${SSH_KEY}.pub" \
        --run-command "systemctl enable sshd" \
        --run-command "systemctl mask firewalld" \
        2>&1 | tee "${RESULTS_DIR}/${vm_name}-customize.log" >/dev/null

    # Create VM
    virt-install \
        --name "${vm_name}" \
        --vcpus 2 \
        --memory 4096 \
        --import \
        --disk "path=${disk_path},format=qcow2" \
        --graphics none \
        --network network=default \
        --os-variant rhel10.0 \
        --wait 0 \
        2>&1 | tee "${RESULTS_DIR}/${vm_name}-virt-install.log" >/dev/null

    log "VM ${vm_name} launched, waiting for SSH..."

    # Wait for SSH
    local vm_ip
    vm_ip=$(wait_for_vm "$vm_name")
    echo "$vm_ip"
}

# Destroy a single VM
destroy_single_vm() {
    local vm_name="$1"
    log "Destroying ${vm_name}..."
    virsh destroy "${vm_name}" 2>/dev/null || true
    virsh undefine "${vm_name}" --remove-all-storage 2>/dev/null || true
    # The guest's host keys die with the VM; a re-provision under the
    # same name generates new ones, so the stale pin file must go (TASK-0008,
    # Omega finding 1).
    rm -f "$(vm_pin_file "${vm_name}")"
    log "${vm_name} destroyed."
}

# Run a test script and capture results
run_test_script() {
    local script_name="$1"
    local vm_ip="$2"
    local phase_name="$3"

    local script_path="${VM_TEST_DIR}/${script_name}"
    [ -f "$script_path" ] || die "Test script not found: ${script_path}"

    log "--- ${phase_name} ---"
    log "Started at: $(timestamp)"

    local log_file="${RESULTS_DIR}/${script_name%.sh}.log"

    if "$script_path" "$vm_ip" 2>&1 | tee -a "$log_file"; then
        log "${phase_name}: PASSED"
        echo "PASS"
        return 0
    else
        log "${phase_name}: FAILED"
        echo "FAIL"
        return 1
    fi
}

# --- Test phases ---

# Phase: Quick install test on VM-1
phase_quick_install() {
    local vm_ip="$1"
    local results_file="${RESULTS_DIR}/test-results.txt"

    log ""
    log "============================================================"
    log "  QUICK INSTALL TEST (VM: ${VM_QUICK})"
    log "============================================================"
    log "Started at: $(timestamp)"

    local pass_count=0
    local fail_count=0

    # Step 1: Install prerequisites
    local result
    result=$(run_test_script "test-install-prerequisites.sh" "$vm_ip" "Prerequisites installation") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Prerequisites installation" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Prerequisites installation" | tee -a "$results_file"
    fi

    # Step 2: Quick install
    result=$(run_test_script "test-quick-install.sh" "$vm_ip" "Quick install (dnf install *.rpm)") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Quick install (dnf install *.rpm)" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Quick install (dnf install *.rpm)" | tee -a "$results_file"
    fi

    # Step 3: Package verification
    result=$(run_test_script "verify-install-packages.sh" "$vm_ip" "Package verification (all 14 base)") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Package verification (14 base pkgs)" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Package verification (14 base pkgs)" | tee -a "$results_file"
    fi

    # Step 4: Binary verification
    if ! $SKIP_VERIFY; then
        result=$(run_test_script "verify-binaries.sh" "$vm_ip" "Binary verification (ldd + version)") || true
        if [ "$result" = "PASS" ]; then
            pass_count=$((pass_count + 1))
            printf '[PASS] %-40s\n' "Binary verification (ldd+version)" | tee -a "$results_file"
        else
            fail_count=$((fail_count + 1))
            printf '[FAIL] %-40s\n' "Binary verification (ldd+version)" | tee -a "$results_file"
        fi
    else
        printf '[SKIP] %-40s\n' "Binary verification (skipped)" | tee -a "$results_file"
    fi

    log ""
    log "Quick install test: ${pass_count} passed, ${fail_count} failed."
    log "============================================================"

    [ "$fail_count" -eq 0 ]
}

# Phase: Step-by-step install test on VM-2
phase_stepbystep_install() {
    local vm_ip="$1"
    local results_file="${RESULTS_DIR}/test-results.txt"

    log ""
    log "============================================================"
    log "  STEP-BY-STEP INSTALL TEST (VM: ${VM_STEPBYSTEP})"
    log "============================================================"
    log "Started at: $(timestamp)"

    local pass_count=0
    local fail_count=0

    # Step 1: Install prerequisites
    local result
    result=$(run_test_script "test-install-prerequisites.sh" "$vm_ip" "Prerequisites installation") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Prerequisites installation" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Prerequisites installation" | tee -a "$results_file"
    fi

    # Step 2: Step-by-step install
    result=$(run_test_script "test-step-by-step-install.sh" "$vm_ip" "Step-by-step install (4 groups)") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Step-by-step install (4 groups)" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Step-by-step install (4 groups)" | tee -a "$results_file"
    fi

    # Step 3: Package verification
    result=$(run_test_script "verify-install-packages.sh" "$vm_ip" "Package verification (all 14 base)") || true
    if [ "$result" = "PASS" ]; then
        pass_count=$((pass_count + 1))
        printf '[PASS] %-40s\n' "Package verification (14 base pkgs)" | tee -a "$results_file"
    else
        fail_count=$((fail_count + 1))
        printf '[FAIL] %-40s\n' "Package verification (14 base pkgs)" | tee -a "$results_file"
    fi

    # Step 4: Binary verification
    if ! $SKIP_VERIFY; then
        result=$(run_test_script "verify-binaries.sh" "$vm_ip" "Binary verification (ldd + version)") || true
        if [ "$result" = "PASS" ]; then
            pass_count=$((pass_count + 1))
            printf '[PASS] %-40s\n' "Binary verification (ldd+version)" | tee -a "$results_file"
        else
            fail_count=$((fail_count + 1))
            printf '[FAIL] %-40s\n' "Binary verification (ldd+version)" | tee -a "$results_file"
        fi
    else
        printf '[SKIP] %-40s\n' "Binary verification (skipped)" | tee -a "$results_file"
    fi

    log ""
    log "Step-by-step install test: ${pass_count} passed, ${fail_count} failed."
    log "============================================================"

    [ "$fail_count" -eq 0 ]
}

# --- Final report ---

print_final_report() {
    local results_file="${RESULTS_DIR}/test-results.txt"

    log ""
    log "============================================================"
    log "  INSTALL.md VALIDATION — FINAL REPORT"
    log "============================================================"
    log "  Timestamp: $(timestamp)"
    log "  Project: ${PROJECT_DIR}"
    log ""

    if [ -f "$results_file" ]; then
        log "  Test Results:"
        while IFS= read -r line; do
            log "    ${line}"
        done < "$results_file"
        log ""
    fi

    local total_pass total_fail total_skip
    total_pass=$(grep -c '^\[PASS\]' "$results_file" 2>/dev/null || echo 0)
    total_fail=$(grep -c '^\[FAIL\]' "$results_file" 2>/dev/null || echo 0)
    total_skip=$(grep -c '^\[SKIP\]' "$results_file" 2>/dev/null || echo 0)

    log "  Summary:"
    log "    PASS: ${total_pass}"
    log "    FAIL: ${total_fail}"
    log "    SKIP: ${total_skip}"
    log ""

    if [ "$total_fail" -gt 0 ]; then
        log "  OVERALL RESULT: FAILED"
        log "============================================================"
        return 1
    else
        log "  OVERALL RESULT: PASSED"
        log "============================================================"
        return 0
    fi
}

# --- Main ---

main() {
    parse_args "$@"

    log "============================================================"
    log "  INSTALL.md Validation Suite (TASK-0005)"
    log "============================================================"
    log "Started at: $(timestamp)"
    log "Project: ${PROJECT_DIR}"
    log ""

    mkdir -p "$RESULTS_DIR"

    # Clear results file
    local results_file="${RESULTS_DIR}/test-results.txt"
    echo "INSTALL.md Validation Results — $(timestamp)" > "$results_file"
    echo "" >> "$results_file"

    local overall_rc=0

    # --- Provision VMs ---

    local vm_quick_ip=""
    local vm_stepbystep_ip=""

    if ! $SKIP_PROVISION; then
        log "Phase: Provisioning VMs..."

        # Check prerequisites
        for cmd in virsh virt-install qemu-img virt-customize; do
            command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found. Install libvirt tools."
        done

        [ -f "${SSH_KEY}.pub" ] || die "SSH key not found at ${SSH_KEY}.pub"

        # Provision VM-1 for quick install
        if ! $SKIP_QUICK; then
            vm_quick_ip=$(provision_single_vm "$VM_QUICK")
            log "VM ${VM_QUICK} provisioned at ${vm_quick_ip}"
        fi

        # Provision VM-2 for step-by-step install
        if ! $SKIP_STEPBYSTEP; then
            vm_stepbystep_ip=$(provision_single_vm "$VM_STEPBYSTEP")
            log "VM ${VM_STEPBYSTEP} provisioned at ${vm_stepbystep_ip}"
        fi
    else
        log "Skipping provisioning (existing VMs will be used)."
        # Try to get IPs of existing VMs
        vm_quick_ip=$(get_vm_ip "$VM_QUICK") || true
        vm_stepbystep_ip=$(get_vm_ip "$VM_STEPBYSTEP") || true

        if [ -z "$vm_quick_ip" ] && ! $SKIP_QUICK; then
            die "VM ${VM_QUICK} not found. Run with provisioning enabled."
        fi
        if [ -z "$vm_stepbystep_ip" ] && ! $SKIP_STEPBYSTEP; then
            die "VM ${VM_STEPBYSTEP} not found. Run with provisioning enabled."
        fi
    fi

    # --- Run quick install test ---

    if ! $SKIP_QUICK; then
        phase_quick_install "$vm_quick_ip" || overall_rc=1
    else
        log "Skipping quick install test."
    fi

    # --- Run step-by-step install test ---

    if ! $SKIP_STEPBYSTEP; then
        phase_stepbystep_install "$vm_stepbystep_ip" || overall_rc=1
    else
        log "Skipping step-by-step install test."
    fi

    # --- Cleanup ---

    if ! $SKIP_DESTROY; then
        log ""
        log "Phase: Cleaning up VMs..."

        if ! $SKIP_QUICK; then
            destroy_single_vm "$VM_QUICK"
        fi
        if ! $SKIP_STEPBYSTEP; then
            destroy_single_vm "$VM_STEPBYSTEP"
        fi
    else
        log ""
        log "Skipping VM cleanup (--skip-destroy). VMs are still running:"
        [ -n "$vm_quick_ip" ] && log "  ${VM_QUICK}: ${vm_quick_ip}"
        [ -n "$vm_stepbystep_ip" ] && log "  ${VM_STEPBYSTEP}: ${vm_stepbystep_ip}"
        log "  SSH: ssh -i ${SSH_KEY} root@<VM_IP>"
    fi

    # --- Final report ---

    print_final_report || overall_rc=1

    exit "$overall_rc"
}

main "$@"
