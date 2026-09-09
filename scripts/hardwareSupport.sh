#!/usr/bin/env bash
# =======================================================
# Hardware Support — firmware, microcode, firmware updates
# -------------------------------------------------------
# Covers the "why doesn't my WiFi/Bluetooth work out of the
# box" class of issues, which is almost always a missing
# non-free firmware blob rather than a real driver problem.
# Also installs CPU microcode (auto-detected Intel vs AMD)
# and fwupd for BIOS/UEFI + peripheral firmware updates via
# LVFS, surfaced through Discover so it's not a separate app.
#
# All of this is inert on hardware it doesn't apply to —
# firmware blobs sit unused in /lib/firmware until matching
# hardware is present, so installing the common set doesn't
# conflict with staying minimal.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [ "$(id -u)" -eq 0 ]; then
    log_err "Do not run this as root."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Hardware Support${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Common WiFi/Bluetooth firmware
# ---------------------------------------------------------------------------
if ask "Install common WiFi/Bluetooth firmware (Intel/Realtek/Atheros/Broadcom)?"; then
    if check_repo_package firmware-iwlwifi "non-free-firmware"; then
        install_pkgs "WiFi/Bluetooth firmware" \
            firmware-iwlwifi firmware-realtek firmware-atheros \
            firmware-brcm80211 firmware-misc-nonfree firmware-linux
    else
        log_warn "Skipping WiFi/Bluetooth firmware — non-free-firmware repo component is missing."
    fi
fi

# ---------------------------------------------------------------------------
# 2. CPU microcode — auto-detected, never both
# ---------------------------------------------------------------------------
if ask "Install CPU microcode updates (auto-detects Intel/AMD)?"; then
    VENDOR="$(grep -m1 -oE 'GenuineIntel|AuthenticAMD' /proc/cpuinfo || true)"
    case "$VENDOR" in
        GenuineIntel)
            log_info "Detected Intel CPU."
            if check_repo_package intel-microcode "non-free-firmware"; then
                install_pkgs "Intel microcode" intel-microcode
            fi
            ;;
        AuthenticAMD)
            log_info "Detected AMD CPU."
            if check_repo_package amd64-microcode "non-free-firmware"; then
                install_pkgs "AMD microcode" amd64-microcode
            fi
            ;;
        *)
            log_warn "Could not detect CPU vendor from /proc/cpuinfo, skipping microcode."
            ;;
    esac
fi

# ---------------------------------------------------------------------------
# 3. fwupd — BIOS/UEFI + peripheral firmware updates via LVFS,
#    surfaced in Discover instead of a separate tool.
# ---------------------------------------------------------------------------
if ask "Install fwupd (firmware updates via Discover, like Mint's Driver Manager)?"; then
    install_pkgs "fwupd" fwupd plasma-discover-backend-fwupd

    if is_installed fwupd; then
        if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
            sudo systemctl enable --now fwupd >/dev/null 2>&1 || true
        else
            sudo service fwupd start >/dev/null 2>&1 || true
        fi
        log_ok "fwupd installed. Check for firmware updates any time in Discover, or run: fwupdmgr get-updates"
    fi
fi

echo -e "${GREEN}Hardware support step complete.${NC}"
log_warn "A reboot is recommended so newly installed firmware/microcode is loaded."
