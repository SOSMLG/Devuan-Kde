#!/usr/bin/env bash
# =======================================================
# Touchpad / Trackpoint fix
# -------------------------------------------------------
# Core fix (from touchpadfix): raise the USB HID mouse
# polling rate. This is the classic fix for laggy/jumpy
# USB-attached trackpoints & touchpads (many ThinkPads and
# some laptop internal pads ride on usbhid).
#   /etc/modprobe.d/mousepoll.conf
#     options usbhid mousepoll=2
#
# Optional extra: sane libinput defaults (tap-to-click,
# no accidental palm clicks, disable natural scroll) via
# an Xorg conf snippet. Only applied if you say yes — KDE's
# own Touchpad KCM will still override anything you change
# there in System Settings afterward.
# =======================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Touchpad / Trackpoint Fix${NC}"
echo -e "${CYAN}=========================================================${NC}"

# ---------------------------------------------------------------------------
# 1. USB HID mouse polling rate fix
# ---------------------------------------------------------------------------
MODPROBE_FILE="/etc/modprobe.d/mousepoll.conf"

if [ -f "$MODPROBE_FILE" ] && grep -q "mousepoll=2" "$MODPROBE_FILE" 2>/dev/null; then
    log_ok "$MODPROBE_FILE already sets mousepoll=2, skipping."
else
    if [ -f "$MODPROBE_FILE" ]; then
        BACKUP="${MODPROBE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$MODPROBE_FILE" "$BACKUP"
        log_info "Existing $MODPROBE_FILE backed up to $BACKUP"
    fi

    if echo "options usbhid mousepoll=2" | sudo tee "$MODPROBE_FILE" > /dev/null; then
        log_ok "Wrote $MODPROBE_FILE (options usbhid mousepoll=2)"
    else
        log_err "Failed to write $MODPROBE_FILE"
        exit 1
    fi

    # Rebuild initramfs so the option is picked up on next boot too.
    if command -v update-initramfs >/dev/null 2>&1; then
        log_info "Updating initramfs..."
        sudo update-initramfs -u || log_warn "update-initramfs failed (non-fatal, the modprobe.d file is still applied on next module load)."
    fi

    # Try to apply immediately without a reboot, if usbhid can be reloaded.
    if command -v modprobe >/dev/null 2>&1; then
        log_info "Attempting to reload the usbhid module now (may briefly disconnect USB input devices)..."
        if sudo modprobe -r usbhid 2>/dev/null && sudo modprobe usbhid 2>/dev/null; then
            log_ok "usbhid reloaded, fix is active immediately."
        else
            log_warn "Could not hot-reload usbhid (likely still in use). A reboot will apply it."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 2. Optional libinput tuning (tap-to-click, disable natural scroll, etc.)
# ---------------------------------------------------------------------------
if ask "Also apply sane libinput defaults (tap-to-click on, natural scroll off)?" "N"; then
    XORG_CONF_DIR="/etc/X11/xorg.conf.d"
    XORG_CONF_FILE="$XORG_CONF_DIR/30-touchpad.conf"

    sudo mkdir -p "$XORG_CONF_DIR"

    if [ -f "$XORG_CONF_FILE" ]; then
        BACKUP="${XORG_CONF_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$XORG_CONF_FILE" "$BACKUP"
        log_info "Existing $XORG_CONF_FILE backed up to $BACKUP"
    fi

    sudo tee "$XORG_CONF_FILE" > /dev/null << 'EOF'
Section "InputClass"
    Identifier "libinput touchpad defaults"
    MatchIsTouchpad "on"
    Driver "libinput"
    Option "Tapping" "on"
    Option "TappingButtonMap" "lrm"
    Option "NaturalScrolling" "false"
    Option "DisableWhileTyping" "true"
    Option "ClickMethod" "clickfinger"
EndSection

Section "InputClass"
    Identifier "libinput pointstick defaults"
    MatchIsPointer "on"
    MatchProduct "TrackPoint|trackpoint|Trackpoint|DualPoint Stick"
    Driver "libinput"
    Option "AccelSpeed" "0.3"
EndSection
EOF

    if [ -f "$XORG_CONF_FILE" ]; then
        log_ok "Wrote $XORG_CONF_FILE"
        log_warn "Note: this file only applies under Xorg. If you're on Wayland, use KDE's own Touchpad settings in System Settings > Input Devices instead — libinput options there apply directly."
    else
        log_err "Failed to write $XORG_CONF_FILE"
    fi
fi

echo -e "${GREEN}Touchpad/trackpoint fix complete.${NC}"
log_warn "A reboot is recommended to guarantee the mousepoll fix is fully applied."
