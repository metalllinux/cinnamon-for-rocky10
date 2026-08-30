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
#   2. Install createrepo_c if missing.
#   3. Generate metadata with createrepo_c if the repodata/ directory is absent.
#   4. Write /etc/yum.repos.d/cinnamon-rocky10.repo pointing at the rpms/ path.
#   5. Enable the CRB (CodeReady Builder) repository.
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
# Step 1 — Install createrepo_c if missing
# -------------------------------------------------------------------
if ! command -v createrepo_c >/dev/null 2>&1; then
    info "createrepo_c not found. Installing..."
    dnf install -y createrepo_c || die "Failed to install createrepo_c."
else
    info "createrepo_c already installed ($(createrepo_c --version 2>&1 | head -1))."
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
# Step 3 — Install the .repo file
# -------------------------------------------------------------------
# Build the absolute file:// URL for the rpms/ directory.
BASEURL="file://${RPMS_DIR}"

info "Installing ${REPO_FILE} with baseurl=${BASEURL}"

# Write the repo file directly with printf. This avoids sed delimiter collisions
# when the path contains the sed delimiter character (e.g. |).
printf '[%s]\nname=%s\nbaseurl=%s\nenabled=%s\ngpgcheck=%s\nmetadata_expire=%s\nmodule_hotfixes=%s\nkeepcache=%s\n' \
    "cinnamon-rocky10" \
    "Cinnamon for Rocky Linux 10 (local)" \
    "${BASEURL}" \
    "1" \
    "0" \
    "0" \
    "0" \
    "0" \
    > "$REPO_FILE" || die "Failed to write ${REPO_FILE}."

# Explicitly set restrictive permissions. Do not rely on umask.
chmod 644 "$REPO_FILE"

info "Repository file installed at ${REPO_FILE}."

# -------------------------------------------------------------------
# Step 4 — Enable CRB repository
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
# Step 5 — Verify the repository is readable
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
