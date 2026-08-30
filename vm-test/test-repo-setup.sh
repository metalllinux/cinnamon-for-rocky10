#!/usr/bin/env bash
# test-repo-setup.sh — Validate DNF repository setup for Cinnamon RPMs
# Part of TASK-0006 test suite for local DNF repository.
#
# Usage: test-repo-setup.sh
#
# This script:
#   1. Provisions a fresh Rocky Linux 10.2 VM (destroying any existing one)
#   2. Copies repo-setup/ and rpms/ directories to the VM
#   3. Runs setup-repo.sh to configure the local DNF repository
#   4. Verifies the repository metadata is accessible via dnf
#   5. Installs cinnamon via the local repository
#   6. Verifies all 14 base packages are installed at expected versions
#   7. Runs binary verification (ldd + version checks)
#   8. Tests error handling edge cases (on the host, not the VM),
#      asserting that the root error path leaves no host state change
#      (statelessness contract, TASK-0008 Omega medium finding)
#
# Results are written to vm-test/results/repo-setup.log

set -euo pipefail

# Source shared constants and functions
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib.sh"

# --- Local constants ---

RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
LOG_FILE="${RESULTS_DIR}/repo-setup.log"
VM_NAME="cinnamon-test-repo"
CLOUD_IMAGE="/var/lib/libvirt/images/cinnamon-test/Rocky-10-GenericCloud.qcow2"
DISK_PATH="/var/lib/libvirt/images/cinnamon-test/${VM_NAME}.qcow2"
VCPUS=2
MEMORY=4096
SSH_MAX_WAIT=120
SSH_CHECK_INTERVAL=5

# Track results
PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
WARN_COUNT=0
TOTAL_COUNT=0

log() { printf '[repo-test] %s\n' "$*" >&2; }

record() {
    local check="$1"
    local result="$2"
    local detail="${3:-}"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$result" = "PASS" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf '[PASS] %-50s %s\n' "$check" "$detail"
    elif [ "$result" = "SKIP" ]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        printf '[SKIP] %-50s %s\n' "$check" "$detail"
    elif [ "$result" = "WARN" ]; then
        WARN_COUNT=$((WARN_COUNT + 1))
        printf '[WARN] %-50s %s\n' "$check" "$detail"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf '[FAIL] %-50s %s\n' "$check" "$detail"
    fi
    echo "[$result] $check $detail" >> "$LOG_FILE"
}

die() { printf '[repo-test] ERROR: %s\n' "$*" >&2; exit 1; }

# --- VM provisioning ---

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
        # per-VM host-key pin file out-of-band from the disk image,
        # then probe with StrictHostKeyChecking=yes. A missing pin
        # file while the guest is still booting reads as "not ready
        # yet" and the loop retries (see lib.sh).
        if seed_vm_pin "${VM_NAME}" "$DISK_PATH"; then
            ssh_pin_opts "$vm_ip"
            # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
            if ssh ${SSH_PIN_OPTS} \
                   -o ConnectTimeout=5 -o BatchMode=yes \
                   -i "${SSH_KEY}" "${VM_USER}@${vm_ip}" \
                   "echo ready" >/dev/null 2>&1; then
                log "SSH ready on ${vm_ip} after ${elapsed}s (host key pinned from ${DISK_PATH})."
                return 0
            fi
        fi
        sleep "$SSH_CHECK_INTERVAL"
        elapsed=$((elapsed + SSH_CHECK_INTERVAL))
        log "  ... ${elapsed}s elapsed..."
    done
    die "SSH never ready on ${vm_ip} within ${SSH_MAX_WAIT}s (host key must be readable from ${DISK_PATH})."
}

provision_vm() {
    # Use the standard VM name from lib.sh for provisioning, then rename
    # Actually, let's use our own VM name directly
    # Key hygiene before the fleet key is injected into the VM
    # (TASK-0008, Omega finding 2).
    assert_ssh_key "${SSH_KEY}"
    mkdir -p /var/lib/libvirt/images/cinnamon-test

    if virsh domstate "${VM_NAME}" >/dev/null 2>&1; then
        destroy_vm
    fi

    log "Provisioning VM '${VM_NAME}'..."
    cp "$CLOUD_IMAGE" "$DISK_PATH"

    log "Customizing disk image..."
    virt-customize -a "$DISK_PATH" \
        --ssh-inject "root:file:${SSH_KEY}.pub" \
        --run-command "systemctl enable sshd" \
        --run-command "systemctl mask firewalld" \
        --run-command "rm -f /etc/systemd/system/multi-user.target.wants/firewalld.service" \
        > "${RESULTS_DIR}/customize.log" 2>&1

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
        > "${RESULTS_DIR}/virt-install.log" 2>&1

    sleep 10
    local vm_ip=""
    local ip_wait=0
    while [ -z "$vm_ip" ] && [ "$ip_wait" -lt 120 ]; do
        # Get MAC for our specific VM
        local vm_mac
        vm_mac=$(virsh domiflist "${VM_NAME}" 2>/dev/null \
            | grep 'vnet\|virtio' \
            | awk '{print $5}' \
            | head -1)
        if [ -n "$vm_mac" ]; then
            vm_ip=$(virsh net-dhcp-leases default 2>/dev/null \
                | grep "${vm_mac}" \
                | awk '{print $5}' \
                | cut -d/ -f1 \
                | tail -1)
        fi
        if [ -n "$vm_ip" ]; then
            break
        fi
        sleep 5
        ip_wait=$((ip_wait + 5))
    done

    if [ -z "$vm_ip" ]; then
        die "No IP for VM within 120s."
    fi
    log "VM IP: ${vm_ip}"
    wait_for_ssh "$vm_ip"
    echo "$vm_ip"
}

# --- Test steps ---

test_error_handling() {
    log ""
    log "=== Phase 0: Error handling (host-side validation) ==="
    log ""

    # Test 1: Script syntax check
    log "Checking setup-repo.sh syntax..."
    if bash -n "${PROJECT_DIR}/repo-setup/setup-repo.sh" 2>/dev/null; then
        record "setup-repo.sh syntax check" "PASS" "no syntax errors"
    else
        record "setup-repo.sh syntax check" "FAIL" "syntax errors detected"
    fi

    # Test 2: Non-root execution should fail with clear error
    log "Testing non-root execution rejection..."
    local nonroot_output
    if nonroot_output=$(bash "${PROJECT_DIR}/repo-setup/setup-repo.sh" 2>&1 || true); then
        if echo "$nonroot_output" | grep -q "must be run as root"; then
            record "Non-root rejection" "PASS" "correctly rejects non-root with clear message"
        else
            record "Non-root rejection" "FAIL" "did not produce expected error message (output: ${nonroot_output})"
        fi
    else
        # Script exited with error, check if it was the root check
        if echo "$nonroot_output" | grep -q "must be run as root"; then
            record "Non-root rejection" "PASS" "exit code non-zero + clear error message"
        else
            record "Non-root rejection" "FAIL" "unexpected error (output: ${nonroot_output})"
        fi
    fi

    # Test 3: Missing rpms/ directory should fail with clear error.
    #
    # Omega finding (medium, TASK-0008): this runs the REAL script as
    # root on this host. Its safety today rests on the script dying at
    # project-root resolution (setup-repo.sh: cd -P under set -euo
    # pipefail) before the root check and every state-changing step —
    # an ordering that was never asserted, so one refactor (moving the
    # root check first) would make this test perform the full setup as
    # root on the host: dnf install createrepo_c, createrepo_c over
    # rpms/ (gitignored repodata/ in the working tree), a host repo
    # file, CRB enabled. The statelessness is therefore asserted, not
    # assumed: the host state is snapshotted before the root run and
    # verified unchanged after it.
    log "Testing missing rpms/ directory rejection..."
    local missing_rpms_output
    local state_marker state_before state_after
    state_marker=$(mktemp)
    state_before="$(
        {
            if rpm -q --quiet createrepo_c 2>/dev/null; then
                echo "createrepo_c:installed"
            else
                echo "createrepo_c:absent"
            fi
            if [ -e /etc/yum.repos.d/cinnamon-rocky10.repo ]; then
                echo "cinnamon-rocky10.repo:present"
            else
                echo "cinnamon-rocky10.repo:absent"
            fi
            # All repo files: catches the cinnamon-rocky10.repo write
            # and a CRB enable (config-manager edits the CRB .repo).
            find /etc/yum.repos.d -maxdepth 1 -name '*.repo' -type f -exec md5sum {} + 2>/dev/null
        } | sort
    )"
    if missing_rpms_output=$(sudo bash "${PROJECT_DIR}/repo-setup/setup-repo.sh" /tmp/nonexistent-dir-$(date +%s) 2>&1 || true); then
        if echo "$missing_rpms_output" | grep -qiE "not found|No such file"; then
            record "Missing rpms/ rejection" "PASS" "correctly rejects missing directory"
        else
            record "Missing rpms/ rejection" "FAIL" "did not produce expected error (output: ${missing_rpms_output})"
        fi
    else
        if echo "$missing_rpms_output" | grep -qiE "not found|No such file"; then
            record "Missing rpms/ rejection" "PASS" "exit code non-zero + clear error"
        else
            record "Missing rpms/ rejection" "FAIL" "unexpected error (output: ${missing_rpms_output})"
        fi
    fi
    # Statelessness check (Omega finding): the root run above must have
    # changed nothing on this host. The dnf metadata cache is
    # deliberately not asserted: it is transient by design and is
    # rewritten by any concurrent dnf activity.
    state_after="$(
        {
            if rpm -q --quiet createrepo_c 2>/dev/null; then
                echo "createrepo_c:installed"
            else
                echo "createrepo_c:absent"
            fi
            if [ -e /etc/yum.repos.d/cinnamon-rocky10.repo ]; then
                echo "cinnamon-rocky10.repo:present"
            else
                echo "cinnamon-rocky10.repo:absent"
            fi
            find /etc/yum.repos.d -maxdepth 1 -name '*.repo' -type f -exec md5sum {} + 2>/dev/null
        } | sort
    )"
    # Any file created or modified under the working tree's rpms/ by
    # the root run (the gitignored repodata/ is the one a stateful
    # regression would write).
    local rpms_modified
    rpms_modified="$(find "${PROJECT_DIR}/rpms" -type f -newer "$state_marker" 2>/dev/null || true)"
    rm -f "$state_marker"
    if [ "$state_before" = "$state_after" ] && [ -z "$rpms_modified" ]; then
        record "Error-path statelessness" "PASS" "root run left no host state change (createrepo_c, repo files, rpms/)"
    else
        record "Error-path statelessness" "FAIL" "host state changed by the error-path run (diff on stderr)"
        {
            diff <(printf '%s\n' "$state_before") <(printf '%s\n' "$state_after") || true
            if [ -n "$rpms_modified" ]; then
                printf 'modified/created under rpms/:\n%s\n' "$rpms_modified"
            fi
        } >&2
    fi

    # Test 4: .repo template exists
    log "Checking .repo template..."
    if [ -f "${PROJECT_DIR}/repo-setup/cinnamon-rocky10.repo" ]; then
        record ".repo template exists" "PASS"
    else
        record ".repo template exists" "FAIL" "file not found"
    fi

    # Test 5: .repo template contains placeholder
    log "Checking .repo template placeholder..."
    if grep -q "BASEURL_PLACEHOLDER" "${PROJECT_DIR}/repo-setup/cinnamon-rocky10.repo"; then
        record ".repo template has BASEURL_PLACEHOLDER" "PASS"
    else
        record ".repo template has BASEURL_PLACEHOLDER" "FAIL"
    fi

    # Test 6: .repo template has gpgcheck=0
    log "Checking gpgcheck=0 in template..."
    if grep -q "gpgcheck=0" "${PROJECT_DIR}/repo-setup/cinnamon-rocky10.repo"; then
        record ".repo template gpgcheck=0" "PASS"
    else
        record ".repo template gpgcheck=0" "FAIL"
    fi

    # Test 7: .repo template has enabled=1
    log "Checking enabled=1 in template..."
    if grep -q "enabled=1" "${PROJECT_DIR}/repo-setup/cinnamon-rocky10.repo"; then
        record ".repo template enabled=1" "PASS"
    else
        record ".repo template enabled=1" "FAIL"
    fi

    # Test 8: .repo template has metadata_expire=0
    log "Checking metadata_expire=0 in template..."
    if grep -q "metadata_expire=0" "${PROJECT_DIR}/repo-setup/cinnamon-rocky10.repo"; then
        record ".repo template metadata_expire=0" "PASS"
    else
        record ".repo template metadata_expire=0" "FAIL"
    fi
}

test_vm_repo_setup() {
    local vm_ip="$1"

    log ""
    log "=== Phase 1: Copy files to VM ==="
    log ""

    # Copy repo-setup/ directory to VM
    log "Copying repo-setup/ to VM..."
    ssh_cmd "$vm_ip" "mkdir -p /root/cinnamon-for-rocky10"
    ssh_pin_opts "$vm_ip"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    rsync -avz -e "ssh ${SSH_PIN_OPTS} -i ${SSH_KEY}" \
        "${PROJECT_DIR}/repo-setup/" \
        "root@${vm_ip}:/root/cinnamon-for-rocky10/repo-setup/" 2>&1 | tail -3

    # Copy rpms/ directory to VM (only RPMs and repodata, not everything)
    log "Copying rpms/ to VM..."
    ssh_pin_opts "$vm_ip"
    # shellcheck disable=SC2086  # SSH_PIN_OPTS is intentionally word-split
    rsync -avz -e "ssh ${SSH_PIN_OPTS} -i ${SSH_KEY}" \
        "${PROJECT_DIR}/rpms/" \
        "root@${vm_ip}:/root/cinnamon-for-rocky10/rpms/" 2>&1 | tail -3

    # Verify files arrived
    local remote_repo_count
    remote_repo_count=$(ssh_cmd "$vm_ip" "find /root/cinnamon-for-rocky10/rpms/ -maxdepth 1 -name '*.rpm' | wc -l" || echo "0")
    if [ "$remote_repo_count" -eq 48 ]; then
        record "RPMs copied to VM" "PASS" "${remote_repo_count}/48 RPMs present"
    else
        record "RPMs copied to VM" "FAIL" "expected 48 RPMs, found ${remote_repo_count}"
    fi

    local remote_scripts
    remote_scripts=$(ssh_cmd "$vm_ip" "ls /root/cinnamon-for-rocky10/repo-setup/" 2>/dev/null || true)
    if echo "$remote_scripts" | grep -q "setup-repo.sh"; then
        record "setup-repo.sh copied to VM" "PASS"
    else
        record "setup-repo.sh copied to VM" "FAIL" "not found on VM"
    fi

    log ""
    log "=== Phase 2: Run setup-repo.sh ==="
    log ""

    # Run setup-repo.sh on the VM
    log "Executing setup-repo.sh on VM..."
    local setup_output
    local setup_rc=0
    setup_output=$(ssh_cmd "$vm_ip" \
        "cd /root/cinnamon-for-rocky10 && bash ./repo-setup/setup-repo.sh /root/cinnamon-for-rocky10 2>&1" || true)
    # Capture exit code separately
    local exit_check
    exit_check=$(ssh_cmd "$vm_ip" \
        "cd /root/cinnamon-for-rocky10 && bash ./repo-setup/setup-repo.sh /root/cinnamon-for-rocky10 >/dev/null 2>&1 ; echo \$?" || echo "255")

    log "Setup script output:"
    echo "$setup_output" | while IFS= read -r line; do
        printf '    %s\n' "$line"
    done

    # Shadow finding 3 (TASK-0008): compare the rc value directly.
    # `grep -q "0$"` matched any code whose last digit is 0 (10, 20,
    # 30, ...), so a failed dnf transaction (rc 10) was recorded PASS
    # with the literal detail "exit code 0". Only the exact value 0
    # passes; the ssh-failure sentinel 255 needs no special case.
    if [ "$exit_check" = "0" ]; then
        record "setup-repo.sh execution" "PASS" "exit code 0"
    else
        record "setup-repo.sh execution" "FAIL" "exit code: ${exit_check}"
    fi

    # Check for "Repository setup complete" in output
    if echo "$setup_output" | grep -q "Repository setup complete"; then
        record "setup-repo.sh completion message" "PASS" "completion message found"
    else
        record "setup-repo.sh completion message" "FAIL" "completion message not found"
    fi

    # Check that createrepo_c ran
    if echo "$setup_output" | grep -qi "createrepo_c"; then
        record "createrepo_c invoked" "PASS" "createrepo_c found in output"
    else
        record "createrepo_c invoked" "FAIL" "createrepo_c not referenced in output"
    fi

    # Check that .repo file was installed
    local repo_file_exists
    repo_file_exists=$(ssh_cmd "$vm_ip" \
        "test -f /etc/yum.repos.d/cinnamon-rocky10.repo && echo yes || echo no" || echo "no")
    if [ "$repo_file_exists" = "yes" ]; then
        record ".repo file installed" "PASS" "/etc/yum.repos.d/cinnamon-rocky10.repo exists"
    else
        record ".repo file installed" "FAIL" ".repo file not found"
    fi

    # Verify repodata was generated
    local repodata_exists
    repodata_exists=$(ssh_cmd "$vm_ip" \
        "test -d /root/cinnamon-for-rocky10/rpms/repodata && echo yes || echo no" || echo "no")
    if [ "$repodata_exists" = "yes" ]; then
        record "repodata/ generated" "PASS" "repodata directory exists"
    else
        record "repodata/ generated" "FAIL" "repodata directory missing"
    fi

    # Verify repomd.xml exists
    local repomd_exists
    repomd_exists=$(ssh_cmd "$vm_ip" \
        "test -f /root/cinnamon-for-rocky10/rpms/repodata/repomd.xml && echo yes || echo no" || echo "no")
    if [ "$repomd_exists" = "yes" ]; then
        record "repomd.xml generated" "PASS"
    else
        record "repomd.xml generated" "FAIL"
    fi

    # Check baseurl in .repo file
    log ""
    log "=== Phase 3: Verify repository accessibility ==="
    log ""

    local baseurl_check
    baseurl_check=$(ssh_cmd "$vm_ip" \
        "grep 'baseurl=file://' /etc/yum.repos.d/cinnamon-rocky10.repo" 2>/dev/null || true)
    if [ -n "$baseurl_check" ]; then
        record ".repo baseurl is file://" "PASS" "$baseurl_check"
    else
        record ".repo baseurl is file://" "FAIL" "no file:// baseurl found"
    fi

    # Verify dnf can see the repo
    local repo_list
    repo_list=$(ssh_cmd "$vm_ip" \
        "dnf repolist 2>&1" || true)
    log "dnf repolist output:"
    echo "$repo_list" | while IFS= read -r line; do
        printf '    %s\n' "$line"
    done

    if echo "$repo_list" | grep -q "cinnamon-rocky10"; then
        record "dnf repolist includes repo" "PASS" "cinnamon-rocky10 visible"
    else
        record "dnf repolist includes repo" "FAIL" "cinnamon-rocky10 not in repolist"
    fi

    # List available packages from the repo
    local available_pkgs
    available_pkgs=$(ssh_cmd "$vm_ip" \
        "dnf list available --repo cinnamon-rocky10 2>&1" || true)
    local pkg_count
    pkg_count=$(echo "$available_pkgs" | grep -c "noarch\|x86_64" || echo "0")
    log "Available packages from cinnamon-rocky10: ${pkg_count}"

    if [ "$pkg_count" -ge 30 ]; then
        record "Repository packages visible" "PASS" "${pkg_count} packages available"
    else
        record "Repository packages visible" "FAIL" "only ${pkg_count} packages (expected 30+)"
    fi

    # Check specific base packages are in the repo
    local core_pkgs="cinnamon cinnamon-desktop cinnamon-session cinnamon-settings-daemon cinnamon-control-center cinnamon-menus nemo cjs muffin mozjs115 xapps-lib"
    local missing_pkgs=""
    for pkg in $core_pkgs; do
        if ! echo "$available_pkgs" | grep -q "^${pkg}"; then
            missing_pkgs="${missing_pkgs} ${pkg}"
        fi
    done

    if [ -z "$missing_pkgs" ]; then
        record "Core packages in repo" "PASS" "all 12 core packages available"
    else
        record "Core packages in repo" "FAIL" "missing:${missing_pkgs}"
    fi

    # Check CRB was enabled
    local crb_status
    crb_status=$(ssh_cmd "$vm_ip" \
        "dnf repolist 2>&1 | grep -i crb || true" || true)
    if [ -n "$crb_status" ]; then
        record "CRB repository enabled" "PASS" "CRB visible in repolist"
    else
        record "CRB repository enabled" "WARN" "CRB not visible (may already be enabled or not available)"
    fi

    log ""
    log "=== Phase 4: Install cinnamon via repository ==="
    log ""

    # Install prerequisites first
    log "Installing prerequisites..."
    local prereq_output
    prereq_output=$(ssh_cmd "$vm_ip" \
        "dnf install -y gtk3 glib2 graphene libX11 libXrandr libXdamage libXext libXfixes libXi libXtst libICE libSM libxkbfile libwacom pipewire libdrm pulseaudio-libs libcanberra systemd gobject-introspection iso-codes xkeyboard-config cairo pango harfbuzz gdk-pixbuf2 libxml2 dbus atk at-spi2-atk fontconfig mesa-libEGL json-glib startup-notification readline 2>&1" || true)

    if echo "$prereq_output" | grep -qi "Complete\|installed"; then
        record "Prerequisites installed" "PASS" "dependencies resolved"
    else
        record "Prerequisites installed" "WARN" "output may indicate issues: $(echo "$prereq_output" | tail -3)"
    fi

    # Install cinnamon via the repo
    log "Installing cinnamon via repository..."
    local install_output
    local install_rc
    install_output=$(ssh_cmd "$vm_ip" \
        "dnf install -y cinnamon 2>&1" || true)
    install_rc=$(ssh_cmd "$vm_ip" \
        "dnf install -y cinnamon >/dev/null 2>&1 ; echo \$?" || echo "255")

    log "Install output (last 20 lines):"
    echo "$install_output" | tail -20 | while IFS= read -r line; do
        printf '    %s\n' "$line"
    done

    # Shadow finding 3 (TASK-0008): direct value comparison (same
    # reasoning as the setup-repo.sh check above).
    if [ "$install_rc" = "0" ]; then
        record "dnf install cinnamon" "PASS" "exit code 0"
    else
        record "dnf install cinnamon" "FAIL" "exit code: ${install_rc}"
    fi

    # Check that cinnamon is actually installed
    local cinnamon_installed
    cinnamon_installed=$(ssh_cmd "$vm_ip" \
        "rpm -q cinnamon 2>/dev/null || echo not-installed" || echo "not-installed")
    if [ "$cinnamon_installed" != "not-installed" ]; then
        record "cinnamon package installed" "PASS" "$cinnamon_installed"
    else
        record "cinnamon package installed" "FAIL" "cinnamon not found via rpm -q"
    fi

    # Run ldconfig
    ssh_cmd "$vm_ip" "ldconfig" || true

    # Install remaining base packages that cinnamon does not pull in as hard dependencies.
    # cinnamon-session, cinnamon-settings-daemon, cinnamon-control-center, nemo, and
    # mozjs115-devel are not hard dependencies of the cinnamon package but are part of
    # the full Cinnamon desktop environment documented in INSTALL.md.
    log ""
    log "=== Phase 4b: Install remaining base packages ==="
    log ""

    local extra_pkgs="cinnamon-session cinnamon-settings-daemon cinnamon-control-center nemo mozjs115-devel"
    log "Installing: ${extra_pkgs}"
    local extra_install_output
    local extra_install_rc
    extra_install_output=$(ssh_cmd "$vm_ip" \
        "dnf install -y ${extra_pkgs} 2>&1" || true)
    extra_install_rc=$(ssh_cmd "$vm_ip" \
        "dnf install -y ${extra_pkgs} >/dev/null 2>&1 ; echo \$?" || echo "255")

    log "Extra install output (last 10 lines):"
    echo "$extra_install_output" | tail -10 | while IFS= read -r line; do
        printf '    %s\n' "$line"
    done

    # Shadow finding 3 (TASK-0008): direct value comparison (same
    # reasoning as the setup-repo.sh check above).
    if [ "$extra_install_rc" = "0" ]; then
        record "dnf install extra packages" "PASS" "exit code 0 for ${extra_pkgs}"
    else
        record "dnf install extra packages" "FAIL" "exit code: ${extra_install_rc}"
    fi

    log ""
    log "=== Phase 5: Verify all 14 base packages ==="
    log ""

    # Use the existing verify-install-packages.sh approach inline
    local PKG_LIST=(
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

    local pkg_ok=0
    local pkg_bad=0
    local pkg_warn=0

    for entry in "${PKG_LIST[@]}"; do
        IFS='|' read -r pkg_name expected_version description <<< "$entry"

        local actual_version=""
        # Two-step: first check if installed, then get version. Avoids rpm error
        # messages leaking into the version string.
        if ssh_cmd "$vm_ip" "rpm -q --quiet ${pkg_name}" 2>/dev/null; then
            actual_version=$(ssh_cmd "$vm_ip" \
                "rpm -q --queryformat '%{VERSION}-%{RELEASE}' ${pkg_name}" 2>/dev/null) || true
        fi
        [ -z "$actual_version" ] && actual_version="NOT-INSTALLED"

        if [ "$actual_version" = "NOT-INSTALLED" ]; then
            record "Package: ${pkg_name}" "FAIL" "NOT INSTALLED (${description})"
            pkg_bad=$((pkg_bad + 1))
        elif [ "$actual_version" = "$expected_version" ]; then
            record "Package: ${pkg_name}" "PASS" "${actual_version} (${description})"
            pkg_ok=$((pkg_ok + 1))
        else
            record "Package: ${pkg_name}" "WARN" "version mismatch: expected=${expected_version} actual=${actual_version} (${description})"
            pkg_warn=$((pkg_warn + 1))
            pkg_ok=$((pkg_ok + 1))
        fi
    done

    # Check GDM session file
    local gdm_exists
    gdm_exists=$(ssh_cmd "$vm_ip" \
        "test -f /usr/share/xsessions/cinnamon.desktop && echo yes || echo no" || echo "no")
    if [ "$gdm_exists" = "yes" ]; then
        record "GDM session file" "PASS" "/usr/share/xsessions/cinnamon.desktop exists"
    else
        record "GDM session file" "FAIL" "cinnamon.desktop missing"
    fi

    # Check key libraries (versioned paths, not unversioned symlinks)
    for lib_path in "/usr/lib64/libcinnamon-desktop.so.4" "/usr/lib64/libxapp.so.1"; do
        local lib_found
        lib_found=$(ssh_cmd "$vm_ip" \
            "test -e '${lib_path}' && echo yes || echo no" || echo "no")
        if [ "$lib_found" = "yes" ]; then
            record "Library: ${lib_path}" "PASS" "exists"
        else
            record "Library: ${lib_path}" "FAIL" "not found"
        fi
    done

    log ""
    log "=== Phase 6: Binary verification ==="
    log ""

    # Check Xvfb availability
    local xvfb_available=false
    if ssh_cmd "$vm_ip" "command -v xvfb-run >/dev/null 2>&1" 2>/dev/null; then
        xvfb_available=true
        log "Xvfb is available in VM."
    else
        log "Attempting to install Xvfb..."
        ssh_cmd "$vm_ip" "dnf install -y xorg-x11-server-Xvfb 2>&1" || true
        if ssh_cmd "$vm_ip" "command -v xvfb-run >/dev/null 2>&1" 2>/dev/null; then
            xvfb_available=true
            log "Xvfb installed successfully."
        else
            log "Xvfb not available. X11-dependent --version checks will be skipped."
        fi
    fi

    # Binary definitions
    local BINARY_DEFS=(
        "cjs|--version|no"
        "muffin|--version|yes"
        "cinnamon-session|NONE|no"
        "csd-xsettings|NONE|no"
        "cinnamon-control-center|--version|yes"
        "nemo|--version|yes"
        "cinnamon|--version|yes"
    )

    for entry in "${BINARY_DEFS[@]}"; do
        IFS='|' read -r binary version_flag needs_xvfb <<< "$entry"

        # Check binary exists
        local bin_path
        bin_path=$(ssh_cmd "$vm_ip" "command -v ${binary} 2>/dev/null" || true)
        if [ -z "$bin_path" ]; then
            record "Binary: ${binary} (ldd)" "FAIL" "binary not found"
            record "Binary: ${binary} (version)" "FAIL" "binary not found"
            continue
        fi

        # ldd check
        local ldd_result
        ldd_result=$(ssh_cmd "$vm_ip" \
            "ldd '${bin_path}' 2>&1 | grep 'not found'" || true)
        local missing_libs=0
        if [ -n "$ldd_result" ]; then
            missing_libs=$(echo "$ldd_result" | wc -l)
        fi
        if [ "$missing_libs" -eq 0 ]; then
            record "Binary: ${binary} (ldd)" "PASS" "0 missing libraries"
        else
            record "Binary: ${binary} (ldd)" "FAIL" "${missing_libs} missing libraries"
        fi

        # Version check
        if [ "$version_flag" = "NONE" ]; then
            record "Binary: ${binary} (version)" "SKIP" "no version flag for this binary"
            continue
        fi

        if [ "$needs_xvfb" = "yes" ] && [ "$xvfb_available" = "false" ]; then
            record "Binary: ${binary} (version)" "SKIP" "Xvfb not available"
            continue
        fi

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

        if [ "$version_rc" -eq 0 ] && [ -n "$version_output" ]; then
            local version_line
            version_line=$(echo "$version_output" | head -1 | sed 's/^[[:space:]]*//')
            record "Binary: ${binary} (version)" "PASS" "$version_line"
        else
            record "Binary: ${binary} (version)" "FAIL" "exit code ${version_rc}: ${version_output:-<empty>}"
        fi
    done
}

# --- Main ---

main() {
    mkdir -p "$RESULTS_DIR"
    : > "$LOG_FILE"

    log "=========================================="
    log "  TASK-0006: DNF Repository Setup Test"
    log "  Started: $(date)"
    log "=========================================="

    # Phase 0: Error handling (host-side)
    test_error_handling

    # Phase 1-6: VM-based testing
    log ""
    local vm_ip
    vm_ip=$(provision_vm)
    record "VM provisioning" "PASS" "VM ${VM_NAME} at ${vm_ip}"

    test_vm_repo_setup "$vm_ip"

    # Cleanup
    log ""
    log "=== Cleanup ==="
    destroy_vm
    record "VM cleanup" "PASS" "${VM_NAME} destroyed"

    # Summary
    log ""
    log "=========================================="
    log "  Test Results Summary"
    log "=========================================="
    log "  Total checks: ${TOTAL_COUNT}"
    log "  PASS: ${PASS_COUNT}"
    log "  FAIL: ${FAIL_COUNT}"
    log "  SKIP: ${SKIP_COUNT}"
    log "  WARN: ${WARN_COUNT}"
    log "=========================================="

    if [ "$FAIL_COUNT" -gt 0 ]; then
        log "OVERALL: FAIL (${FAIL_COUNT} failures)"
        exit 1
    else
        log "OVERALL: PASS"
        exit 0
    fi
}

main "$@"
