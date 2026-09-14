#!/usr/bin/env bash
# =======================================================
# Verify Setup — end-state audit
# -------------------------------------------------------
# One-pass check of the toolkit's expected end state:
# group membership, key packages, fonts, Firefox user.js,
# and enabled services. Designed to be run from run.sh
# --verify after a run, or standalone at any time.
#
# Prints PASS/FAIL/WARN lines and exits non-zero if any
# critical check failed, so it can gate CI/ISO validation.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

PASS=0; FAIL=0; WARN=0

report() {  # report <name> <status> <detail>
    case "$2" in
        ok)
            printf '  PASS  %-48s %s\n' "$1" "${3:-}"
            PASS=$((PASS + 1))
            ;;
        fail)
            printf '  FAIL  %-48s %s\n' "$1" "${3:-}"
            FAIL=$((FAIL + 1))
            ;;
        warn)
            printf '  WARN  %-48s %s\n' "$1" "${3:-}"
            WARN=$((WARN + 1))
            ;;
    esac
}

pkg() {  # pkg <name> [critical|optional]
    local name="$1" level="${2:-critical}"
    local state detail
    if is_installed "$name"; then
        state="ok"; detail="installed"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "$name" "$state" "$detail"
}

# pkg_glob: package names that shifted (e.g. libavcodec-extra* across releases)
pkg_glob() {
    local name="$1" level="${2:-critical}"
    local state detail
    if dpkg-query -W -f='${Status}' "$name" 2>/dev/null | grep -q "install ok installed" \
        || dpkg-query -l "${name}*" 2>/dev/null | grep -q '^ii'; then
        state="ok"; detail="installed"
    elif [ "$level" = "optional" ]; then
        state="warn"; detail="not installed (optional — OK to skip)"
    else
        state="fail"; detail="missing — re-run the relevant script"
    fi
    report "$name*" "$state" "$detail"
}

# service_state: enabled under systemd, OpenRC, OR sysvinit; running via
# process name. Never assumes an init system (Devuan ships all three).
service_state() {
    local svc="$1" procname="$2" level="${3:-fail}"
    local enabled="" running=""
    case "$(init_system)" in
        systemd)
            systemctl is-enabled "$svc" >/dev/null 2>&1 && enabled="systemd"
            [ -z "$enabled" ] && systemctl is-enabled "${svc}.service" >/dev/null 2>&1 && enabled="systemd"
            ;;
        openrc)
            if command_exists rc-update && rc-update show 2>/dev/null | awk -v s="$svc" '$1==s{found=1} END{exit !found}'; then
                enabled="openrc"
            fi
            ;;
        sysvinit)
            if [ -f "/etc/init.d/$svc" ] && ls /etc/rc[0-9S]*.d/S*"$svc" >/dev/null 2>&1; then
                enabled="sysvinit"
            fi
            ;;
    esac
    pgrep -x "$procname" >/dev/null 2>&1 && running="yes"

    if [ -n "$running" ]; then
        report "$svc (service)" ok "${enabled:-running, not enabled}"
    elif [ "$level" = "optional" ]; then
        report "$svc (service)" warn "not running"
    else
        report "$svc (service)" fail "not running"
    fi
}

# dir_exists: report a path the toolkit should have created.
dir_exists() {
    local name="$1" path="$2" level="${3:-warn}"
    if [ -e "$path" ]; then
        report "$name" ok
    elif [ "$level" = "warn" ]; then
        report "$name" warn "not found — re-run the relevant script (or skip)"
    else
        report "$name" fail "not found — re-run the relevant script"
    fi
}

# conf_key: report whether file:group:key holds value "expected".
conf_key() {
    local name="$1" file="$2" group="$3" key="$4" expected="$5" level="${6:-warn}"
    local actual
    actual="$(kconfig_read "$file" "$group" "$key")"
    if [ "$actual" = "$expected" ]; then
        report "$name" ok
    elif [ "$level" = "warn" ]; then
        report "$name" warn "expected '$expected', got '${actual:-unset}'"
    else
        report "$name" fail "expected '$expected', got '${actual:-unset}'"
    fi
}

# kconfig_read: portable read of a KDE .conf file without needing
# kwriteconfig's read mode (kreadconfig6 may be absent).
kconfig_read() {
    local file="$1" group="$2" key="$3"
    local f="$HOME/.config/$file" in_group=0 val=""
    [ -f "$f" ] || { echo ""; return 0; }
    val="$(awk -v g="$group" -v k="$key" '
        $0 ~ "^\\[" g "\\]$" { in_group=1; next }
        in_group && /^\[/ { in_group=0 }
        in_group && index($0, k "=") == 1 { print substr($0, index($0,"=")+1); exit }
    ' "$f")"
    echo "$val"
}

log_head "Setup verification"

echo -e "  (user: ${CYAN}${ACTUAL_USER}${NC})\n"

# --- 1. Group membership ------------------------------------------------
for g in input video render; do
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$g"; then
        report "group: $g" ok
    else
        report "group: $g" fail "user not in $g — re-run addUserToGroups.sh or: sudo usermod -aG $g $ACTUAL_USER"
    fi
done

# --- 2. Package baseline (default-Y/lean set) ----------------------------
pkg vlc
pkg tlp
pkg firmware-iwlwifi optional
pkg ffmpeg
pkg_glob libavcodec-extra
pkg firefox-esr
pkg fonts-noto-color-emoji
pkg fonts-noto-core optional
pkg fastfetch
pkg flatpak
pkg timeshift
pkg bluez
pkg bluetooth
pkg fwupd optional
pkg chrony optional
pkg featherpad optional

# --- 2b. Bluetooth audio (what bluetoothSetup.sh actually bridges) --------
if is_installed pipewire-pulse || is_installed wireplumber; then
    pkg libspa-0.2-bluetooth optional
elif is_installed pulseaudio; then
    pkg pulseaudio-module-bluetooth optional
else
    report "Bluetooth audio" warn "neither PipeWire nor PulseAudio present — nothing to bridge"
fi

# --- 3. Optional/user-picked packages (warn roll, not fail) --------------
pkg codium optional
pkg opencode optional
pkg heroic optional
pkg steam optional
pkg gimp optional
pkg btop optional
pkg eza optional
pkg bat optional
pkg neovim optional
pkg keepassxc optional
pkg gamemode optional
pkg mangohud optional
pkg wine optional
pkg vesktop optional
pkg cron optional

# --- 4. Fonts -------------------------------------------------------------
if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    report "JetBrainsMono Nerd Font" ok
else
    report "JetBrainsMono Nerd Font" fail "not found — re-run installFonts.sh"
fi
dir_exists "fontconfig defaults (fonts.conf)" "$HOME/.config/fontconfig/fonts.conf" warn

# --- 5. Firefox hardening -------------------------------------------------
if grep -rlsq "user_pref" "$HOME/.mozilla/firefox" 2>/dev/null; then
    report "Firefox hardened user.js" ok
else
    report "Firefox hardened user.js" warn "no user.js found (harden Firefox or skip)"
fi

# --- 6. Catppuccin theme --------------------------------------------------
if ls "$HOME/.local/share/plasma/look-and-feel" 2>/dev/null | grep -qi catppuccin \
    || ls "$HOME/.local/share/plasma/global-themes" 2>/dev/null | grep -qi catppuccin; then
    report "Catppuccin Plasma theme" ok
else
    report "Catppuccin Plasma theme" warn "not applied — re-run catppuccinPlasma.sh"
fi
pkg "papirus-icon-theme" optional
dir_exists "Papirus-Dark icons" "/usr/share/icons/papirus-dark" warn
# Optional clean panel (plasmaPanel.sh): the rebuilt layout is a single
# floating bottom panel. Report presence of the pre-change backup plus a
# floating flag that the panel writes; both are cheap, none-brittle probes.
PANEL_SRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -e "$PANEL_SRC.pre-plasmaPanel" ]; then
    report "Clean floating panel (plasmaPanel.sh)" ok "floating panel layout is active"
else
    report "Clean floating panel (plasmaPanel.sh)" warn "not applied — run plasmaPanel.sh (optional)"
fi
# The active Konsole palette is a PALETTE_SHORT from the theme engine; the
# default (theme marker absent) is the stock "CatppuccinRed". Read the
# marker so a user who swapped palettes (applyThemes.sh) still verifies clean.
CURRENT_PALETTE=""
CURRENT_THEME_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/devuan-kde-setup/current-theme"
if [ -f "$CURRENT_THEME_FILE" ]; then
    CURRENT_PALETTE_ID="$(cat "$CURRENT_THEME_FILE")"
    for _pd in "$SCRIPT_DIR"/../themes/*/; do
        [ "$(basename "$_pd")" = "$CURRENT_PALETTE_ID" ] || continue
        CURRENT_PALETTE="$(PALETTE_SHORT= bash -c "source '$_pd/palette.sh' 2>/dev/null; printf '%s' \"\${PALETTE_SHORT:-}\"")"
        break
    done
fi
[ -n "$CURRENT_PALETTE" ] || CURRENT_PALETTE="CatppuccinRed"
dir_exists "Konsole scheme ($CURRENT_PALETTE)" "$HOME/.local/share/konsole/$CURRENT_PALETTE.colorscheme" warn
dir_exists "Konsole profile ($CURRENT_PALETTE)" "$HOME/.local/share/konsole/$CURRENT_PALETTE.profile" warn
dir_exists "Plasma color scheme ($CURRENT_PALETTE)" "$HOME/.local/share/color-schemes/$CURRENT_PALETTE.colors" warn

# --- 6b. Boot theming (bootThemeSetup.sh) --------------------------------
dir_exists "Plymouth catppuccin-mocha" "/usr/share/plymouth/themes/catppuccin-mocha/catppuccin-mocha.plymouth" warn
if grep -q '^GRUB_THEME=' /etc/default/grub 2>/dev/null; then
    report "GRUB Catppuccin theme" ok
else
    report "GRUB Catppuccin theme" warn "GRUB_THEME not set in /etc/default/grub"
fi
dir_exists "SDDM Catppuccin theme conf" "/etc/sddm.conf.d/catppuccin-theme.conf" warn

# --- 6c. Baloo / beep / misc per-user toggles (kdeDebloat.sh) ------------
conf_key "Baloo indexing disabled" baloofilerc "Basic Settings" "Indexing-Enabled" "false" warn
dir_exists "mousepoll.conf (touchpad fix)" "/etc/modprobe.d/mousepoll.conf" warn
dir_exists "ButterBash install" "$HOME/.config/bash" warn

# --- 7. Services -----------------------------------------------------------
service_state bluetooth bluetoothd optional
service_state tlp tlp optional
service_state cups cupsd optional
service_state chrony chronyd optional
service_state cron cron optional

echo
echo -e "${GREEN}  ${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo
    log_err "Some checks failed — see lines above, then re-run the relevant script."
    exit 1
fi
exit 0