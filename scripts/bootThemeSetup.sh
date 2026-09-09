#!/usr/bin/env bash
# =======================================================
# bootThemeSetup.sh — the part before you reach Plasma
# -------------------------------------------------------
# catppuccinPlasma.sh handles everything *inside*
# the session. This handles the three things you see *before* that:
# the Plymouth splash while the kernel boots, the GRUB menu (if you
# ever see it), and the SDDM login screen. Right now all three are
# stock — this closes that seam, same idea as the XFCE sibling
# toolkit's own bootThemeSetup.sh (Plymouth/GRUB are DE-agnostic;
# only the login-manager step differs — SDDM here, not LightDM).
#
# This is more invasive than the rest of the toolkit — it edits
# /etc/default/grub, regenerates grub.cfg, and rebuilds the
# initramfs. Every edit is backed up first, and every step checks
# it actually applies to this machine (no GRUB? no SDDM? it says so
# and skips, instead of guessing).
# Privilege: sudo
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [ "$(id -u)" -eq 0 ]; then
    log_err "Run this as your normal user, not root."
    exit 1
fi
command_exists sudo || { log_err "sudo not found — this script needs it to touch system files."; exit 1; }

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Boot -> Login Theming (Catppuccin Mocha)${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update -qq

# ---------------------------------------------------------------------------
# 1. Plymouth boot splash
# ---------------------------------------------------------------------------
if ask "Install the Catppuccin Plymouth splash (shown while the kernel boots)?"; then
    sudo apt-get install -y plymouth plymouth-themes || log_warn "Plymouth package install had issues — continuing."

    if git clone --depth=1 https://github.com/catppuccin/plymouth.git "$WORK_DIR/plymouth" 2>/tmp/catppuccin-plymouth-clone.log; then
        if [ -d "$WORK_DIR/plymouth/themes/catppuccin-mocha" ]; then
            sudo mkdir -p /usr/share/plymouth/themes
            sudo cp -r "$WORK_DIR/plymouth/themes/catppuccin-mocha" /usr/share/plymouth/themes/
            log_ok "Theme files copied to /usr/share/plymouth/themes/catppuccin-mocha"

            APPLIED=0
            if command_exists plymouth-set-default-theme; then
                # -R also rebuilds the initramfs — one command does both.
                sudo plymouth-set-default-theme -R catppuccin-mocha 2>/tmp/plymouth-set-theme.log && APPLIED=1
            fi
            if [ "$APPLIED" -eq 0 ]; then
                log_info "plymouth-set-default-theme unavailable/failed — using update-alternatives instead."
                sudo update-alternatives --install /usr/share/plymouth/themes/default.plymouth \
                    default.plymouth /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth 200 \
                    && sudo update-alternatives --set default.plymouth \
                        /usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth \
                    && sudo update-initramfs -u \
                    && APPLIED=1
            fi

            if [ "$APPLIED" -eq 1 ]; then
                log_ok "Plymouth theme set to catppuccin-mocha."
                GRUB_DEFAULT="/etc/default/grub"
                if [ -f "$GRUB_DEFAULT" ]; then
                    sudo cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                    LINE=$(grep -m1 '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_DEFAULT" || true)
                    if [ -n "$LINE" ]; then
                        NEEDS_UPDATE=0
                        NEW_LINE="$LINE"
                        case "$NEW_LINE" in *splash*) ;; *) NEW_LINE="${NEW_LINE%\"} splash\""; NEEDS_UPDATE=1 ;; esac
                        case "$NEW_LINE" in *quiet*) ;; *) NEW_LINE="${NEW_LINE%\"} quiet\""; NEEDS_UPDATE=1 ;; esac
                        if [ "$NEEDS_UPDATE" -eq 1 ]; then
                            sudo sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|${NEW_LINE}|" "$GRUB_DEFAULT"
                            log_ok "Added splash/quiet to GRUB_CMDLINE_LINUX_DEFAULT (backup saved alongside it)."
                        fi
                    else
                        echo 'GRUB_CMDLINE_LINUX_DEFAULT="splash quiet"' | sudo tee -a "$GRUB_DEFAULT" > /dev/null
                        log_ok "Added GRUB_CMDLINE_LINUX_DEFAULT with splash/quiet."
                    fi
                    command_exists update-grub && { sudo update-grub || log_warn "update-grub failed — run it yourself once you've checked $GRUB_DEFAULT"; }
                else
                    log_warn "No /etc/default/grub found — if this system doesn't use GRUB, add 'splash quiet' to your bootloader's kernel cmdline manually."
                fi
                log_warn "You won't see this until your next real reboot — a logout doesn't touch it."
            else
                log_err "Couldn't apply the Plymouth theme. Log: /tmp/plymouth-set-theme.log"
            fi
        else
            log_err "Cloned catppuccin/plymouth but themes/catppuccin-mocha wasn't there — upstream layout may have changed."
        fi
    else
        log_err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-plymouth-clone.log"
    fi
else
    log_warn "Skipped Plymouth."
fi

# ---------------------------------------------------------------------------
# 2. GRUB menu theme
# ---------------------------------------------------------------------------
if ! command_exists update-grub && [ ! -d /boot/grub ]; then
    log_warn "This system doesn't appear to use GRUB — skipping (nothing to do, not an error)."
elif ask "Install the Catppuccin GRUB theme (only matters if you actually see the GRUB menu)?"; then
    if git clone --depth=1 https://github.com/catppuccin/grub.git "$WORK_DIR/grub" 2>/tmp/catppuccin-grub-clone.log; then
        THEME_TXT=$(find "$WORK_DIR/grub" -maxdepth 3 -iname "theme.txt" -ipath "*mocha*" | head -1)
        if [ -n "$THEME_TXT" ]; then
            THEME_DIR=$(dirname "$THEME_TXT")
            THEME_NAME=$(basename "$THEME_DIR")
            sudo mkdir -p /usr/share/grub/themes
            sudo cp -r "$THEME_DIR" "/usr/share/grub/themes/"
            log_ok "GRUB theme copied to /usr/share/grub/themes/$THEME_NAME"

            GRUB_DEFAULT="/etc/default/grub"
            if [ -f "$GRUB_DEFAULT" ]; then
                sudo cp "$GRUB_DEFAULT" "${GRUB_DEFAULT}.bak.$(date +%Y%m%d%H%M%S)"
                THEME_LINE="GRUB_THEME=\"/usr/share/grub/themes/${THEME_NAME}/theme.txt\""
                if grep -q '^GRUB_THEME=' "$GRUB_DEFAULT"; then
                    sudo sed -i "s|^GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                elif grep -q '^#GRUB_THEME=' "$GRUB_DEFAULT"; then
                    sudo sed -i "s|^#GRUB_THEME=.*|${THEME_LINE}|" "$GRUB_DEFAULT"
                else
                    echo "$THEME_LINE" | sudo tee -a "$GRUB_DEFAULT" > /dev/null
                fi
                sudo sed -i 's/^GRUB_TERMINAL_OUTPUT=console/#GRUB_TERMINAL_OUTPUT=console/' "$GRUB_DEFAULT"

                if command_exists update-grub; then
                    if sudo update-grub; then
                        log_ok "GRUB theme applied ($THEME_NAME). You'll see it next time GRUB's menu actually shows."
                    else
                        log_err "update-grub failed — check $GRUB_DEFAULT for typos before rebooting."
                    fi
                fi
            else
                log_warn "No /etc/default/grub found — theme files are in place but not wired up."
            fi
        else
            log_err "Cloned catppuccin/grub but couldn't find a Mocha theme.txt in it — upstream layout may have changed."
        fi
    else
        log_err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-grub-clone.log"
    fi
else
    log_warn "Skipped GRUB theme."
fi

# ---------------------------------------------------------------------------
# 3. SDDM login screen — catppuccin/sddm, official releases packaged as
#    <flavour>-<accent>.zip, extracting to /usr/share/sddm/themes/. Found
#    via the GitHub API (matching "mocha" + "red") rather than a hardcoded
#    URL, since exact asset naming has shifted across releases before.
# ---------------------------------------------------------------------------
if ! dpkg -l sddm 2>/dev/null | grep -q '^ii'; then
    log_warn "SDDM isn't installed — skipping (if you use a different display manager, this script doesn't know its theme format)."
elif ask "Install the Catppuccin SDDM theme (Mocha, Red)?"; then
    SDDM_URL=$(curl -fsSL https://api.github.com/repos/catppuccin/sddm/releases/latest \
        | grep -oP '"browser_download_url":\s*"\K[^"]*mocha[^"]*red[^"]*\.zip' | head -1)
    if [ -z "$SDDM_URL" ]; then
        log_warn "Couldn't find a Mocha+Red asset via the GitHub API — listing what IS available:"
        curl -fsSL https://api.github.com/repos/catppuccin/sddm/releases/latest \
            | grep -oP '"browser_download_url":\s*"\K[^"]+\.zip' | sed 's/^/    /'
        log_warn "Grab one of those manually and drop it in /usr/share/sddm/themes/ if you'd like a different accent."
    else
        SDDM_ZIP="$WORK_DIR/sddm-theme.zip"
        if curl -fsSL -o "$SDDM_ZIP" "$SDDM_URL"; then
            sudo mkdir -p /usr/share/sddm/themes
            TMP_EXTRACT="$WORK_DIR/sddm-extract"
            mkdir -p "$TMP_EXTRACT"
            if unzip -oq "$SDDM_ZIP" -d "$TMP_EXTRACT"; then
                SDDM_THEME_NAME=$(find "$TMP_EXTRACT" -maxdepth 2 -iname "theme.conf" -printf '%h\n' | head -1 | xargs -r basename)
                if [ -z "$SDDM_THEME_NAME" ]; then
                    # Single top-level dir with no nested theme.conf found this way — use the dir name itself.
                    SDDM_THEME_NAME=$(find "$TMP_EXTRACT" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | head -1)
                fi
                if [ -n "$SDDM_THEME_NAME" ]; then
                    sudo cp -r "$TMP_EXTRACT"/* /usr/share/sddm/themes/
                    sudo mkdir -p /etc/sddm.conf.d
                    printf '[Theme]\nCurrent=%s\n' "$SDDM_THEME_NAME" | sudo tee /etc/sddm.conf.d/catppuccin-theme.conf > /dev/null
                    log_ok "SDDM theme '$SDDM_THEME_NAME' installed and set active."
                    log_warn "Takes effect at next login/reboot — restarting SDDM now would end this session."
                else
                    log_err "Extracted the zip but couldn't determine the theme's folder name — check $TMP_EXTRACT by hand."
                fi
            else
                log_err "Couldn't unzip the SDDM theme archive."
            fi
        else
            log_err "SDDM theme download failed."
        fi
    fi
else
    log_warn "Skipped SDDM theme."
fi

echo
echo -e "${GREEN}Boot -> login theming pass complete.${NC}"
log_info "Reboot to see all three."
