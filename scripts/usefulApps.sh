#!/usr/bin/env bash
# =======================================================
# Useful apps to fill the gaps left by kdeDebloat.sh
# -------------------------------------------------------
# VLC replaces Elisa/JuK as the media player.
# The rest are small helper packages (archive formats,
# thumbnailers) that make Dolphin/Ark feel complete without
# pulling in a whole extra app suite.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Useful Apps${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

if ask "Install VLC (media player)?"; then
    install_pkgs "VLC" vlc

    # kdeDebloat.sh may have removed Dragon Player/Elisa earlier in this
    # toolkit's flow. If so, without this, common video/audio MIME types
    # can be left pointing at a now-uninstalled app instead of falling
    # over to VLC automatically.
    if is_installed vlc && command -v xdg-mime >/dev/null 2>&1; then
        log_info "Setting VLC as the default player for common video/audio types..."
        if xdg-mime default vlc.desktop \
            video/mp4 video/x-matroska video/webm video/x-msvideo video/quicktime video/mpeg \
            audio/mpeg audio/mp4 audio/flac audio/x-wav audio/ogg 2>/dev/null; then
            log_ok "VLC set as default for common video/audio types."
        else
            log_warn "Could not set MIME defaults (non-fatal — set manually via right-click > Open With if needed)."
        fi
    fi
fi

if ask "Install archive format support for Ark (7z, rar)?"; then
    if check_repo_package unrar "non-free"; then
        install_pkgs "Archive support" p7zip-full unrar
    else
        log_warn "unrar (non-free, creates RAR archives) not in your repos — using unrar-free (decompresses RAR only) instead."
        install_pkgs "Archive support" p7zip-full unrar-free
    fi
fi

if ask "Install Dolphin file/video thumbnailers (previews for media, docs, RAW photos)?"; then
    install_pkgs "Thumbnailers" ffmpegthumbs kdegraphics-thumbnailers kimageformat-plugins
fi

if ask "Install qBittorrent (torrent client)?" "N"; then
    install_pkgs "qBittorrent" qbittorrent
fi

if ask "Install TLP (laptop battery/power management)?" "N"; then
    # power-profiles-daemon and TLP both try to manage the same knobs
    # (CPU governor, PCIe ASPM, etc.) — running both fights itself and
    # is a well-known source of "my settings keep reverting" reports.
    if is_installed power-profiles-daemon; then
        log_info "power-profiles-daemon conflicts with TLP — removing it first."
        sudo systemctl disable --now power-profiles-daemon 2>/dev/null || true
        sudo apt-get purge -y power-profiles-daemon 2>/dev/null || log_warn "Couldn't remove power-profiles-daemon — TLP may fight it for control."
    fi

    install_pkgs "TLP" tlp tlp-rdw
    if is_installed tlp; then
        sudo systemctl enable --now tlp 2>/dev/null \
            || sudo service tlp start 2>/dev/null \
            || log_warn "Could not start tlp service automatically — check your init system (systemd vs sysvinit/openrc on Devuan)."
        log_ok "TLP installed and running. Check status any time with: sudo tlp-stat -s"

        # Charge thresholds only exist on hardware that exposes them
        # (ThinkPads via the in-kernel thinkpad_acpi driver, and some
        # others) — check rather than assume, and don't silently pick
        # a number for someone's battery.
        BAT_PATH=$(find /sys/class/power_supply -maxdepth 1 -iname 'BAT*' -print -quit 2>/dev/null)
        if [ -n "$BAT_PATH" ] && [ -f "${BAT_PATH}/charge_control_end_threshold" ]; then
            BAT_NAME=$(basename "$BAT_PATH")
            log_info "Charge-threshold support detected on ${BAT_NAME} (common on ThinkPads)."
            if ask "Cap charging at 80% to slow long-term battery wear (common ThinkPad recommendation)?" "N"; then
                sudo mkdir -p /etc/tlp.d
                sudo tee /etc/tlp.d/60-battery-threshold.conf > /dev/null << EOF
# Written by usefulApps.sh — charge threshold for ${BAT_NAME}.
# Full-charge fans of 100% can delete this file and run: sudo tlp start
START_CHARGE_THRESH_${BAT_NAME}=75
STOP_CHARGE_THRESH_${BAT_NAME}=80
EOF
                sudo tlp start >/dev/null 2>&1 || true
                log_ok "Charge capped at 80% (resumes below 75%). Edit /etc/tlp.d/60-battery-threshold.conf to change it."
            fi
        else
            log_info "No charge-threshold sysfs entry found on this machine — nothing to configure, not an error."
        fi
    fi
fi

echo -e "${GREEN}Useful apps step complete.${NC}"
