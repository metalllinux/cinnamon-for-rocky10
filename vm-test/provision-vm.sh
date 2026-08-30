#!/usr/bin/env bash
# provision-vm.sh — W1: Provision a Rocky Linux 10.2 VM from cloud image
# Part of TASK-0003 VM testing harness for Cinnamon RPMs.
#
# Usage: provision-vm.sh [--destroy] [--destroy-only] [--graphics <type>] [--name <vm-name>]
#   --destroy       : destroy existing VM before provisioning (idempotent)
#   --destroy-only  : destroy the existing VM and exit; do not provision
#                     (teardown path, TASK-0008)
#   --graphics type : virt-install graphics type (default: none).
#                     Use "vnc" to attach to the console (TASK-0008 item 2:
#                     GDM greeter observation). The VNC display is reported
#                     via `virsh vncdisplay <vm>` after launch.
#   --name name     : VM name (default: cinnamon-test-vm from lib.sh)
#
# Uses virt-customize to configure the cloud image (root password, SSH, firewall)
# before launching the VM. No cloud-init needed.
#
# Security fixes (Omega):
#   - VM_PASSWORD removed entirely — VM accessed via SSH keys only (no password auth)
#   - Password no longer logged to stdout (was in "already exists" message)
#   - virt-install --import does not pass credentials on command line
#   - TASK-0008 (Omega finding 1, high): wait_for_ssh seeds the per-VM
#     host-key pin file out-of-band from the disk image (see
#     seed_vm_pin in lib.sh) and only then connects, with
#     StrictHostKeyChecking=yes; no harness channel runs with host-key
#     verification off

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Provision-specific constants ---
# (IMG_DIR comes from lib.sh: the wait loop seeds the per-VM host-key
# pin file from the disk image, so both need the same location.)

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
    # Key hygiene before the key is injected into a VM (TASK-0008,
    # Omega finding 2): the fleet key is the root credential for every
    # VM it is injected into, so a world/group-readable copy is a
    # standing leak.
    assert_ssh_key "${SSH_KEY}"
    [ -f "${SSH_KEY}.pub" ] || die "SSH public key not found at ${SSH_KEY}.pub. Run: ssh-keygen -t ed25519 -f ~/.ssh/cinnamon-test-key -N ''"
}

destroy_vm() {
    log "Destroying existing VM ${VM_NAME}..."
    virsh destroy "${VM_NAME}" 2>/dev/null || true
    virsh undefine "${VM_NAME}" --remove-all-storage 2>/dev/null || true
    rm -f "$DISK_PATH"
    # The guest's host keys die with the VM; a re-provision under the
    # same name generates new ones, so the stale pin file must go with
    # the disk (TASK-0008, Omega finding 1).
    rm -f "$(vm_pin_file "${VM_NAME}")"
    log "VM destroyed."
}

wait_for_ssh() {
    local vm_ip="$1"
    local elapsed=0
    log "Waiting for SSH on ${vm_ip} (timeout: ${SSH_MAX_WAIT}s)..."

    while [ "$elapsed" -lt "$SSH_MAX_WAIT" ]; do
        # Pinned first contact (TASK-0008, Omega finding 1): seed the
        # per-VM host-key pin file out-of-band from the disk image.
        # While the guest is still booting (sshd-keygen has not written
        # the keys yet) the seed is a no-op and the loop retries; once
        # the keys are in the image, every connection is pinned against
        # them. An on-path attacker cannot answer the pinned probe with
        # its own key, so the evidence chain starts authenticated.
        if seed_vm_pin "${VM_NAME}" "$DISK_PATH"; then
            ssh_pin_opts "$vm_ip"
            # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
            if ssh ${SSH_PIN_OPTS} \
                   -o ConnectTimeout=5 -o BatchMode=yes \
                   -i "${SSH_KEY}" "${VM_USER}@${vm_ip}" \
                   "echo ready" >/dev/null 2>&1; then
                log "SSH is ready on ${vm_ip} after ${elapsed}s (host key pinned from ${DISK_PATH})."
                return 0
            fi
        fi
        sleep "$SSH_CHECK_INTERVAL"
        elapsed=$((elapsed + SSH_CHECK_INTERVAL))
        log "  ... ${elapsed}s elapsed, retrying..."
    done

    die "SSH never became ready on ${vm_ip} within ${SSH_MAX_WAIT}s (host key must be readable from ${DISK_PATH}; check that the VM is booting)."
}

# --- Main ---

main() {
    local do_destroy=false
    local destroy_only=false
    local graphics="none"
    local vm_name_override=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --destroy)
                do_destroy=true
                shift
                ;;
            --destroy-only)
                destroy_only=true
                shift
                ;;
            --graphics)
                graphics="${2:-}"
                [ -n "$graphics" ] || die "--graphics requires a value (none|vnc|spice)"
                shift 2
                ;;
            --name)
                vm_name_override="${2:-}"
                [ -n "$vm_name_override" ] || die "--name requires a value"
                shift 2
                ;;
            *)
                die "Unknown option: $1 (see header for usage)"
                ;;
        esac
    done

    # Apply the name override after lib.sh has been sourced.
    if [ -n "$vm_name_override" ]; then
        VM_NAME="$vm_name_override"
        DISK_PATH="${IMG_DIR}/${VM_NAME}.qcow2"
    fi

    check_prereqs

    # --destroy-only: tear down and stop. Idempotent: a missing VM is a
    # success (the teardown path wants "gone", not "error").
    #
    # Shadow finding 4 (TASK-0008): the harness records its teardown
    # verdict from this path's rc, so the rc must reflect the real end
    # state. destroy_vm's virsh calls carry || true (idempotent
    # re-runs), so a failed destroy would otherwise read as success.
    # The end state is therefore verified, not assumed.
    if $destroy_only; then
        # First prove libvirt is reachable at all: a permission failure
        # on the system driver must not read as "VM not present".
        virsh list --all >/dev/null 2>&1 || die "cannot query libvirt (virsh list --all failed); cannot verify the end state, so teardown is reported as failed"
        if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
            destroy_vm
        else
            log "VM '${VM_NAME}' not present; nothing to destroy."
            rm -f "$DISK_PATH"
            rm -f "$(vm_pin_file "${VM_NAME}")"
        fi
        # Verify the domain is actually gone (the || true calls above
        # swallow a failed destroy/undefine).
        if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
            die "VM '${VM_NAME}' still present after destroy (domstate: $(virsh domstate "${VM_NAME}" 2>&1 || true))"
        fi
        if [ -e "$DISK_PATH" ]; then
            die "disk ${DISK_PATH} still present after destroy"
        fi
        exit 0
    fi

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
    # $graphics is "none" by default; "vnc" gives the agent a console
    # channel for greeter observation (TASK-0008 item 2).
    log "Creating VM (graphics: ${graphics})..."
    virt-install \
        --name "${VM_NAME}" \
        --vcpus "${VCPUS}" \
        --memory "${MEMORY}" \
        --import \
        --disk "path=${DISK_PATH},format=qcow2" \
        --graphics "${graphics}" \
        --network network=default \
        --os-variant rhel10.0 \
        --wait 0 \
        2>&1 | tee "${IMG_DIR}/virt-install.log"

    log "VM launched from cloud image."
    log "Watch progress with: virsh console ${VM_NAME}"
    if [ "$graphics" = "vnc" ]; then
        # libvirt assigns the first free VNC display; report it so the
        # operator/agent can connect (e.g. a VNC client to :N on the host).
        local vnc_display
        vnc_display=$(virsh vncdisplay "${VM_NAME}" 2>/dev/null || true)
        [ -n "$vnc_display" ] && log "VNC display: ${vnc_display} (connect to host:${vnc_display#*:})"
    fi

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
