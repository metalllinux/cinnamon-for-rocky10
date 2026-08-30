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
#   - Omega HIGH (TASK-0008): every ssh/scp/rsync channel pinned against
#     vm-test/known_hosts (see the pinning section below); no channel in
#     the harness runs with host-key verification off
#   - Omega MEDIUM (TASK-0008): assert_ssh_key refuses a private key
#     that is group/world readable or owned by another user; the
#     bare-metal host gets its own dedicated key (BAREMETAL_KEY), never
#     the fleet key
#
# Credential blast radius (TASK-0008, Omega finding 2): SSH_KEY
# (default ~/.ssh/cinnamon-test-key) is the FLEET key — it is injected
# into every test VM at provision time and is root in all of them. One
# stolen copy of it opens the whole VM fleet; there is no per-target
# revocation short of re-provisioning. It must NOT be copied to any
# physical host: the bare-metal test host (BAREMETAL_HOST) is accessed
# with its own dedicated key (BAREMETAL_KEY) as BAREMETAL_USER. Keep
# both keys mode 600 and owned by the invoking user; assert_ssh_key
# enforces that on every channel.

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

# --- Host-key pinning (TASK-0008, Omega finding 1, high) ---
#
# Every ssh/scp/rsync channel in the harness runs with
# StrictHostKeyChecking=yes against a pinned host-key file (see
# ssh_pin_opts below). Two target classes:
#
#   VM targets. The cloud image ships no host keys; each guest generates
#   fresh ones on first boot (sshd-keygen@*.service), so every VM has
#   different keys and none can be committed in advance. The provisioner
#   therefore seeds a per-VM pin file (VM_PIN_DIR/<vm-name>) by reading
#   the keys out-of-band from the VM's own qcow2 image (cp + virt-cat,
#   never over the network), and the VM is pinned under a stable
#   HostKeyAlias (= the VM name) so DHCP IP changes are irrelevant.
#
#   Bare-metal host. 192.168.1.103 is pinned by IP in the committed
#   KNOWN_HOSTS_FILE (one-time human TOFU, fingerprints recorded in the
#   TASK-0008 planning doc, Big's checkpoint 2).
#
# A target without a pin file is a hard error. The harness never falls
# back to verification-off.

# Shared VM image directory (provision-vm.sh and the wait loops read
# disk images from here for out-of-band key seeding).
IMG_DIR="/var/lib/libvirt/images/cinnamon-test"

# Committed pin file: bare-metal host keys + policy header.
KNOWN_HOSTS_FILE="${VM_TEST_DIR}/known_hosts"
# Per-VM pin files, seeded at provision time. Under results/ so they
# are gitignored (they are per-run key material, not source).
VM_PIN_DIR="${VM_TEST_DIR}/results/known-hosts"
# The bare-metal host the harness drives besides the VMs. It is
# accessed with a dedicated key as a non-root user (passwordless sudo
# is available there); the fleet key must not open this machine
# (TASK-0008, Omega finding 2).
BAREMETAL_HOST="192.168.1.103"
BAREMETAL_USER="howard"
BAREMETAL_KEY="${HOME}/.ssh/baremetal-103"

# vm_pin_file VM_NAME — path of the per-VM pinned host-key file.
vm_pin_file() {
    printf '%s' "${VM_PIN_DIR}/$1"
}

# seed_vm_pin VM_NAME DISK_PATH — single attempt to pin VM_NAME's host
# keys. Reads the guest's /etc/ssh/ssh_host_*_key.pub out-of-band: the
# qcow2 is copied first (a running VM holds an exclusive lock on its
# disk, which blocks direct qemu-img/virt-cat access), then virt-cat
# extracts the keys from the copy. No network is involved, so an
# on-path attacker cannot influence what gets pinned. rc 0 if the pin
# file now exists; rc 1 if the guest's keys are not in the image yet
# (guest still booting) or the disk is missing.
seed_vm_pin() {
    local vm_name="$1" disk="$2"
    local pin copy line k
    local entries=()
    pin="$(vm_pin_file "$vm_name")"
    [ -f "$pin" ] && return 0
    [ -f "$disk" ] || return 1
    copy="$(mktemp "${TMPDIR:-/tmp}/t0008-pin-XXXXXX")" || return 1
    cp "$disk" "$copy" 2>/dev/null || { rm -f "$copy"; return 1; }
    for k in ed25519 ecdsa rsa; do
        line="$(virt-cat "$copy" "/etc/ssh/ssh_host_${k}_key.pub" 2>/dev/null || true)"
        [ -n "$line" ] || { rm -f "$copy"; return 1; }
        # Reject a corrupt (e.g. torn) read: the key must parse.
        ssh-keygen -lf <(printf '%s\n' "$line") >/dev/null 2>&1 \
            || { rm -f "$copy"; return 1; }
        entries+=("${vm_name} ${line}")
    done
    rm -f "$copy"
    mkdir -p "${VM_PIN_DIR}"
    printf '%s\n' "${entries[@]}" > "$pin"
    chmod 644 "$pin"
    return 0
}

# ssh_pin_opts TARGET [ALIAS] — sets SSH_PIN_OPTS (a string that callers
# word-split deliberately; see the shellcheck disable at each use site)
# to the -o options that pin host-key verification for TARGET:
#   VM target: the per-VM pin file + HostKeyAlias=ALIAS
#              (default ALIAS: ${VM_NAME})
#   bare-metal: the committed KNOWN_HOSTS_FILE, pinned by IP
# A VM target without a pin file is a hard error (fail-closed).
ssh_pin_opts() {
    local target="$1" alias="${2:-${VM_NAME}}"
    if [ "$target" = "${BAREMETAL_HOST}" ]; then
        SSH_PIN_OPTS="-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${KNOWN_HOSTS_FILE}"
        return 0
    fi
    local pin
    pin="$(vm_pin_file "$alias")"
    if [ ! -f "$pin" ]; then
        {
            echo "[lib] ERROR: no pinned host key for '${alias}' (${pin} missing)."
            echo "[lib] The harness never connects with host-key verification off."
            echo "[lib] Seed it by provisioning through provision-vm.sh (the key is read"
            echo "[lib] from the disk image out-of-band) or create ${pin} manually; the"
            echo "[lib] format is documented in the header of ${KNOWN_HOSTS_FILE}."
        } >&2
        exit 1
    fi
    SSH_PIN_OPTS="-o StrictHostKeyChecking=yes -o UserKnownHostsFile=${pin} -o HostKeyAlias=${alias}"
}

# --- Shared functions ---

# assert_ssh_key KEY_PATH — on-disk hygiene of a private key is a
# harness invariant (TASK-0008, Omega finding 2): the key must exist,
# be owned by the invoking user, and not be group/world readable (mode
# 600 is the standard; 400 is accepted — ssh requires the same).
# Checked once per key per process; exits 1 with an actionable message
# on failure.
assert_ssh_key() {
    local key="$1"
    local checked="${_SSH_KEY_CHECKED:-}"
    case " ${checked} " in
        *" ${key} "*) return 0 ;;
    esac
    [ -f "$key" ] || { echo "[lib] ERROR: SSH private key not found at ${key}" >&2; exit 1; }
    local mode owner
    mode="$(stat -c '%a' "$key")"
    owner="$(stat -c '%U' "$key")"
    if [ $(( 0${mode} & 077 )) -ne 0 ]; then
        echo "[lib] ERROR: SSH key ${key} is mode ${mode} (group/world readable)." >&2
        echo "[lib] Fix: chmod 600 ${key}" >&2
        exit 1
    fi
    if [ "$owner" != "$(id -un)" ]; then
        echo "[lib] ERROR: SSH key ${key} is owned by ${owner}, not $(id -un)." >&2
        echo "[lib] The harness refuses to use a key it does not own." >&2
        exit 1
    fi
    _SSH_KEY_CHECKED="${checked} ${key}"
}

# SSH helper — uses key-based auth, pinned host-key verification.
# Shared by all test scripts. ConnectTimeout=60 to accommodate
# longer-running operations like binary verification and version checks
# that may time out with the default 30s.
#
# Credentials are per target: VM targets use the fleet key as root;
# the bare-metal host uses its dedicated key as BAREMETAL_USER
# (TASK-0008, Omega finding 2). Commands for the bare-metal host run
# as that non-root user — wrap root operations in 'sudo' (passwordless
# sudo is available on that host).
ssh_cmd() {
    local target="$1"; shift
    local user key
    if [ "$target" = "${BAREMETAL_HOST}" ]; then
        user="${BAREMETAL_USER}"
        key="${BAREMETAL_KEY}"
    else
        user="${VM_USER}"
        key="${SSH_KEY}"
    fi
    assert_ssh_key "$key"
    ssh_pin_opts "$target"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    ssh ${SSH_PIN_OPTS} -o ConnectTimeout=60 -i "${key}" "${user}@${target}" "$@"
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
