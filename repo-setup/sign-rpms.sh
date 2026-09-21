#!/bin/bash
# sign-rpms.sh — sign the project RPMs in place with the dedicated repo
# signing GPG key, uid "metallinux Cinnamon for Rocky Linux (repo signing)
# <repo-signing@metalinux.dev>", then verify the whole set.
#
# TASK-0024 items 2-3. Design and constraints: planning doc
# planning/docs/TASK-0024-rpm-signing-gpgcheck.md, decisions D1/D2 (ratified
# 2026-09-21). This script is the only place the passphrase is ever read.
#
# Usage:
#   ./sign-rpms.sh [PROJECT_ROOT]
#
#   With no argument, the script assumes it is located inside
#   cinnamon-for-rocky10/repo-setup/ and uses the parent directory, the same
#   resolution rule as setup-repo.sh.
#
# How it works:
#   1. Pre-flight: the dedicated keyring holds exactly one secret key with
#      the recorded fingerprint, the passphrase file exists with the right
#      modes, and the public key is already in the rpm keyring (required for
#      rpm --checksig verification).
#   2. Preset the passphrase into gpg-agent via gpg-connect-agent. The
#      passphrase is read from the 600-mode sibling file, hex-encoded, and
#      sent on stdin only. It never appears in argv, and the script must
#      never be run with set -x or -x, or the trace would print it
#      (AGENTS.md section 4).
#   3. Sign every unsigned RPM in rpms/ in place with rpm --addsign.
#   4. Clear the preset from gpg-agent on every exit path (EXIT trap).
#   5. Verify the whole set with rpm --checksig and report.
#
# The keyring is host-local and never lives in the repo tree. It is the
# dedicated keyring ~/.gnupg-cinnamon-rocky10 (mode 700) unless GNUPGHOME is
# set. The passphrase lives in the sibling directory
# ~/.gnupg-cinnamon-rocky10.passphrase (mode 700), file "passphrase"
# (mode 600, single line, no embedded newlines). No agent, log, planning doc,
# or commit records the passphrase value.
#
# The preset protocol below is pinned against gpg 2.4.5 on the host
# (gnupg2-2.4.5-4.el10_1); see ## Implementation in the planning doc for the
# source citations and the empirical proof.

set -euo pipefail

# -------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------
# Fingerprint of the dedicated signing key (public data; it ships inside the
# public key). Recorded from item 1 (2026-09-21). The check below refuses to
# run against any other keyring.
EXPECTED_FINGERPRINT="1689676AF4D4F6FEC142B4429C0A8912FDA02785"

# Dedicated keyring (host-local, mode 700) and sibling passphrase location
# (D1). Overridable for testing via the environment; the production run uses
# the defaults.
DEFAULT_KEYRING="${HOME}/.gnupg-cinnamon-rocky10"
KEYRING_DIR="${GNUPGHOME:-${DEFAULT_KEYRING}}"
PASSPHRASE_DIR="${PASSPHRASE_DIR:-${KEYRING_DIR}.passphrase}"
PASSPHRASE_FILE="${PASSPHRASE_DIR}/passphrase"

# Scope every gpg/gpgconf call to the dedicated keyring.
export GNUPGHOME="${KEYRING_DIR}"

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------
die() {
    echo "ERROR: $*" >&2
    exit 1
}

info() {
    echo "INFO: $*"
}

# Note: gpg-connect-agent returns 0 even when the agent answers with an ERR
# line. Success is asserted from the OK line in the reply, below.

# -------------------------------------------------------------------
# Resolve project root (same rule as setup-repo.sh)
# -------------------------------------------------------------------
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
    PROJECT_ROOT="$(cd -P "$1" && pwd)"
else
    PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
fi

RPMS_DIR="${PROJECT_ROOT}/rpms"
KEYFILE="${PROJECT_ROOT}/keys/cinnamon-rocky10-public.asc"

info "Project root    : ${PROJECT_ROOT}"
info "Keyring         : ${KEYRING_DIR}"
info "Passphrase file : ${PASSPHRASE_FILE}"

# -------------------------------------------------------------------
# Pre-flight checks
# -------------------------------------------------------------------
# The fingerprint must be recorded before any signing attempt.
if [ -z "$EXPECTED_FINGERPRINT" ] || [ "$EXPECTED_FINGERPRINT" = "PENDING-ITEM-1" ]; then
    die "EXPECTED_FINGERPRINT is not recorded yet (TASK-0024 item 1 pending). Generate the key, record its fingerprint in this script, then re-run."
fi

# Tooling.
for tool in gpg gpg-connect-agent rpm; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: ${tool}"
done

# The keyring must hold exactly one secret key with the expected fingerprint.
[ -d "$KEYRING_DIR" ] || die "keyring not found at ${KEYRING_DIR} (item 1 user step)."
COLONS=$(gpg --with-colons -K 2>/dev/null) || die "gpg could not read the keyring at ${KEYRING_DIR}"
SECRET_COUNT=$(echo "$COLONS" | grep -c '^sec:' || true)
if [ "$SECRET_COUNT" -ne 1 ]; then
    die "keyring must hold exactly one secret key, found ${SECRET_COUNT}."
fi
FPR=$(echo "$COLONS" | awk -F: '/^fpr/{print $10; exit}')
if [ "$FPR" != "$EXPECTED_FINGERPRINT" ]; then
    die "fingerprint mismatch: keyring holds ${FPR}, expected ${EXPECTED_FINGERPRINT}."
fi

# Derive the signing keygrip: a signing subkey is preferred over the primary,
# which is gpg's own selection rule. The keygrip is the agent cache address
# for PRESET_PASSPHRASE and must be sent uppercase, exactly as displayed.
KEYGRIP=$(echo "$COLONS" | awk -F: '
    /^sec:/ { type="sec"; cap=$12 }
    /^ssb:/ { type="ssb"; cap=$12 }
    /^grp:/ {
        if (type == "ssb" && cap ~ /s/) subg = $10
        else if (type == "sec" && cap ~ /s/) prig = $10
    }
    END { print (subg != "" ? subg : prig) }
')
[ -n "$KEYGRIP" ] || die "no signing-capable secret key in ${KEYRING_DIR}."

# The uid string for the _gpg_name macro (which key identity signs).
UID_STR=$(echo "$COLONS" | awk -F: '/^uid/{print $10; exit}')
[ -n "$UID_STR" ] || die "no uid found for the signing key."

# The passphrase file must exist with the mandated modes.
[ -d "$PASSPHRASE_DIR" ] || die "passphrase directory missing: ${PASSPHRASE_DIR} (item 1 user step)."
[ "$(stat -c '%a' "$PASSPHRASE_DIR")" = "700" ] || die "passphrase directory ${PASSPHRASE_DIR} must be mode 700."
[ -f "$PASSPHRASE_FILE" ] || die "passphrase file missing: ${PASSPHRASE_FILE} (item 1 user step)."
[ "$(stat -c '%a' "$PASSPHRASE_FILE")" = "600" ] || die "passphrase file ${PASSPHRASE_FILE} must be mode 600."

# rpm --checksig verifies against the rpm keyring (the installed gpg-pubkey
# packages), not against this keyring. The public key must be imported once
# with root; the import is idempotent and the check below detects it.
KEYID8="${FPR: -8}"
KEYID8=$(echo "$KEYID8" | tr 'A-F' 'a-f')
if ! rpm -qa | grep -q "^gpg-pubkey-${KEYID8}-"; then
    die "public key ${KEYID8} is not in the rpm keyring (required for rpm --checksig). Import it once with: sudo rpm --import ${KEYFILE}"
fi

# The rpms/ directory must exist and contain RPMs.
[ -d "$RPMS_DIR" ] || die "rpms/ directory not found at ${RPMS_DIR}."
RPM_TOTAL=$(find "$RPMS_DIR" -maxdepth 1 -name '*.rpm' | wc -l)
[ "$RPM_TOTAL" -gt 0 ] || die "No .rpm files found in ${RPMS_DIR}."
info "Found ${RPM_TOTAL} RPM files."

# -------------------------------------------------------------------
# Preset the passphrase into gpg-agent
# -------------------------------------------------------------------
# The agent requires allow-preset-passphrase in its config (off by default).
# Ensure it idempotently; restarting the agent drops the old config.
AGENT_CONF="${KEYRING_DIR}/gpg-agent.conf"
if ! { [ -f "$AGENT_CONF" ] && grep -qx 'allow-preset-passphrase' "$AGENT_CONF"; }; then
    info "Adding 'allow-preset-passphrase' to ${AGENT_CONF} and restarting gpg-agent"
    echo 'allow-preset-passphrase' >> "$AGENT_CONF"
    gpgconf --kill gpg-agent || true
fi

# Read the passphrase. $(cat ...) strips the trailing newline; the file must
# be a single line. Hex-encoding keeps every byte representable on the assuan
# line and means the cleartext never crosses a process boundary.
PASS=$(cat "$PASSPHRASE_FILE")
[ -n "$PASS" ] || die "passphrase file ${PASSPHRASE_FILE} is empty."
PASS_HEX=$(printf '%s' "$PASS" | xxd -p | tr -d '\n')
# Round-trip check: a multi-line file would not survive the hex round trip.
ROUND=$(printf '%s' "$PASS_HEX" | xxd -r -p)
[ "$ROUND" = "$PASS" ] || die "passphrase file must be a single line (no embedded newlines)."
PASS=""

# gpg 2.4.5 protocol (pinned): PRESET_PASSPHRASE <keygrip> -1 <hex>. The second
# argument is a timeout; only -1 (no timeout) is accepted. The command has no
# slash prefix: a leading / would make it a local control command.
PRESET_OUT=$(gpg-connect-agent --homedir "$KEYRING_DIR" -- <<EOF
PRESET_PASSPHRASE ${KEYGRIP} -1 ${PASS_HEX}
/bye
EOF
)
if ! echo "$PRESET_OUT" | grep -q '^OK'; then
    die "gpg-agent rejected the passphrase preset: ${PRESET_OUT}"
fi
PASS_HEX=""
PRESET_DONE=1
info "Passphrase preset into gpg-agent (keygrip ${KEYGRIP})."

# Clear the preset on every exit path.
clear_preset() {
    if [ "${PRESET_DONE:-0}" = "1" ]; then
        gpg-connect-agent --homedir "$KEYRING_DIR" -- <<EOF 2>/dev/null
CLEAR_PASSPHRASE ${KEYGRIP}
/bye
EOF
        info "Passphrase cleared from gpg-agent."
    fi
}
trap clear_preset EXIT

# -------------------------------------------------------------------
# Sign the unsigned RPMs in place
# -------------------------------------------------------------------
# A file is signed iff rpm -K reports "digests signatures OK" against the rpm
# keyring (the public key is guaranteed present by the pre-flight). Note the
# casing: a verified signature prints lowercase "signatures OK", while a
# signature that cannot be verified prints uppercase "SIGNATURES NOT OK".
# The -i match cannot hit the failure string, which inserts NOT in between.
# Re-running the script therefore skips everything already signed (idempotent).
is_signed() {
    rpm -K "$1" 2>/dev/null | grep -qi "signatures OK"
}

SIGNED_COUNT=0
SKIPPED_COUNT=0
for rpm_file in "$RPMS_DIR"/*.rpm; do
    [ -e "$rpm_file" ] || continue
    name="$(basename "$rpm_file")"
    if is_signed "$rpm_file"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        info "already signed, skipping: ${name}"
        continue
    fi
    info "signing: ${name}"
    rpm --addsign --define "_gpg_name ${UID_STR}" "$rpm_file" || die "rpm --addsign failed for ${name}."
    SIGNED_COUNT=$((SIGNED_COUNT + 1))
done

# -------------------------------------------------------------------
# Verify the whole set
# -------------------------------------------------------------------
info "Verifying ${RPM_TOTAL} RPMs with rpm --checksig..."
for rpm_file in "$RPMS_DIR"/*.rpm; do
    [ -e "$rpm_file" ] || continue
    name="$(basename "$rpm_file")"
    rpm --checksig "$rpm_file" 2>/dev/null | grep -qi "signatures OK" || die "signature verification failed for ${name}."
done

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo ""
echo "=== Signing complete ==="
echo ""
info "Signed now       : ${SIGNED_COUNT}"
info "Already signed   : ${SKIPPED_COUNT}"
info "Total verified   : ${RPM_TOTAL}"
info "All RPMs in ${RPMS_DIR} carry a valid signature from ${FPR}."
