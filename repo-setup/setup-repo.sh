#!/bin/bash
# setup-repo.sh — install a local DNF repository for Cinnamon RPMs on Rocky Linux 10
#
# Usage:
#   sudo ./setup-repo.sh /path/to/cinnamon-for-rocky10
#
# If no argument is given, the script assumes it is located inside the
# cinnamon-for-rocky10/repo-setup/ directory and uses the parent directory.
#
# The script will:
#   1. Verify the rpms/ directory and its metadata exist.
#   2. Install createrepo_c and gnupg2 if missing.
#   3. Generate metadata with createrepo_c if the repodata/ directory is absent.
#   4. Verify the repo GPG public key holds exactly the tracked key, and
#      import it into the rpm keyring.
#   5. Write /etc/yum.repos.d/cinnamon-rocky10.repo (gpgcheck=1)
#      pointing at the rpms/ path.
#   6. Enable the CRB (CodeReady Builder) repository.
#
# Requires: sudo privileges, dnf, Rocky Linux 10 (or compatible).
#
# Statelessness contract (TASK-0008, Omega medium finding): with an
# argument that does not name an existing directory, the script exits
# at project-root resolution (the cd -P below, under set -euo pipefail)
# BEFORE the root check and before every state-changing step. That
# ordering is load-bearing: vm-test/test-repo-setup.sh runs exactly
# this error path as root on the host and asserts that no host state
# changed. Do not move any state-changing step above the project-root
# resolution without updating that assertion.

set -euo pipefail

# -------------------------------------------------------------------
# Constants
# -------------------------------------------------------------------
REPO_NAME="cinnamon-rocky10"
REPO_FILE="/etc/yum.repos.d/${REPO_NAME}.repo"
# Short GPG key id, lowercase as rpm names it: last 8 hex of fingerprint
# 2274BFE1BF28C051CD98675BEBD13108EB7FEF99. rpm 4.19 names imported key
# packages gpg-pubkey-<keyid>-<import-timestamp>; verified on the host as
# gpg-pubkey-eb7fef99-6ad5798e (the old key read
# gpg-pubkey-fda02785-6ab101f4, TASK-0024 item 1). Public data; the key
# ships at keys/cinnamon-rocky10-public.asc.
KEY_ID="eb7fef99"
# Full fingerprints of the tracked key, primary and signing subkey.
# Public data: the key ships at keys/cinnamon-rocky10-public.asc, the
# primary names KEY_ID above, and sign-rpms.sh pins the same primary as
# EXPECTED_FINGERPRINT (sign-rpms.sh:66).
EXPECTED_PRIMARY_FINGERPRINT="2274BFE1BF28C051CD98675BEBD13108EB7FEF99"
EXPECTED_SUBKEY_FINGERPRINT="CD4958E1A421CBD6B56B7C5614CF2C0A8A47323C"

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

# Throwaway keyring for verify_tracked_key_file, cleaned by the EXIT
# trap. Global (not local) so the trap body can reference it after the
# function frame is gone; the trap is installed only after the
# assignment, so the empty initial value is never used.
KEYCHECK_KEYRING=""

# Verify that a key file holds exactly the tracked key, the primary and
# its signing subkey, and nothing else, before the host rpm
# keyring sees it. The key file is tree-controlled, so the post-import
# keyid check alone proves presence, not the absence of extra keys:
# a file carrying the tracked key plus an attacker key would pass that
# check, and dnf under gpgcheck=1 would then accept attacker-signed
# packages. The file is imported into a throwaway keyring and its full
# fingerprint set compared against the two tracked fingerprints,
# mirroring the EXPECTED_FINGERPRINT pin in sign-rpms.sh:66
# (TASK-0038, Omega high finding, 2026-10-31).
verify_tracked_key_file() {
    local key_file="$1"

    command -v gpg >/dev/null 2>&1 || die "gpg not found (gnupg2). It is required to verify the key file fingerprint before import."

    KEYCHECK_KEYRING="$(mktemp -d)" || die "could not create a temporary keyring directory."
    trap 'rm -rf "${KEYCHECK_KEYRING}"' EXIT

    # Import into the throwaway keyring, never the host keyring. A file
    # that is not a valid armored public key fails here.
    gpg --batch --homedir "${KEYCHECK_KEYRING}" --import "${key_file}" >/dev/null 2>&1 \
        || die "key file ${key_file} is not a valid armored public key."

    # The full key set the file holds, one line per fingerprint.
    local found expected
    found="$(gpg --homedir "${KEYCHECK_KEYRING}" --with-colons --list-keys 2>/dev/null \
        | awk -F: '$1 == "fpr" { print toupper($10) }' | LC_ALL=C sort -u)" \
        || die "gpg could not list the keys of ${key_file}."
    expected="$(printf '%s\n%s\n' "${EXPECTED_PRIMARY_FINGERPRINT}" "${EXPECTED_SUBKEY_FINGERPRINT}" | LC_ALL=C sort -u)"

    if [ "$found" != "$expected" ]; then
        die "key file ${key_file} does not hold exactly the tracked key (expected ${EXPECTED_PRIMARY_FINGERPRINT} plus ${EXPECTED_SUBKEY_FINGERPRINT}, found: $(printf '%s' "$found" | tr '\n' ' ')). Refusing to import."
    fi
}

# -------------------------------------------------------------------
# Resolve project root
# -------------------------------------------------------------------
SCRIPT_DIR="$(cd -P "$(dirname "$0")" && pwd)"

if [ $# -ge 1 ]; then
    PROJECT_ROOT="$(cd -P "$1" && pwd)"
else
    # Assume the script lives in repo-setup/ inside the project
    PROJECT_ROOT="$(cd -P "$SCRIPT_DIR/.." && pwd)"
fi

RPMS_DIR="${PROJECT_ROOT}/rpms"
REPODATA_DIR="${RPMS_DIR}/repodata"

info "Project root : ${PROJECT_ROOT}"
info "RPMs directory: ${RPMS_DIR}"

# -------------------------------------------------------------------
# Pre-flight checks
# -------------------------------------------------------------------
# Must run as root (we need to touch /etc/yum.repos.d/ and install packages).
if [ "$(id -u)" -ne 0 ]; then
    die "This script must be run as root (use sudo)."
fi

# Verify dnf is available.
command -v dnf >/dev/null 2>&1 || die "dnf not found. This script requires Rocky Linux (or a dnf-based distro)."

# Verify the rpms/ directory exists and contains RPMs.
if [ ! -d "$RPMS_DIR" ]; then
    die "rpms/ directory not found at ${RPMS_DIR}. Point the script at the correct project root."
fi

RPM_COUNT=$(find "$RPMS_DIR" -maxdepth 1 -name '*.rpm' | wc -l)
if [ "$RPM_COUNT" -eq 0 ]; then
    die "No .rpm files found in ${RPMS_DIR}."
fi
info "Found ${RPM_COUNT} RPM files."

# -------------------------------------------------------------------
# Step 1 — Install createrepo_c and gnupg2 if missing
# -------------------------------------------------------------------
if ! command -v createrepo_c >/dev/null 2>&1; then
    info "createrepo_c not found. Installing..."
    dnf install -y createrepo_c || die "Failed to install createrepo_c."
else
    info "createrepo_c already installed ($(createrepo_c --version 2>&1 | head -1))."
fi

# gnupg2 provides the gpg binary that verify_tracked_key_file uses to
# pin the tracked key set before the rpm keyring import. It is not in
# the RHEL 10 Core group, so a fresh minimal install carries no gpg;
# the self-install is the same dnf pattern as createrepo_c above, and
# a re-run finds gpg already present and skips the install.
if ! command -v gpg >/dev/null 2>&1; then
    info "gpg (gnupg2) not found. Installing..."
    dnf install -y gnupg2 || die "Failed to install gnupg2."
else
    info "gpg (gnupg2) already installed ($(gpg --version 2>&1 | head -1))."
fi

# -------------------------------------------------------------------
# Step 2 — Generate metadata if absent
# -------------------------------------------------------------------
if [ ! -d "$REPODATA_DIR" ] || [ ! -f "$REPODATA_DIR/repomd.xml" ]; then
    info "Generating repository metadata with createrepo_c..."
    createrepo_c "$RPMS_DIR" || die "createrepo_c failed."
    info "Metadata generated."
else
    info "Repository metadata already present. Skipping generation."
fi

# -------------------------------------------------------------------
# Step 3 — Import the GPG public key into the rpm keyring
# -------------------------------------------------------------------
# TASK-0024 D3: dnf verifies RPM signatures against the rpm keyring
# (the same model as the EL base repos), so the public key is imported
# here and the .repo file written below carries gpgcheck=1 with no
# gpgkey= line. A file:// gpgkey pointing into the clone breaks when a
# follower moves the clone; the imported key is path-independent.
# State-changing, so it stays below project-root resolution (see the
# statelessness contract at the top of this file).
KEY_FILE="${PROJECT_ROOT}/keys/cinnamon-rocky10-public.asc"
if [ ! -f "$KEY_FILE" ]; then
    die "GPG public key not found at ${KEY_FILE}."
fi

# Pin the key set before the import (see verify_tracked_key_file).
verify_tracked_key_file "${KEY_FILE}"
info "Key file holds exactly the tracked key (${EXPECTED_PRIMARY_FINGERPRINT})."

info "Importing repo GPG public key (${KEY_ID}) into the rpm keyring..."
rpm --import "${KEY_FILE}" || die "rpm --import failed for ${KEY_FILE}."

# Assert the key actually landed in the rpm keyring. rpm names imported
# keys gpg-pubkey-<keyid>-<import-timestamp>; the timestamp differs per
# machine, so query by keyid prefix. Re-importing an already-present key
# is a no-op (verified on the host), so this step is idempotent.
if ! rpm -q "gpg-pubkey-${KEY_ID}*" >/dev/null 2>&1; then
    die "Key ${KEY_ID} not found in the rpm keyring after import (expected a gpg-pubkey-${KEY_ID}-<timestamp> package)."
fi
info "Key ${KEY_ID} present in the rpm keyring."

# -------------------------------------------------------------------
# Step 4 — Install the .repo file
# -------------------------------------------------------------------
# Build the absolute file:// URL for the rpms/ directory.
BASEURL="file://${RPMS_DIR}"

info "Installing ${REPO_FILE} with baseurl=${BASEURL}"

# Write the repo file directly with printf. This avoids sed delimiter collisions
# when the path contains the sed delimiter character (e.g. |).
# gpgcheck=1: dnf verifies every package signature against the rpm
# keyring populated in step 3.
printf '[%s]\nname=%s\nbaseurl=%s\nenabled=%s\ngpgcheck=%s\nmetadata_expire=%s\nmodule_hotfixes=%s\nkeepcache=%s\n' \
    "cinnamon-rocky10" \
    "Cinnamon for Rocky Linux 10 (local)" \
    "${BASEURL}" \
    "1" \
    "1" \
    "0" \
    "0" \
    "0" \
    > "$REPO_FILE" || die "Failed to write ${REPO_FILE}."

# Explicitly set restrictive permissions. Do not rely on umask.
chmod 644 "$REPO_FILE"

info "Repository file installed at ${REPO_FILE}."

# -------------------------------------------------------------------
# Step 5 — Enable CRB repository
# -------------------------------------------------------------------
info "Enabling CRB (CodeReady Builder) repository..."
CRB_ERR=$(dnf config-manager --set-enabled crb 2>&1 1>/dev/null) || {
    if echo "$CRB_ERR" | grep -qi "already.*enable\|no.*section\|unknown.*repo"; then
        info "CRB already enabled or not available: ${CRB_ERR}"
    else
        echo "WARNING: CRB enable returned unexpected output: ${CRB_ERR}" >&2
    fi
}

# -------------------------------------------------------------------
# Step 6 — Verify the repository is readable
# -------------------------------------------------------------------
info "Refreshing repository metadata..."
if ! dnf makecache --disablerepo='*' --enablerepo="${REPO_NAME}"; then
    die "dnf makecache failed. The repository is not accessible. Check that the path ${RPMS_DIR} is correct and readable."
fi

# -------------------------------------------------------------------
# Done
# -------------------------------------------------------------------
echo ""
echo "=== Repository setup complete ==="
echo ""
echo "The '${REPO_NAME}' repository is now configured."
echo "Install Cinnamon with:"
echo ""
echo "  dnf install cinnamon"
echo ""
echo "To verify available packages:"
echo ""
echo "  dnf list available --repo ${REPO_NAME}"
echo ""
