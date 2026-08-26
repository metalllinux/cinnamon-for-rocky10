#!/usr/bin/env bash
# lib.sh — Shared constants and functions for the Cinnamon VM test harness
# Part of TASK-0003 VM testing harness for Cinnamon RPMs.
#
# Source this file from all test scripts. Do not execute directly.
#
# Addresses:
#   - Omega MEDIUM: VM_PASSWORD duplicated across 3 files (extracted to single source)
#   - Shadow should-fix: get_vm_ip duplicated across 3 files (extracted to shared lib)
#   - Omega low: ssh_cmd duplicated across 5 files (TASK-0005 — extracted to shared lib)

# --- Guard: must be sourced, not executed ---
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    echo "lib.sh must be sourced, not executed." >&2
    exit 1
fi

# Force system connection (session pool has no networks defined)
export LIBVIRT_DEFAULT_URI=qemu:///system

# --- Shared constants ---

# VM_NAME honors a pre-set environment value so a caller (e.g.
# test-gdm-login.sh) can provision under its own name. Scripts that
# source this file without exporting VM_NAME keep the default.
VM_NAME="${VM_NAME:-cinnamon-test-vm}"
VM_USER="root"
SSH_KEY="${HOME}/.ssh/cinnamon-test-key"
PROJECT_DIR="${HOME}/Linux/projects/cinnamon-for-rocky10"
VM_TEST_DIR="${PROJECT_DIR}/vm-test"

# --- Shared functions ---

# SSH helper — uses key-based auth. Shared by all test scripts.
# ConnectTimeout=60 to accommodate longer-running operations like binary
# verification and version checks that may time out with the default 30s.
ssh_cmd() {
    local target="$1"; shift
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=60 -i "${SSH_KEY}" "${VM_USER}@${target}" "$@"
}

# Resolve VM IP from libvirt DHCP leases using MAC-based lookup.
# Returns the IP address on stdout, empty string if not found.
get_vm_ip() {
    local vm_ip=""
    local vm_mac
    vm_mac=$(virsh domiflist "${VM_NAME}" 2>/dev/null \
        | grep 'vnet\|virtio' \
        | awk '{print $5}' \
        | head -1)

    if [ -n "$vm_mac" ]; then
        # Columns: Expiry(2) MAC Protocol IP Hostname ClientID
        vm_ip=$(virsh net-dhcp-leases default 2>/dev/null \
            | grep "${vm_mac}" \
            | awk '{print $5}' \
            | cut -d/ -f1 \
            | tail -1)
    fi

    echo "$vm_ip"
}
