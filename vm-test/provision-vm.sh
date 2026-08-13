#!/usr/bin/env bash
# provision-vm.sh — W1: Provision a Rocky Linux 10.2 VM from cloud image
# Part of TASK-0003 VM testing harness for Cinnamon RPMs.
#
# Usage: provision-vm.sh [--destroy]
#   --destroy  : destroy existing VM before provisioning (idempotent)
#
# Uses virt-customize to configure the cloud image (root password, SSH, firewall)
# before launching the VM. No cloud-init needed.
#
# Security fixes (Omega):
#   - VM_PASSWORD removed entirely — VM accessed via SSH keys only (no password auth)
#   - Password no longer logged to stdout (was in "already exists" message)
#   - virt-install --import does not pass credentials on command line

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Provision-specific constants ---

IMG_DIR="/var/lib/libvirt/images/cinnamon-test"
CLOUD_IMAGE="${IMG_DIR}/Rocky-10-GenericCloud.qcow2"
DISK_PATH="${IMG_DIR}/${VM_NAME}.qcow2"
VCPUS=2
MEMORY=4096
SSH_MAX_WAIT=120
SSH_CHECK_INTERVAL=5

# --- Helpers ---

log() { printf '[provision] %s\n' "$*"; }
die() { printf '[provision] ERROR: %s\n' "$*" >&2; exit 1; }

check_prereqs() {
    for cmd in virt-install virsh qemu-img virt-customize; do
        command -v "$cmd" >/dev/null 2>&1 || die "'$cmd' not found"
    done
    [ -f "$CLOUD_IMAGE" ] || die "Cloud image not found at $CLOUD_IMAGE"
    [ -f "${SSH_KEY}.pub" ] || die "SSH public key not found at ${SSH_KEY}.pub. Run: ssh-keygen -t ed25519 -f ~/.ssh/cinnamon-test-key -N ''"
}

destroy_vm() {
    log "Destroying existing VM ${VM_NAME}..."
    virsh destroy "${VM_NAME}" 2>/dev/null || true
    virsh undefine "${VM_NAME}" --remove-all-storage 2>/dev/null || true
    rm -f "$DISK_PATH"
    log "VM destroyed."
}

wait_for_ssh() {
    local vm_ip="$1"
    local elapsed=0
    log "Waiting for SSH on ${vm_ip} (timeout: ${SSH_MAX_WAIT}s)..."

    while [ "$elapsed" -lt "$SSH_MAX_WAIT" ]; do
        if ssh -o StrictHostKeyChecking=no \
           -o ConnectTimeout=5 -o BatchMode=yes \
           -i "${SSH_KEY}" "${VM_USER}@${vm_ip}" \
           "echo ready" >/dev/null 2>&1; then
            log "SSH is ready on ${vm_ip} after ${elapsed}s."
            return 0
        fi
        sleep "$SSH_CHECK_INTERVAL"
        elapsed=$((elapsed + SSH_CHECK_INTERVAL))
        log "  ... ${elapsed}s elapsed, retrying..."
    done

    die "SSH never became ready on ${vm_ip} within ${SSH_MAX_WAIT}s."
}

# --- Main ---

main() {
    local do_destroy=false
    [ "${1:-}" = "--destroy" ] && do_destroy=true

    check_prereqs

    if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
        if $do_destroy; then
            destroy_vm
        else
            log "VM '${VM_NAME}' already exists."
            local vm_ip
            vm_ip=$(get_vm_ip)
            if [ -n "$vm_ip" ]; then
                log "VM IP: ${vm_ip}"
                # Omega fix: SSH key auth only — no password in log output
                log "SSH: ssh -i ${SSH_KEY} ${VM_USER}@${vm_ip}"
            else
                log "VM exists but could not determine IP."
            fi
            log "Re-run with --destroy to recreate."
            exit 0
        fi
    fi

    mkdir -p "$IMG_DIR"

    log "Provisioning VM '${VM_NAME}' from cloud image..."
    log "  Cloud image: ${CLOUD_IMAGE}"
    log "  Disk: ${DISK_PATH}"
    log "  vCPUs: ${VCPUS}, RAM: ${MEMORY}MB"

    # Copy cloud image to working disk
    log "Copying cloud image to working disk..."
    cp "$CLOUD_IMAGE" "$DISK_PATH"

    # Customize the disk image: inject SSH key, configure SSH and firewall
    log "Customizing disk image (SSH key, firewall)..."
    [ -f "${SSH_KEY}.pub" ] || die "SSH public key not found at ${SSH_KEY}.pub"

    virt-customize -a "$DISK_PATH" \
        --ssh-inject "root:file:${SSH_KEY}.pub" \
        --run-command "systemctl enable sshd" \
        --run-command "systemctl mask firewalld" \
        --run-command "rm -f /etc/systemd/system/multi-user.target.wants/firewalld.service" \
        2>&1 | tee "${IMG_DIR}/customize.log"

    # Create VM using virt-install --import
    log "Creating VM..."
    virt-install \
        --name "${VM_NAME}" \
        --vcpus "${VCPUS}" \
        --memory "${MEMORY}" \
        --import \
        --disk "path=${DISK_PATH},format=qcow2" \
        --graphics none \
        --network network=default \
        --os-variant rhel10.0 \
        --wait 0 \
        2>&1 | tee "${IMG_DIR}/virt-install.log"

    log "VM launched from cloud image."
    log "Watch progress with: virsh console ${VM_NAME}"

    # Wait for the VM to get an IP
    sleep 10

    # Poll until we get an IP address (DHCP)
    local vm_ip=""
    local ip_wait=0
    while [ -z "$vm_ip" ] && [ "$ip_wait" -lt 120 ]; do
        vm_ip=$(get_vm_ip)
        if [ -n "$vm_ip" ]; then
            break
        fi
        sleep 5
        ip_wait=$((ip_wait + 5))
        log "  Waiting for VM IP (DHCP)... ${ip_wait}s"
    done

    if [ -z "$vm_ip" ]; then
        die "No IP address obtained for VM within 60s."
    fi

    log "VM obtained IP: ${vm_ip}"

    # Wait for SSH
    wait_for_ssh "$vm_ip"

    log "VM '${VM_NAME}' provisioned and ready."
    log "  IP: ${vm_ip}"
    log "  SSH: ssh -i ${SSH_KEY} ${VM_USER}@${vm_ip}"
    log "  Console: virsh console ${VM_NAME}"
}

main "$@"
