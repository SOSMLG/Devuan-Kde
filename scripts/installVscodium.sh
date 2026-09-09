#!/usr/bin/env bash
# =======================================================
# VSCodium (optional)
# -------------------------------------------------------
# Telemetry-free build of VS Code. Installed via the
# official VSCodium APT repository so it stays updated
# through normal `apt upgrade`, rather than a one-off
# GitHub release .deb that never updates itself.
# Source: https://vscodium.com/#install
# Releases (for reference): https://github.com/VSCodium/vscodium/releases
# =======================================================
set -uo pipefail

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} VSCodium${NC}"
echo -e "${CYAN}=========================================================${NC}"

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root."
    exit 1
fi

if is_installed codium; then
    log_ok "VSCodium (codium) is already installed."
    exit 0
fi

for dep in wget gpg; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log_info "Installing dependency: $dep"
        apt_update -qq || true
        sudo apt-get install -y "$dep" || { log_err "Failed to install $dep"; exit 1; }
    fi
done

KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"

log_info "Adding VSCodium's GPG key..."
if wget -qO - "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" \
        | gpg --dearmor | sudo tee "$KEYRING" > /dev/null; then
    log_ok "Key installed to $KEYRING"
else
    log_err "Failed to fetch/install the VSCodium GPG key."
    exit 1
fi

log_info "Adding VSCodium APT repository..."
ARCH="$(dpkg --print-architecture)"
if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" \
        | sudo tee "$SOURCES_FILE" > /dev/null; then
    log_ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
else
    log_err "Failed to write $SOURCES_FILE"
    exit 1
fi

log_info "Updating package lists..."
apt_update || { log_err "apt-get update failed after adding the VSCodium repo."; exit 1; }

log_info "Installing codium..."
if sudo apt-get install -y codium; then
    log_ok "VSCodium installed. Launch it with 'codium'."
else
    log_err "Failed to install codium."
    exit 1
fi
