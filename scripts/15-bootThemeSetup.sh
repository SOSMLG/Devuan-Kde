#!/usr/bin/env bash
# DEVMKDE_DESC: Carry the theme to Plymouth (boot splash), GRUB, and the SDDM login screen
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# bootThemeSetup.sh -- the part before you reach Plasma
# -------------------------------------------------------
# 14-plasmaTheme.sh handles everything *inside* the session. This handles the
# three things you see *before* that: the Plymouth splash while the kernel
# boots, the GRUB menu (if you ever see it), and the SDDM login screen. All
# three get a locally generated Graphite Amber look: no upstream theme, no
# network fetch, and no third-party assets to verify.
#
# This is more invasive than the rest of the toolkit -- it edits
# /etc/default/grub, regenerates grub.cfg, and rebuilds the initramfs. Every
# edit is backed up first, and every step checks it actually applies to this
# machine (no GRUB? no SDDM? it says so and skips, instead of guessing).
# Privilege: priv() (sudo or doas).
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [ "$(id -u)" -eq 0 ]; then
    log_err "Run this as your normal user, not root."
    exit 1
fi
require_priv

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

THEME_ID="graphite-amber"
CANVAS="#16181D"
SURFACE="#202329"
LINE="#30343B"
AMBER="#E8A33D"
TEXT="#D8D3C8"

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Boot -> Login Theming (Graphite Amber)${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update -qq

# ---------------------------------------------------------------------------
# 1. Plymouth boot splash -- built from the text module, so no image assets
#    need to ship in this repo. The palette lives in the .plymouth file.
# ---------------------------------------------------------------------------
PLYMOUTH_DIR="/usr/share/plymouth/themes/$THEME_ID"
PLYMOUTH_FILE="$PLYMOUTH_DIR/$THEME_ID.plymouth"
if ask "Install the Graphite Amber Plymouth splash (shown while the kernel boots)?"; then
    install_pkgs "Plymouth" plymouth plymouth-themes || log_warn "Plymouth package install had issues -- continuing."

    priv mkdir -p "$PLYMOUTH_DIR"
    {
        printf '[Plymouth Theme]\n'
        printf 'Name=Graphite Amber\n'
        printf 'Description=Graphite surfaces with an amber accent\n'
        printf 'ModuleName=text\n'
        printf '\n'
        printf '[text]\n'
        printf 'ScreenBackgroundColor=0x16181D\n'
        printf 'TitleColor=0xE8A33D\n'
        printf 'MessageColor=0xD8D3C8\n'
        printf 'TitleFont=Sans:size=24\n'
        printf 'MessageFont=Sans:size=12\n'
    } | priv tee "$PLYMOUTH_FILE" > /dev/null
    log_ok "Plymouth theme written to $PLYMOUTH_FILE"

    APPLIED=0
    if command_exists plymouth-set-default-theme; then
        # -R also rebuilds the initramfs -- one command does both.
        priv plymouth-set-default-theme -R "$THEME_ID" 2>/tmp/plymouth-set-theme.log && APPLIED=1
    fi
    if [ "$APPLIED" -eq 0 ]; then
        log_info "plymouth-set-default-theme unavailable/failed -- using update-alternatives instead."
        priv update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
            default.plymouth "$PLYMOUTH_FILE" 200 \
            && priv update-alternatives --set default.plymouth "$PLYMOUTH_FILE" \
            && priv update-initramfs -u \
            && APPLIED=1
    fi

    if [ "$APPLIED" -eq 1 ]; then
        log_ok "Plymouth theme set to $THEME_ID."
        GRUB_DEFAULT="/etc/default/grub"
        if [ -f "$GRUB_DEFAULT" ]; then
            priv cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
            LINE=$(grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT" || true)
            if [ -n "$LINE" ]; then
                NEEDS_UPDATE=0
                NEW_LINE="$LINE"
                case "$NEW_LINE" in *splash*) ;; *) NEW_LINE="${NEW_LINE%\"} splash\""; NEEDS_UPDATE=1 ;; esac
                case "$NEW_LINE" in *quiet*) ;; *) NEW_LINE="${NEW_LINE%\"} quiet\""; NEEDS_UPDATE=1 ;; esac
                if [ "$NEEDS_UPDATE" -eq 1 ]; then
                    priv sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|${NEW_LINE}|" "$GRUB_DEFAULT"
                    log_ok "Added splash/quiet to GRUB_CMDLINE_LINUX_DEFAULT (backup saved alongside it)."
                fi
            else
                echo 'GRUB_CMDLINE_LINUX_DEFAULT="splash quiet"' | priv tee -a "$GRUB_DEFAULT" > /dev/null
                log_ok "Added GRUB_CMDLINE_LINUX_DEFAULT with splash/quiet."
            fi
            command_exists update-grub && { priv update-grub || log_warn "update-grub failed -- run it yourself once you've checked $GRUB_DEFAULT"; }
        else
            log_warn "No /etc/default/grub found -- if this system doesn't use GRUB, add 'splash quiet' to your bootloader's kernel cmdline manually."
        fi
        log_warn "You won't see this until your next real reboot -- a logout doesn't touch it."
    else
        log_err "Couldn't apply the Plymouth theme. Log: /tmp/plymouth-set-theme.log"
    fi
else
    log_warn "Skipped Plymouth."
fi

# ---------------------------------------------------------------------------
# 2. GRUB menu theme -- a plain theme.txt in exact palette hexes, no archive
#    to download and no upstream asset layout to guess at.
# ---------------------------------------------------------------------------
if ! command_exists update-grub && [ ! -d /boot/grub ]; then
    log_warn "This system doesn't appear to use GRUB -- skipping (nothing to do, not an error)."
elif ask "Install the Graphite Amber GRUB theme (only matters if you actually see the GRUB menu)?"; then
    GRUB_THEME_DIR="/usr/share/grub/themes/$THEME_ID"
    priv mkdir -p "$GRUB_THEME_DIR"
    {
        printf 'title-text: "Graphite Amber"\n'
        printf 'title-font: "DejaVu Sans Bold 24"\n'
        printf 'desktop-color: "%s"\n' "$CANVAS"
        printf '+ boot_menu {\n'
        printf '  left = 10%%\n'
        printf '  top = 25%%\n'
        printf '  width = 80%%\n'
        printf '  height = 50%%\n'
        printf '  item_font = "DejaVu Sans 16"\n'
        printf '  item_color = "%s"\n' "$TEXT"
        printf '  selected_item_color = "%s"\n' "$AMBER"
        printf '  item_height = 32\n'
        printf '  item_padding = 8\n'
        printf '  item_spacing = 6\n'
        printf '}\n'
    } | priv tee "$GRUB_THEME_DIR/theme.txt" > /dev/null
    log_ok "GRUB theme written to $GRUB_THEME_DIR/theme.txt"

    GRUB_DEFAULT="/etc/default/grub"
    if [ -f "$GRUB_DEFAULT" ]; then
        priv cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
        GRUB_THEME_LINE="GRUB_THEME=\"$GRUB_THEME_DIR/theme.txt\""
        if grep -q '^GRUB_THEME=' "$GRUB_DEFAULT"; then
            priv sed -i "s|^GRUB_THEME=.*|${GRUB_THEME_LINE}|" "$GRUB_DEFAULT"
        elif grep -q '^#GRUB_THEME=' "$GRUB_DEFAULT"; then
            priv sed -i "s|^#GRUB_THEME=.*|${GRUB_THEME_LINE}|" "$GRUB_DEFAULT"
        else
            echo "$GRUB_THEME_LINE" | priv tee -a "$GRUB_DEFAULT" > /dev/null
        fi
        priv sed -i 's/^GRUB_TERMINAL_OUTPUT=console/#GRUB_TERMINAL_OUTPUT=console/' "$GRUB_DEFAULT"
        for COLOR_LINE in 'GRUB_COLOR_NORMAL="light-gray/black"' 'GRUB_COLOR_HIGHLIGHT="yellow/black"'; do
            COLOR_KEY="${COLOR_LINE%%=*}"
            if grep -q "^${COLOR_KEY}=" "$GRUB_DEFAULT"; then
                priv sed -i "s|^${COLOR_KEY}=.*|${COLOR_LINE}|" "$GRUB_DEFAULT"
            else
                echo "$COLOR_LINE" | priv tee -a "$GRUB_DEFAULT" > /dev/null
            fi
        done

        if command_exists update-grub; then
            if priv update-grub; then
                log_ok "GRUB theme applied ($THEME_ID). You'll see it next time GRUB's menu actually shows."
            else
                log_err "update-grub failed -- check $GRUB_DEFAULT for typos before rebooting."
            fi
        fi
    else
        log_warn "No /etc/default/grub found -- theme files are in place but not wired up."
    fi
else
    log_warn "Skipped GRUB theme."
fi

# ---------------------------------------------------------------------------
# 3. SDDM login screen -- use a shipped dark theme as the QML base, copy it
#    under our own name, and replace its background with a local graphite /
#    amber image when ImageMagick is available. No theme archive is fetched.
# ---------------------------------------------------------------------------
if ! dpkg -l sddm 2>/dev/null | grep -q '^ii'; then
    log_warn "SDDM isn't installed -- skipping (if you use a different display manager, this script doesn't know its theme format)."
elif ask "Install the Graphite Amber SDDM theme (built-in dark base, local palette)?"; then
    THEME_SRC=""
    for CAND in /usr/share/sddm/themes/elarun /usr/share/sddm/themes/maldives /usr/share/sddm/themes/maya; do
        if [ -f "$CAND/theme.conf" ] || [ -f "$CAND/metadata.desktop" ]; then
            THEME_SRC="$CAND"
            break
        fi
    done
    if [ -z "$THEME_SRC" ]; then
        log_warn "No shipped SDDM theme found to use as a base -- skipping."
    else
        THEME_DEST="/usr/share/sddm/themes/$THEME_ID"
        priv rm -rf "$THEME_DEST"
        priv mkdir -p "$THEME_DEST"
        priv cp -r "$THEME_SRC/." "$THEME_DEST/"
        [ -f "$THEME_DEST/metadata.desktop" ] && \
            priv sed -i 's/^Name=.*/Name=Graphite Amber/' "$THEME_DEST/metadata.desktop" 2>/dev/null || true

        BG_FILE=$(find "$THEME_DEST" -maxdepth 3 -type f \( -name '*.png' -o -name '*.jpg' \) 2>/dev/null | head -1)
        if [ -n "$BG_FILE" ] && command_exists convert; then
            if convert -size 1920x1080 "gradient:${CANVAS}-${SURFACE}" \
                \( -size 1920x1080 xc:none -fill "$AMBER" -draw "circle 1500,700 1820,700" -blur 0x180 \) \
                -compose over -composite "$WORK_DIR/sddm-bg.png" && \
                priv cp "$WORK_DIR/sddm-bg.png" "$BG_FILE"; then
                log_ok "SDDM background rendered in graphite and amber."
            else
                log_warn "Background render failed -- the shipped base image stays in place."
            fi
        else
            log_warn "No writable background image or no ImageMagick -- the shipped dark base image stays in place."
        fi

        priv mkdir -p /etc/sddm.conf.d
        printf '[Theme]\nCurrent=%s\n' "$THEME_ID" | priv tee /etc/sddm.conf.d/graphite-amber-theme.conf > /dev/null
        log_ok "SDDM theme '$THEME_ID' installed and set active."
        log_warn "Takes effect at next login/reboot -- restarting SDDM now would end this session."
    fi
else
    log_warn "Skipped SDDM theme."
fi

echo
echo -e "${GREEN}Boot -> login theming pass complete.${NC}"
log_info "Reboot to see all three."
