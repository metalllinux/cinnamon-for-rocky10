#!/usr/bin/env bash
# test-gdm-login.sh — GDM login harness (libvirt), TASK-0008 item 2.
#
# Drives the full GDM login flow on a fresh Rocky Linux 10.2 VM:
#   1. Provision a VM with VNC graphics (provision-vm.sh --graphics vnc)
#   2. Baseline the user's configuration: GDM + GNOME. The greeter is
#      Wayland on EL10 by necessity (item 2 finding: no X server is
#      installable and gdm-47 is Wayland-only), so no greeter config
#      is written. Ephemeral test user with a random password generated
#      inside the VM (never leaves it).
#   3. Build the in-VM ukey uinput driver + gdm-a11y.py a11y reader
#      (item 3 finding F9: xdotool/ydotool/dogtail absent from EL10
#      + EPEL; item 2 finding: no X server for an XTest driver)
#   4. Control: log the test user into GNOME, verify by state
#   5. Install Cinnamon exactly per INSTALL.md (setup-repo.sh + the two
#      dnf install commands + ldconfig)
#   6. Attempt the Cinnamon (Wayland) login (session select via the
#      greeter's Login Options menu, credentials, 120s wait), verify
#      by state, capture evidence on both outcomes. The
#      cinnamon-wayland.desktop entry is the launchable one on EL10
#      (the X11 entry cannot launch: no Xorg, item 2c-1)
#
# Verdicts are state-based, not pixel-based (plan, Login drive step 4):
# a loginctl session of type wayland/x11 for the user plus the expected
# desktop process. Evidence (journalctl -u gdm, /var/log/secure,
# loginctl, getenforce, the greeter a11y tree, host-side VNC
# screenshots via virsh screenshot) is always captured, including on
# failure, and is collected back to vm-test/results/ (gitignored).
#
# Usage: test-gdm-login.sh [options]
#   --name NAME          VM name (default: gdm-login-vm)
#   --selinux MODE       enforcing|permissive (default: permissive, the
#                        plan's base-reproduction mode; enforcing is the
#                        S5 matrix scenario)
#   --reboot-after-install
#                        reboot the VM after the INSTALL.md install,
#                        before the Cinnamon attempt (item 5 experiment B)
#   --daemon-reload-after-install
#                        systemctl daemon-reload after the install, no
#                        reboot (item 5 experiment C)
#   --attach             reuse the existing running VM (skip provisioning)
#   --ip IP              with --attach: attach to a VM that is NOT a
#                        libvirt domain (an orphan QEMU process, e.g.
#                        the adopted gdm-login-vm of TASK-0008 attempt
#                        4). The IP is taken as given; reboots go over
#                        SSH; the post-reboot IP is re-resolved from
#                        the libvirt default-network dnsmasq lease
#                        state by NIC MAC; host screenshots are skipped
#                        (no QMP channel) and the a11y tree is the
#                        observation channel.
#
# Host-key pinning (TASK-0008, Omega finding 1): every ssh/scp channel
# in this harness runs with StrictHostKeyChecking=yes against a pinned
# key file (see lib.sh). VMs provisioned by the harness get their pin
# file seeded out-of-band from the disk image; with --attach the VM
# must either already have a pin file (vm-test/results/known-hosts/
# <name>) or keep its disk image at the standard path
# /var/lib/libvirt/images/cinnamon-test/<name>.qcow2 so it can be
# seeded. A target with neither is refused up front (fail-closed; the
# harness has no verification-off fallback).
#   --keep-vm            do not destroy the VM at the end
#   --in-vm 'cmd'        run one command in the VM as root and exit
#                        (iteration channel for driver development)
#   -h, --help           this help
#
# Exit code: 0 when the harness completed both login attempts with
# evidence and the teardown verified the VM is gone (the Cinnamon
# verdict may be PASS or FAIL — that is the result under test, not a
# harness error); 1 when a harness phase failed (a teardown that
# cannot verify the VM is gone is a phase failure: the surviving
# domain would read as "destroyed" and the next run starts from a
# phantom state, Shadow finding 4, TASK-0008).

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_ROOT="${PROJECT_DIR}/vm-test/results"
TS="$(date '+%Y%m%d-%H%M%S')"
RESULTS_DIR="${RESULTS_ROOT}/gdm-login-${TS}"
HARNESS_FILES=("${PROJECT_DIR}/tasks/lib/gdm-drive.sh" \
               "${PROJECT_DIR}/tasks/lib/ukey.c" \
               "${PROJECT_DIR}/tasks/lib/gdm-a11y.py")
REMOTE_HARNESS_DIR="/root/gdm-harness"
TEST_USER="gdmtest"
SSH_MAX_WAIT=180
SSH_CHECK_INTERVAL=5
PROVISION_SCRIPT="${SCRIPT_DIR}/provision-vm.sh"

# --- Options (defaults per the plan) ---

VM_NAME="gdm-login-vm"
SELINUX_MODE="permissive"
REBOOT_AFTER_INSTALL=false
DAEMON_RELOAD_AFTER_INSTALL=false
ATTACH=false
ATTACH_IP=""
KEEP_VM=false
INVM_CMD=""

# --- Helpers ---

log() { printf '[gdm-login] %s\n' "$*"; }
die() { printf '[gdm-login] ERROR: %s\n' "$*" >&2; exit 1; }

show_usage() {
    # Print the header comment block from "Usage:" to the first blank
    # line (the option list and exit-code note).
    sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

# Summary bookkeeping
PHASE_LINES=()
record_phase() {
    local verdict="$1" phase="$2" detail="${3:-}"
    PHASE_LINES+=("[${verdict}] ${phase}${detail:+ - ${detail}}")
    log "PHASE ${verdict} ${phase} ${detail}"
}

# write_summary — prints and persists the phase table. Defined before
# its first use (several failure paths call it mid-script).
write_summary() {
    {
        echo "GDM login harness summary - ${TS}"
        echo "VM: ${VM_NAME}  IP: ${VM_IP:-unknown}  VNC: ${VNC_DISPLAY:-unknown}"
        echo "Options: selinux=${SELINUX_MODE} reboot-after-install=${REBOOT_AFTER_INSTALL} daemon-reload=${DAEMON_RELOAD_AFTER_INSTALL}"
        for line in "${PHASE_LINES[@]}"; do
            echo "$line"
        done
        echo "Evidence: ${RESULTS_DIR}/evidence/"
        echo "Screenshots: ${RESULTS_DIR}/shots/"
        echo "Per-phase logs: ${RESULTS_DIR}/*.log"
    } | tee "${RESULTS_DIR}/summary.txt"
}

# host_shot — pixel observation channel: capture the guest framebuffer
# from the host via QMP (works for the Wayland greeter; no in-VM X
# needed). $1 = shot name. For a domain-less (orphan) VM there is no
# QMP channel, so the shot is skipped with a log line and the a11y
# tree (captured by gdm_capture_evidence) is the observation channel
# instead (plan: screenshots are best-effort; verdicts are state-based).
host_shot() {
    local f="${RESULTS_DIR}/shots/$1.png"
    mkdir -p "${RESULTS_DIR}/shots"
    if ! virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
        log "screenshot skipped: ${VM_NAME} is not a libvirt domain (a11y tree is the observation channel)"
        return 0
    fi
    if virsh screenshot "${VM_NAME}" "$f" >/dev/null 2>&1; then
        log "screenshot: ${f}"
    else
        log "screenshot FAILED: ${f}"
    fi
}

# try_ssh — poll SSH on an IP until it answers or the timeout passes.
# Returns 0/1 without dying, so callers can try a second candidate
# address (post-reboot DHCP re-resolution, orphan mode).
#
# Pinned (TASK-0008, Omega finding 1): each iteration seeds the per-VM
# host-key pin file out-of-band from the disk image, then probes with
# StrictHostKeyChecking=yes. A missing pin file (guest still booting,
# or an unknown target without a disk) reads as "not ready yet" here
# and the loop retries; the hard error is reserved for the non-wait
# channels (ssh_cmd), where a missing pin file is a harness error.
try_ssh() {
    local vm_ip="$1"
    local elapsed=0
    while [ "$elapsed" -lt "$SSH_MAX_WAIT" ]; do
        if seed_vm_pin "${VM_NAME}" "${IMG_DIR}/${VM_NAME}.qcow2" \
            && { ssh_pin_opts "$vm_ip"
                 # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
                 ssh ${SSH_PIN_OPTS} -o ConnectTimeout=5 -o BatchMode=yes \
                     -i "${SSH_KEY}" "${VM_USER}@${vm_ip}" \
                     "echo ready" >/dev/null 2>&1; }; then
            return 0
        fi
        sleep "$SSH_CHECK_INTERVAL"
        elapsed=$((elapsed + SSH_CHECK_INTERVAL))
    done
    return 1
}

# wait_for_ssh — like provision-vm.sh's, longer timeout for post-reboot
# windows (GDM + GNOME first boot is slower than the console target).
wait_for_ssh() {
    local vm_ip="$1"
    log "Waiting for SSH on ${vm_ip} (timeout: ${SSH_MAX_WAIT}s)..."
    if try_ssh "$vm_ip"; then
        log "SSH ready on ${vm_ip}."
        return 0
    fi
    die "SSH never became ready on ${vm_ip} within ${SSH_MAX_WAIT}s."
}

# orphan_vm_ip — resolve the IP of a VM that is not a libvirt domain
# (an orphan QEMU process) from the libvirt default-network dnsmasq
# lease state. The NIC MAC comes from the QEMU process command line
# (-device ...mac=...); the lease is the dnsmasq status JSON. Prints
# the IP, or nothing.
orphan_vm_ip() {
    local mac=""
    local qpid
    qpid=$(pgrep -f "guest=${VM_NAME}" 2>/dev/null | head -1)
    [ -n "$qpid" ] || return 0
    mac=$(tr '\0' ' ' < "/proc/${qpid}/cmdline" 2>/dev/null \
        | grep -oE 'mac=[0-9a-f]{2}(:[0-9a-f]{2}){5}' | head -1 | cut -d= -f2)
    [ -n "$mac" ] || return 0
    sudo jq -r --arg mac "$mac" \
        '.[] | select(.["mac-address"] == $mac) | .["ip-address"]' \
        /var/lib/libvirt/dnsmasq/virbr0.status 2>/dev/null | head -1
}

# reboot_and_wait — reboot the VM and wait for it to come back with an
# IP and SSH. The DHCP lease can vanish during the reboot, so the IP is
# re-pollled; a new lease (same or different address) is re-resolved
# after SSH is back. Sets VM_IP on success.
#
# Orphan mode (no libvirt domain): the reboot goes over SSH, and the
# post-reboot IP is re-resolved from the dnsmasq lease state (the
# previous address is tried first, since dnsmasq normally keeps it).
reboot_and_wait() {
    if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
        local ip=""
        local waited=0
        virsh reboot "${VM_NAME}"
        log "Rebooting ${VM_NAME}; waiting for it to come back..."
        # Give the guest time to start shutting down before we expect
        # the old lease to be released.
        sleep 15
        while [ -z "$ip" ] && [ "$waited" -lt 120 ]; do
            ip="$(get_vm_ip)"
            if [ -z "$ip" ]; then
                sleep 5
                waited=$((waited + 5))
            fi
        done
        [ -n "$ip" ] || die "no IP after reboot of ${VM_NAME}"
        wait_for_ssh "$ip"
        # Re-resolve: DHCP may have handed the guest a different address.
        VM_IP="$(get_vm_ip)"
        [ -n "$VM_IP" ] || VM_IP="$ip"
    else
        local old_ip="$VM_IP"
        log "Orphan VM ${VM_NAME}: rebooting over SSH (no libvirt domain)."
        ssh_cmd "$VM_IP" "reboot" 2>/dev/null || true
        log "Waiting for ${VM_NAME} to come back..."
        sleep 15
        local candidates=("$old_ip")
        local alt
        alt="$(orphan_vm_ip)"
        if [ -n "$alt" ] && [ "$alt" != "$old_ip" ]; then
            candidates+=("$alt")
        fi
        local c back=false
        for c in "${candidates[@]}"; do
            log "Trying ${c} ..."
            if try_ssh "$c"; then
                VM_IP="$c"
                back=true
                break
            fi
        done
        $back || die "no reachable IP after reboot of ${VM_NAME} (tried: ${candidates[*]})"
    fi
    log "${VM_NAME} back after reboot at ${VM_IP}"
}

# invm — run an in-VM script (on stdin, as root) and capture its output
# to RESULTS_DIR/<tag>.log. The in-VM script prints its outcome as a
# final single line: PHASE_RESULT <PASS|FAIL|VERDICT> <detail>. A FAIL
# report exits non-zero by design, so the marker is accepted regardless
# of rc; only a missing marker (script died, ssh dropped) is a harness
# error.
#
# Contract: the marker line is the LAST line of the in-VM script and is
# always exactly one line. invm prints at most that one line on stdout
# (the parse input); diagnostic tail output goes to stderr, never into
# the command substitution.
invm() {
    local tag="$1"; shift
    local args="${*:-}"
    local logf="${RESULTS_DIR}/${tag}.log"
    local rc=0
    # shellcheck disable=SC2086  # args are intentionally word-split
    ssh_cmd "$VM_IP" "bash -s ${args}" > "$logf" 2>&1 || rc=$?
    local marker
    marker=$(grep '^PHASE_RESULT ' "$logf" | tail -1)
    if [ -n "$marker" ]; then
        printf '%s\n' "$marker"
        return 0
    fi
    printf 'PHASE_RESULT FAIL no marker (rc=%s; see %s)\n' "$rc" "$logf"
    tail -5 "$logf" 2>/dev/null | sed 's/^/    /' >&2
    return 1
}

# parse the marker line (guaranteed single-line by invm): set
# MARKER_VERDICT / MARKER_DETAIL
parse_marker() {
    local line="$1"
    MARKER_VERDICT="$(cut -d' ' -f2 <<<"$line")"
    MARKER_DETAIL="$(cut -d' ' -f3- <<<"$line")"
}

# --- Argument parsing ---

while [ $# -gt 0 ]; do
    case "$1" in
        --name)
            VM_NAME="${2:-}"; [ -n "$VM_NAME" ] || die "--name requires a value"
            shift 2 ;;
        --selinux)
            SELINUX_MODE="${2:-}"; shift 2
            [ "$SELINUX_MODE" = "enforcing" ] || [ "$SELINUX_MODE" = "permissive" ] \
                || die "--selinux takes enforcing|permissive"
            ;;
        --reboot-after-install)
            REBOOT_AFTER_INSTALL=true; shift ;;
        --daemon-reload-after-install)
            DAEMON_RELOAD_AFTER_INSTALL=true; shift ;;
        --attach)
            ATTACH=true; shift ;;
        --ip)
            ATTACH_IP="${2:-}"; [ -n "$ATTACH_IP" ] || die "--ip requires a value"
            shift 2 ;;
        --keep-vm)
            KEEP_VM=true; shift ;;
        --in-vm)
            INVM_CMD="${2:-}"; [ -n "$INVM_CMD" ] || die "--in-vm requires a command"
            shift 2 ;;
        -h|--help)
            show_usage; exit 0 ;;
        *)
            die "Unknown option: $1 (try --help)" ;;
    esac
done

mkdir -p "$RESULTS_DIR"
exec > >(tee "${RESULTS_DIR}/run.log") 2>&1

log "=== GDM login harness run ${TS} ==="
log "VM: ${VM_NAME}  SELinux: ${SELINUX_MODE}  reboot-after-install: ${REBOOT_AFTER_INSTALL}  daemon-reload: ${DAEMON_RELOAD_AFTER_INSTALL}"

# Export for lib.sh consumers (provision-vm.sh, get_vm_ip)
export VM_NAME

# resolve_ip — libvirt lease lookup first; for a domain-less (orphan)
# VM fall back to --ip. Sets VM_IP.
resolve_ip() {
    VM_IP="$(get_vm_ip)"
    if [ -z "$VM_IP" ] && [ -n "$ATTACH_IP" ]; then
        VM_IP="$ATTACH_IP"
    fi
}

# --- Iteration channel: one in-VM command, then exit ---
if [ -n "$INVM_CMD" ]; then
    resolve_ip
    [ -n "$VM_IP" ] || die "no IP for ${VM_NAME} (is it running?; orphan VMs need --ip)"
    log "in-vm on ${VM_IP}: ${INVM_CMD}"
    ssh_cmd "$VM_IP" bash -c "$INVM_CMD"
    exit $?
fi

# --- Phase 1: provision (or attach) ---

if [ "$ATTACH" = true ]; then
    if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
        log "Attaching to existing VM ${VM_NAME}."
        resolve_ip
        [ -n "$VM_IP" ] || die "no IP for ${VM_NAME}"
    else
        [ -n "$ATTACH_IP" ] || die "VM ${VM_NAME} is not a libvirt domain; pass --ip IP to attach to an orphan VM"
        log "Attaching to orphan VM ${VM_NAME} at ${ATTACH_IP} (no libvirt domain; screenshots and virsh reboot unavailable)."
        VM_IP="$ATTACH_IP"
    fi
    # Fail-closed host-key check (TASK-0008, Omega finding 1): an
    # attached VM must be pinnable — either its pin file already exists
    # or its disk image is available for out-of-band seeding. A target
    # with neither is refused up front instead of timing out in
    # wait_for_ssh.
    if [ ! -f "$(vm_pin_file "${VM_NAME}")" ] && [ ! -f "${IMG_DIR}/${VM_NAME}.qcow2" ]; then
        die "cannot pin the host key of ${VM_NAME} at ${VM_IP}: no pin file at $(vm_pin_file "${VM_NAME}") and no disk image at ${IMG_DIR}/${VM_NAME}.qcow2 to seed from. Create the pin file manually (format in the header of ${KNOWN_HOSTS_FILE}); the harness never connects with host-key verification off."
    fi
    wait_for_ssh "$VM_IP"
    record_phase PASS provision "attached to existing VM at ${VM_IP}"
else
    log "Provisioning fresh VM with VNC graphics..."
    # provision-vm.sh honors the exported VM_NAME (lib.sh change, item 2).
    bash "${PROVISION_SCRIPT}" --destroy --graphics vnc \
        || { record_phase FAIL provision "provision-vm.sh failed"; write_summary; exit 1; }
    VM_IP="$(get_vm_ip)"
    [ -n "$VM_IP" ] || die "no IP after provisioning"
    record_phase PASS provision "VM ${VM_NAME} at ${VM_IP}"
fi

# Record the VNC display for human observation of the greeter.
VNC_DISPLAY="$(virsh vncdisplay "${VM_NAME}" 2>/dev/null || echo none)"
log "VNC display: ${VNC_DISPLAY}"

# --- Phase 2: copy harness files into the VM ---

ssh_cmd "$VM_IP" "mkdir -p ${REMOTE_HARNESS_DIR}"
for f in "${HARNESS_FILES[@]}"; do
    ssh_pin_opts "$VM_IP"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    scp ${SSH_PIN_OPTS} -i "${SSH_KEY}" \
        "$f" "${VM_USER}@${VM_IP}:${REMOTE_HARNESS_DIR}/" >/dev/null \
        || die "scp failed for ${f}"
done
log "Harness files in ${REMOTE_HARNESS_DIR}/"

# --- Phase 3: in-VM baseline (GDM + GNOME, test user, driver) ---

log "Phase 3: baseline (GDM + GNOME, test user, ukey build)..."
BASELINE_MARKER="$(
    invm baseline "${SELINUX_MODE}" <<'EOF'
set -uo pipefail
fail() { echo "PHASE_RESULT FAIL $*"; exit 1; }

SELINUX_MODE="${1:-permissive}"

# 1. SELinux mode, deterministic (plan A2): setenforce + config so a
#    later --reboot-after-install keeps the mode across the reboot.
if [ "$SELINUX_MODE" = "enforcing" ]; then
    setenforce 1 || fail "setenforce 1"
    sed -ri 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
else
    setenforce 0 || fail "setenforce 0"
    sed -ri 's/^SELINUX=.*/SELINUX=permissive/' /etc/selinux/config
fi
echo "SELinux mode: $(getenforce)"

mkdir -p /root/evidence

# 2. GDM + GNOME baseline (the user's configuration, plan A1). The
#    resolved package set is recorded for the planning doc.
#    NOTE: no X server package exists on EL10 (item 2 finding,
#    re-verified live in the test VM 2026-08-27 item 2c: dnf list
#    available "xorg-x11-server*" -> only Xwayland-devel in crb; dnf
#    provides /usr/bin/Xorg -> no matches; EPEL 10 has no Xorg either)
#    — the greeter is Wayland (gdm-47 ships only gdm-wayland-session),
#    so no /etc/gdm/custom.conf is written and nothing X is installed.
dnf install -y gdm gnome-shell \
    > /root/evidence/baseline-dnf.log 2>&1 \
    || fail "dnf install gdm gnome-shell"
rpm -q gdm gnome-shell > /root/evidence/baseline-packages.log 2>&1
# Record the driver-decision evidence: no X server installable.
{
    echo "--- xorg-x11-server-Xorg availability (item 2 finding) ---"
    rpm -q xorg-x11-server-Xorg || true
    dnf list available xorg-x11-server-Xorg 2>&1 || true
    echo "--- gdm session launchers shipped (Wayland-only) ---"
    rpm -ql gdm | grep '^/usr/libexec/' || true
} > /root/evidence/baseline-repos.log 2>&1

# 3. GDM as the boot login manager.
systemctl enable gdm
systemctl set-default graphical.target

# 4. Ephemeral test user. The password is random hex (typeable without
#    shift), generated here, and never leaves the VM.
id -u gdmtest >/dev/null 2>&1 || useradd -m gdmtest
openssl rand -hex 12 > /root/gdmtest.pass
chmod 600 /root/gdmtest.pass
usermod -p "$(openssl passwd -6 "$(cat /root/gdmtest.pass)")" gdmtest

# 5. Driver build (ukey: gcc + kernel-headers; gdm-a11y.py:
#    python3-dbus). All default EL10 repos.
dnf install -y gcc kernel-headers python3-dbus \
    > /root/evidence/baseline-driverdeps.log 2>&1 \
    || fail "driver build deps"
source /root/gdm-harness/gdm-drive.sh
gdm_build_driver || fail "ukey build"
echo "PHASE_RESULT PASS baseline complete (SELinux=$(getenforce))"
EOF
)" || true
parse_marker "$BASELINE_MARKER"
record_phase "$MARKER_VERDICT" "baseline" "$MARKER_DETAIL"
[ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }

# --- Phase 4: reboot into the graphical target, wait for the greeter ---

log "Phase 4: reboot into GDM, wait for greeter..."
reboot_and_wait
# Wait for the greeter session + a11y UI before declaring it up.
GREETER_MARKER="$(
    invm greeter-wait <<'EOF'
set -uo pipefail
source /root/gdm-harness/gdm-drive.sh
gdm_wait_greeter 240 || { echo "PHASE_RESULT FAIL greeter session not up after 240s"; exit 1; }
# Dual-mode UI readiness: the face-list greeter has no "Log In" node
# (item 2, attempt 4), so no needle is passed.
gdm_greeter_ui_ready "" 120 || { echo "PHASE_RESULT FAIL greeter a11y UI not ready"; exit 1; }
python3 /root/gdm-harness/gdm-a11y.py text > /root/evidence/greeter-ui-text.log 2>&1 || true
python3 /root/gdm-harness/gdm-a11y.py tree > /root/evidence/greeter-ui-tree.log 2>&1 || true
echo "PHASE_RESULT PASS greeter up (a11y UI ready)"
EOF
)" || true
parse_marker "$GREETER_MARKER"
record_phase "$MARKER_VERDICT" "reboot+greeter" "$MARKER_DETAIL (VM back at ${VM_IP})"
[ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }
host_shot 00-greeter

# --- Phase 5: GNOME control login ---

log "Phase 5: GNOME control login for ${TEST_USER}..."
GNOME_MARKER="$(
    invm gnome-control <<'EOF'
set -uo pipefail
source /root/gdm-harness/gdm-drive.sh
mkdir -p /root/evidence/gnome-control

gdm_ensure_greeter gdmtest 150 || { echo "PHASE_RESULT FAIL greeter not up"; exit 1; }
python3 /root/gdm-harness/gdm-a11y.py tree > /root/evidence/gnome-control/01-greeter-tree.log 2>&1 || true

T0="$(date '+%F %T')"
gdm_login gdmtest /root/gdmtest.pass gnome
gdm_wait_session gdmtest "$GDM_LOGIN_WAIT" gnome-shell
RC=$?
gdm_capture_evidence gnome-control "$T0" gdmtest

if [ "$RC" -eq 0 ]; then
    # Return to the greeter for the later Cinnamon attempt (the
    # greeter stays up through the install, matching the user's
    # scenario: install at the desktop, then log out and try Cinnamon).
    loginctl terminate-user gdmtest
    gdm_wait_greeter_ui 90 || { echo "PHASE_RESULT FAIL greeter did not return after logout"; exit 1; }
    echo "PHASE_RESULT PASS gnome control login verified, logged out to greeter"
else
    echo "PHASE_RESULT FAIL gnome control login (rc=${RC}; evidence captured)"
    exit 1
fi
EOF
)" || true
parse_marker "$GNOME_MARKER"
record_phase "$MARKER_VERDICT" "gnome-control-login" "$MARKER_DETAIL"
if [ "$MARKER_VERDICT" = "PASS" ]; then
    host_shot 01-gnome-desktop
    host_shot 02-greeter-back
else
    host_shot 01-gnome-control-fail
fi
[ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }

# --- Phase 6: INSTALL.md install (repo method, the user's procedure) ---

log "Phase 6: copy rpms/ + repo-setup/ and run the INSTALL.md install..."
ssh_pin_opts "$VM_IP"
# shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
scp ${SSH_PIN_OPTS} -i "${SSH_KEY}" \
    -r "${PROJECT_DIR}/rpms" "${PROJECT_DIR}/repo-setup" \
    "${VM_USER}@${VM_IP}/root/" >/dev/null \
    || die "scp of rpms/ + repo-setup/ failed"

INSTALL_MARKER="$(
    invm install <<'EOF'
set -uo pipefail
fail() { echo "PHASE_RESULT FAIL $*"; exit 1; }
mkdir -p /root/evidence

# INSTALL.md:27-48: setup-repo.sh, then the two dnf install commands,
# then ldconfig. Exactly the user's procedure, via the file:// repo.
bash /root/repo-setup/setup-repo.sh /root \
    > /root/evidence/install-setup-repo.log 2>&1 || fail "setup-repo.sh"
dnf install -y cinnamon \
    > /root/evidence/install-cinnamon.log 2>&1 || fail "dnf install cinnamon"
dnf install -y cinnamon-session cinnamon-settings-daemon cinnamon-control-center \
    nemo mozjs115-devel \
    > /root/evidence/install-core.log 2>&1 || fail "dnf install core components"
ldconfig > /root/evidence/install-ldconfig.log 2>&1 || fail "ldconfig"
rpm -q cinnamon cinnamon-session nemo \
    > /root/evidence/install-versions.log 2>&1
ls -l /usr/share/xsessions/cinnamon.desktop \
    >> /root/evidence/install-versions.log 2>&1
echo "PHASE_RESULT PASS install complete (14 packages, session file present)"
EOF
)" || true
parse_marker "$INSTALL_MARKER"
record_phase "$MARKER_VERDICT" "install" "$MARKER_DETAIL"
[ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }

# --- Phase 7: post-install modes (item 5 experiments) ---

if [ "$REBOOT_AFTER_INSTALL" = true ]; then
    log "Phase 7a: reboot after install (experiment B)..."
    reboot_and_wait
    POSTBOOT_MARKER="$(
        invm postboot-wait <<'EOF'
set -uo pipefail
source /root/gdm-harness/gdm-drive.sh
gdm_wait_greeter 240 || { echo "PHASE_RESULT FAIL greeter not up after post-install reboot"; exit 1; }
gdm_greeter_ui_ready "" 120 || { echo "PHASE_RESULT FAIL greeter a11y UI not ready"; exit 1; }
echo "PHASE_RESULT PASS greeter up after post-install reboot"
EOF
    )" || true
    parse_marker "$POSTBOOT_MARKER"
    record_phase "$MARKER_VERDICT" "reboot-after-install" "$MARKER_DETAIL (VM back at ${VM_IP})"
    [ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }
fi

if [ "$DAEMON_RELOAD_AFTER_INSTALL" = true ]; then
    log "Phase 7b: daemon-reload after install (experiment C)..."
    DR_MARKER="$(
        invm daemon-reload <<'EOF'
set -uo pipefail
mkdir -p /root/evidence
systemctl daemon-reload
journalctl -u systemd-logind --since "$(date -d '10 minutes ago' '+%F %T')" --no-pager \
    > /root/evidence/daemon-reload-logind.log 2>&1 || true
loginctl list-sessions --no-legend \
    > /root/evidence/daemon-reload-sessions.log 2>&1 || true
echo "PHASE_RESULT PASS daemon-reload done"
EOF
    )" || true
    parse_marker "$DR_MARKER"
    record_phase "$MARKER_VERDICT" "daemon-reload-after-install" "$MARKER_DETAIL"
    [ "$MARKER_VERDICT" = "PASS" ] || { write_summary; exit 1; }
fi

# --- Phase 8: Cinnamon login attempt (the result under test) ---

log "Phase 8: Cinnamon login attempt for ${TEST_USER}..."
host_shot 03-greeter-cinnamon
CINNAMON_MARKER="$(
    invm cinnamon-attempt <<'EOF'
set -uo pipefail
source /root/gdm-harness/gdm-drive.sh
mkdir -p /root/evidence/cinnamon-attempt

gdm_ensure_greeter gdmtest 150 || { echo "PHASE_RESULT FAIL greeter not up"; exit 1; }
# What the greeter offers at this moment (session entries + a11y
# structure). The a11y tree records which session entries the
# greeter lists (X11 "Cinnamon" and "Cinnamon (Wayland)" after the
# Cinnamon install; the Wayland entry is the launchable one on
# EL10 — no Xorg, item 2c-1).
ls -l /usr/share/xsessions/ /usr/share/wayland-sessions/ \
    > /root/evidence/cinnamon-attempt/sessions-available.log 2>&1 || true
python3 /root/gdm-harness/gdm-a11y.py tree > /root/evidence/cinnamon-attempt/01-greeter-tree.log 2>&1 || true
python3 /root/gdm-harness/gdm-a11y.py text > /root/evidence/cinnamon-attempt/01-greeter-text.log 2>&1 || true

T0="$(date '+%F %T')"
# rc=2 (gdm_login) = requested session not selectable in the greeter
# menu: the attempt did not submit credentials, so it is a harness
# verdict, not a PAM outcome.
gdm_login gdmtest /root/gdmtest.pass cinnamon-wayland
LOGIN_RC=$?
if [ "$LOGIN_RC" -ne 0 ]; then
    gdm_capture_evidence cinnamon-attempt "$T0" gdmtest
    echo "PHASE_RESULT VERDICT cinnamon login FAIL (gdm_login rc=${LOGIN_RC}, no credentials submitted)"
    exit 0
fi
gdm_wait_session gdmtest "$GDM_LOGIN_WAIT" cinnamon-session
RC=$?
gdm_capture_evidence cinnamon-attempt "$T0" gdmtest

# The post-attempt greeter screen carries the dialog text (e.g.
# "Authentication Error", plan A4) — capture it on both outcomes.
sleep 5
python3 /root/gdm-harness/gdm-a11y.py text > /root/evidence/cinnamon-attempt/02-post-attempt-text.log 2>&1 || true

if [ "$RC" -eq 0 ]; then
    echo "PHASE_RESULT VERDICT cinnamon login PASS (session + process verified)"
else
    echo "PHASE_RESULT VERDICT cinnamon login FAIL (rc=${RC}; evidence captured)"
fi
EOF
)" || true
parse_marker "$CINNAMON_MARKER"
# VERDICT (not PASS/FAIL) so the harness is not blamed for the result
# under test: the acceptance criterion is that the attempt runs to
# completion with the evidence set, whichever way it lands.
if [ "$MARKER_VERDICT" = "VERDICT" ]; then
    record_phase PASS "cinnamon-login-attempt" "verdict: ${MARKER_DETAIL}"
elif [ "$MARKER_VERDICT" = "FAIL" ]; then
    # Distinguish "verdict FAIL" (handled above as VERDICT) from a
    # harness failure (greeter never up).
    case "$MARKER_DETAIL" in
        *"cinnamon login"*)
            record_phase PASS "cinnamon-login-attempt" "verdict: ${MARKER_DETAIL}" ;;
        *)
            record_phase FAIL "cinnamon-login-attempt" "$MARKER_DETAIL"
            write_summary
            exit 1 ;;
    esac
else
    record_phase FAIL "cinnamon-login-attempt" "no marker (${CINNAMON_MARKER})"
    write_summary
    exit 1
fi
host_shot 04-post-cinnamon-attempt

# --- Phase 9: collect evidence back to the host ---

log "Phase 9: collecting evidence to ${RESULTS_DIR}/evidence/..."
ssh_pin_opts "$VM_IP"
# shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
scp ${SSH_PIN_OPTS} -i "${SSH_KEY}" \
    -r "${VM_USER}@${VM_IP}:/root/evidence" "${RESULTS_DIR}/" >/dev/null 2>&1 \
    || { record_phase FAIL evidence "scp of /root/evidence failed"; write_summary; exit 1; }
EVIDENCE_COUNT="$(find "${RESULTS_DIR}/evidence" -type f | wc -l)"
record_phase PASS evidence "${EVIDENCE_COUNT} files under ${RESULTS_DIR}/evidence/"

# --- Teardown ---

if [ "$KEEP_VM" = true ]; then
    log "Keeping VM ${VM_NAME} (IP ${VM_IP}, VNC ${VNC_DISPLAY})."
else
    log "Destroying VM ${VM_NAME}..."
    # Shadow finding 4 (TASK-0008): record PASS/FAIL from the rc of
    # --destroy-only instead of `|| true`. provision-vm.sh now proves
    # libvirt is reachable and verifies the domain (and disk) are
    # actually gone before exiting 0, so a non-zero rc means the VM
    # may still exist.
    teardown_rc=0
    teardown_out="$(bash "${PROVISION_SCRIPT}" --destroy-only 2>&1)" || teardown_rc=$?
    if [ "$teardown_rc" -eq 0 ]; then
        record_phase PASS teardown "VM destroyed"
    else
        domstate="$(virsh domstate "${VM_NAME}" 2>&1 || true)"
        log "teardown output from provision-vm.sh --destroy-only:"
        printf '%s\n' "$teardown_out" >&2
        record_phase FAIL teardown "destroy rc=${teardown_rc} (domain state: ${domstate:-unknown}); VM may still exist"
        write_summary
        exit 1
    fi
fi

write_summary

log "=== run complete: ${RESULTS_DIR} ==="
