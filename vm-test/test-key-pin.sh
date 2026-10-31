#!/usr/bin/env bash
# test-key-pin.sh — Host-side test for the tracked-key pin in
# repo-setup/setup-repo.sh (TASK-0038, Omega high finding, 2026-10-31).
#
# The key file keys/cinnamon-rocky10-public.asc is tree-controlled, so
# the post-import keyid check alone proves presence, not the absence of
# extra keys. setup-repo.sh therefore pins the full tracked key set
# (primary + signing subkey, nothing else) against a throwaway keyring
# before rpm --import. This harness exercises that pin with the
# script's own code:
#
#   1. bash -n on setup-repo.sh.
#   2. The script's own die/info/verify_tracked_key_file functions and
#      EXPECTED_*_FINGERPRINT constants, extracted from the real file
#      and eval'd, run against six key file variants.
#   3. The real setup-repo.sh run as root against a synthetic project
#      root whose key file carries the tracked key plus an attacker
#      key, asserting the pin dies before any host state change (rpm
#      keyring, /etc/yum.repos.d, createrepo_c).
#
# No secret key material is used. The attacker key is a throwaway key
# generated for this run, exported as public-only, and its keyring
# deleted before the variants are used.
#
# Usage: test-key-pin.sh [PROJECT_DIR]
#
# Results are written to vm-test/results/key-pin.log

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${1:-$(cd -P "${SCRIPT_DIR}/.." && pwd)}"
SCRIPT="${PROJECT_DIR}/repo-setup/setup-repo.sh"
KEY_FILE="${PROJECT_DIR}/keys/cinnamon-rocky10-public.asc"
RESULTS_DIR="${PROJECT_DIR}/vm-test/results"
LOG_FILE="${RESULTS_DIR}/key-pin.log"

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0
TOTAL_COUNT=0

log() { printf '[key-pin] %s\n' "$*"; }

record() {
    local check="$1"
    local result="$2"
    local detail="${3:-}"
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    if [ "$result" = "PASS" ]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        printf '[PASS] %-55s %s\n' "$check" "$detail"
    elif [ "$result" = "SKIP" ]; then
        SKIP_COUNT=$((SKIP_COUNT + 1))
        printf '[SKIP] %-55s %s\n' "$check" "$detail"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        printf '[FAIL] %-55s %s\n' "$check" "$detail"
    fi
    echo "[$result] $check $detail" >> "$LOG_FILE"
}

die() { printf '[key-pin] ERROR: %s\n' "$*" >&2; exit 1; }

WORK_DIR="$(mktemp -d)"
cleanup() { rm -rf "${WORK_DIR}"; }
trap cleanup EXIT

mkdir -p "${RESULTS_DIR}"
: > "${LOG_FILE}"

# --- Extract the pin from the real script ---

# The harness runs the script's own functions and constants, not copies.
# Each definition is a column-0 block ending in a column-0 '}'.
DIE_SRC="$(sed -n '/^die() {/,/^}/p' "$SCRIPT")"
INFO_SRC="$(sed -n '/^info() {/,/^}/p' "$SCRIPT")"
CHECK_SRC="$(sed -n '/^verify_tracked_key_file() {/,/^}/p' "$SCRIPT")"
CONSTS_SRC="$(grep -E '^EXPECTED_(PRIMARY|SUBKEY)_FINGERPRINT=' "$SCRIPT")"
[ -n "$DIE_SRC" ] && [ -n "$INFO_SRC" ] && [ -n "$CHECK_SRC" ] && [ -n "$CONSTS_SRC" ] \
    || die "could not extract die/info/verify_tracked_key_file/EXPECTED_*_FINGERPRINT from ${SCRIPT}"
eval "$CONSTS_SRC"
eval "$DIE_SRC"
eval "$INFO_SRC"
eval "$CHECK_SRC"

# --- Build the key file variants ---

# Throwaway attacker keyring. The private key never leaves this
# directory; only the public export is kept, and the directory is
# removed right after the export. A batch-file passphrase is required:
# this gpg build (2.4.5) routes an empty or absent passphrase through
# pinentry, and the unattended generation then times out (observed on
# the team host). The passphrase is test text for a throwaway key, not
# a credential.
ATTACKER_HOME="${WORK_DIR}/attacker-home"
mkdir -p "${ATTACKER_HOME}"
chmod 700 "${ATTACKER_HOME}"
printf 'Key-Type: default\nKey-Length: 2048\nSubkey-Type: default\nName-Real: keypin attacker\nName-Email: keypin-attacker@example.invalid\nExpire-Date: 0\nPassphrase: keypin-throwaway-test\n%%commit\n' \
    > "${WORK_DIR}/genkey.conf"
gpg --homedir "${ATTACKER_HOME}" --batch --gen-key "${WORK_DIR}/genkey.conf" \
    >/dev/null 2>&1 \
    || die "could not generate the throwaway attacker key."
gpg --homedir "${ATTACKER_HOME}" --armor --export > "${WORK_DIR}/attacker.asc" \
    || die "could not export the throwaway attacker public key."
rm -rf "${ATTACKER_HOME}"

cp "${KEY_FILE}" "${WORK_DIR}/tracked.asc"
cat "${KEY_FILE}" "${WORK_DIR}/attacker.asc" > "${WORK_DIR}/tracked-plus-attacker.asc"
cat "${KEY_FILE}" "${KEY_FILE}" > "${WORK_DIR}/tracked-twice.asc"
printf 'this is not a key file\n' > "${WORK_DIR}/garbage.asc"
: > "${WORK_DIR}/empty.asc"

# --- Test 1: syntax ---

if bash -n "$SCRIPT" 2>/dev/null; then
    record "setup-repo.sh syntax check" "PASS" "no syntax errors"
else
    record "setup-repo.sh syntax check" "FAIL" "syntax errors detected"
fi

# --- Test 2: the pin, run as the script's own function ---

# Each case runs in a command-substitution subshell so the pin's own
# die/exit and EXIT-trap cleanup stay inside the case.
pin_case() {
    local file="$1"
    verify_tracked_key_file "${file}"
}

check_variant() {
    local label="$1" file="$2" expect_rc="$3" expect_msg="$4"
    local out="" rc=0
    out="$(pin_case "${file}" 2>&1)" || rc=$?
    if [ "$rc" -eq "$expect_rc" ] && { [ -z "$expect_msg" ] || grep -q "$expect_msg" <<< "$out"; }; then
        record "$label" "PASS" "rc=${rc}"
    else
        record "$label" "FAIL" "rc=${rc} (expected ${expect_rc}); output: ${out}"
    fi
}

check_variant "pin: tracked key file passes" \
    "${WORK_DIR}/tracked.asc" 0 ""
check_variant "pin: tracked key + attacker key fails" \
    "${WORK_DIR}/tracked-plus-attacker.asc" 1 "does not hold exactly the tracked key"
check_variant "pin: attacker key only fails" \
    "${WORK_DIR}/attacker.asc" 1 "does not hold exactly the tracked key"
check_variant "pin: duplicated tracked key passes (no extra key)" \
    "${WORK_DIR}/tracked-twice.asc" 0 ""
check_variant "pin: non-armor file fails" \
    "${WORK_DIR}/garbage.asc" 1 "not a valid armored public key"
check_variant "pin: empty file fails" \
    "${WORK_DIR}/empty.asc" 1 "not a valid armored public key"

# --- Test 3: the real script, run as root against a synthetic root ---

# The synthetic root carries the tracked key plus an attacker key. The
# real script must die at the pin, before rpm --import and before any
# state change. Guards: createrepo_c must already be installed (the
# script would otherwise dnf install it, a host state change), and
# passwordless sudo must be available.
host_state() {
    { rpm -qa 2>/dev/null | grep '^gpg-pubkey-' | LC_ALL=C sort; } || true
    { find /etc/yum.repos.d -maxdepth 1 -name '*.repo' -type f -exec md5sum {} + 2>/dev/null | LC_ALL=C sort; } || true
    if rpm -q --quiet createrepo_c 2>/dev/null; then
        echo "createrepo_c:installed"
    else
        echo "createrepo_c:absent"
    fi
}

if ! command -v createrepo_c >/dev/null 2>&1; then
    record "end-to-end: root run with attacker key file" "SKIP" "createrepo_c not installed on the host (the run would trigger dnf install)"
elif ! sudo -n true >/dev/null 2>&1; then
    record "end-to-end: root run with attacker key file" "SKIP" "passwordless sudo unavailable"
else
    ROOT_DIR="${WORK_DIR}/synthetic-root"
    mkdir -p "${ROOT_DIR}/rpms/repodata" "${ROOT_DIR}/keys"
    # One real RPM so the pre-flight count passes; the run dies at the
    # pin before anything consumes it.
    cp "$(find "${PROJECT_DIR}/rpms" -maxdepth 1 -name '*.rpm' | head -1)" "${ROOT_DIR}/rpms/"
    # Pre-existing repodata/repomd.xml makes step 2 skip generation.
    : > "${ROOT_DIR}/rpms/repodata/repomd.xml"
    cp "${WORK_DIR}/tracked-plus-attacker.asc" "${ROOT_DIR}/keys/cinnamon-rocky10-public.asc"

    state_before="$(host_state)"
    rc=0
    root_out="$(sudo bash "$SCRIPT" "${ROOT_DIR}" 2>&1)" || rc=$?
    state_after="$(host_state)"

    if [ "$rc" -eq 1 ] && grep -q "does not hold exactly the tracked key" <<< "$root_out" \
        && [ "$state_before" = "$state_after" ]; then
        record "end-to-end: root run with attacker key file" "PASS" "rc=1 at the pin, no host state change (rpm keyring, /etc/yum.repos.d, createrepo_c)"
    else
        record "end-to-end: root run with attacker key file" "FAIL" "rc=${rc}; output: ${root_out}"
        if [ "$state_before" != "$state_after" ]; then
            diff <(printf '%s\n' "$state_before") <(printf '%s\n' "$state_after") >&2 || true
        fi
    fi
fi

# --- Summary ---

log ""
log "Total checks: ${TOTAL_COUNT}"
log "PASS: ${PASS_COUNT}  FAIL: ${FAIL_COUNT}  SKIP: ${SKIP_COUNT}"

if [ "$FAIL_COUNT" -gt 0 ]; then
    log "OVERALL: FAIL"
    exit 1
fi
log "OVERALL: PASS"
exit 0
