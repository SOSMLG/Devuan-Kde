#!/usr/bin/env bash
# =======================================================
# Bluetooth Setup
# -------------------------------------------------------
# hardwareSupport.sh already covers Bluetooth *firmware* (the blob that
# lets the adapter itself work at all). This covers the layer on top:
# the actual bluez stack, KDE's native Bluetooth applet, and — the part
# that trips people up most — getting audio (not just pairing) working
# for Bluetooth headsets/earbuds.
#
# No Blueman here: Bluedevil is KDE's own Bluetooth applet/KCM (System
# Settings > Bluetooth, plus a system tray icon) and does the same job
# Blueman does on GTK desktops. Installing Blueman alongside it would
# just be two competing tray icons/agents fighting over the same
# adapter.
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
echo -e "${CYAN} Bluetooth Setup${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. bluez — the actual Bluetooth stack (bluetoothd, hciconfig/bluetoothctl).
#    Without this, no firmware blob or applet matters — nothing's listening.
# ---------------------------------------------------------------------------
if ask "Install the Bluetooth stack (bluez)?"; then
    install_pkgs "bluez" bluez bluez-tools

    if is_installed bluez; then
        start_service bluetooth
        log_ok "bluetooth service started."

        if command_exists rfkill && rfkill list bluetooth 2>/dev/null | grep -qi "soft blocked: yes"; then
            sudo rfkill unblock bluetooth && log_ok "Bluetooth was rfkill-soft-blocked — unblocked it." \
                || log_warn "Couldn't rfkill unblock automatically — try 'sudo rfkill unblock bluetooth' yourself."
        fi
    fi
else
    log_warn "Skipped bluez."
fi

# ---------------------------------------------------------------------------
# 2. Bluedevil — KDE's own Bluetooth applet (System Settings + tray icon
#    + pairing wizard). Almost always already present on a standard Plasma
#    desktop install, but this is a safety net in case it isn't (e.g. a
#    trimmed-down/netinstall-based KDE spin).
# ---------------------------------------------------------------------------
if ask "Install/confirm Bluedevil (KDE's Bluetooth applet)?"; then
    install_pkgs "Bluedevil" bluedevil
fi

# ---------------------------------------------------------------------------
# 3. Audio bridging — the step that's actually missing most often. Pairing
#    can succeed while audio (A2DP profile — real stereo sound, not just
#    the phone-call-quality HSP/HFP fallback) silently doesn't work,
#    because the audio server doesn't have Bluetooth support wired in.
#    Detect which audio server owns this session rather than installing
#    both blindly (installing pulseaudio-module-bluetooth alongside a
#    PipeWire-managed session does nothing useful and can confuse
#    troubleshooting later).
# ---------------------------------------------------------------------------
if ask "Set up Bluetooth audio (A2DP stereo sound for headsets/earbuds)?"; then
    AUDIO_SERVER=""
    if command_exists pactl && pactl info 2>/dev/null | grep -qi "PipeWire"; then
        AUDIO_SERVER="pipewire"
    elif is_installed pipewire || is_installed pipewire-pulse; then
        AUDIO_SERVER="pipewire"
    elif command_exists pactl; then
        AUDIO_SERVER="pulseaudio"
    fi

    case "$AUDIO_SERVER" in
        pipewire)
            log_info "PipeWire detected — installing its Bluetooth + session-management pieces."
            install_pkgs "PipeWire Bluetooth support" pipewire-pulse wireplumber libspa-0.2-bluetooth
            ;;
        pulseaudio)
            log_info "PulseAudio detected — installing its Bluetooth module."
            install_pkgs "PulseAudio Bluetooth module" pulseaudio-module-bluetooth
            ;;
        *)
            log_warn "Couldn't confidently detect PipeWire vs PulseAudio — installing both Bluetooth"
            log_warn "add-ons. The one that doesn't apply to your setup is simply inert."
            install_pkgs "Bluetooth audio (both)" pulseaudio-module-bluetooth pipewire-pulse libspa-0.2-bluetooth
            ;;
    esac

    # Restart the user audio session so the newly installed module is
    # actually loaded without needing a full logout.
    if command_exists systemctl; then
        systemctl --user restart pipewire pipewire-pulse wireplumber 2>/dev/null \
            || systemctl --user restart pulseaudio 2>/dev/null \
            || true
    fi
    log_ok "Bluetooth audio support installed. Pair your headset/earbuds via System Settings >"
    log_ok "Bluetooth or the tray icon, then pick them under Audio Volume as the output device."
else
    log_warn "Skipped Bluetooth audio setup."
fi

echo -e "${GREEN}Bluetooth setup complete.${NC}"
log_warn "If a headset paired but shows no audio device, a logout/login (or 'systemctl --user"
log_warn "restart pipewire pipewire-pulse wireplumber') resolves it in almost every case."
