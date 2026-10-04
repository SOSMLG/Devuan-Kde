#!/usr/bin/env bash
# DEVMKDE_DESC: Install the VSCodium editor
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: optional
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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

log_head "VSCodium"

require_not_root

if is_installed codium; then
    log_ok "VSCodium (codium) is already installed."
    exit 0
fi

for dep in wget gpg; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log_info "Installing dependency: $dep"
        apt_update -qq || true
        install_pkgs "$dep" "$dep" || { log_err "Failed to install $dep"; exit 1; }
    fi
done

KEYRING="/usr/share/keyrings/vscodium-archive-keyring.gpg"
SOURCES_FILE="/etc/apt/sources.list.d/vscodium.list"

if [ ! -f "$KEYRING" ]; then
    log_info "Adding VSCodium's GPG key..."
    if wget -qO - "https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg" \
            | gpg --dearmor | priv tee "$KEYRING" > /dev/null; then
        priv chmod 644 "$KEYRING"
        log_ok "Key installed to $KEYRING"
    else
        log_err "Failed to fetch/install the VSCodium GPG key."
        exit 1
    fi
else
    log_ok "VSCodium key already present at $KEYRING."
fi

log_info "Adding VSCodium APT repository..."
ARCH="$(dpkg --print-architecture)"
if echo "deb [arch=${ARCH} signed-by=${KEYRING}] https://download.vscodium.com/debs vscodium main" \
        | priv tee "$SOURCES_FILE" > /dev/null; then
    log_ok "Repository added at $SOURCES_FILE (scoped to arch=${ARCH})"
else
    log_err "Failed to write $SOURCES_FILE"
    exit 1
fi

log_info "Updating package lists..."
apt_update || { log_err "apt-get update failed after adding the VSCodium repo."; exit 1; }

log_info "Installing codium..."
if install_pkgs "VSCodium" codium; then
    log_ok "VSCodium installed. Launch it with 'codium'."
else
    log_err "Failed to install codium."
    exit 1
fi

log_info "Pointing text/plain files at VSCodium (so code/.txt open in the editor)..."
if ! run_as_user xdg-mime default codium.desktop text/plain; then
    log_warn "Could not set the text/plain default (xdg-mime unavailable). Set it in"
    log_warn "System Settings > File Associations > text/plain > Application Preference."
else
    log_ok "text/plain now opens in VSCodium by default."
fi
