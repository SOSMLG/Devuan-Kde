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

# service_state: enabled under systemd OR OpenRC; running via process name.
service_state() {
    local svc="$1" procname="$2" level="${3:-fail}"
    local enabled="" running=""
    if systemctl is-enabled "$svc" >/dev/null 2>&1 || systemctl is-enabled "${svc}.service" >/dev/null 2>&1; then
        enabled="systemd"
    elif command_exists rc-update && rc-update show 2>/dev/null | awk -v s="$svc" '$1==s{found=1} END{exit !found}'; then
        enabled="openrc"
    fi
    pgrep -x "$procname" >/dev/null 2>&1 && running="yes"
    [ -z "$enabled" ] && [ -z "$running" ] && { pgrep -x "$procname" >/dev/null 2>&1 && running="yes"; }

    if [ -n "$running" ]; then
        report "$svc (service)" ok "${enabled:-running, not enabled}"
    elif [ "$level" = "optional" ]; then
        report "$svc (service)" warn "not running"
    else
        report "$svc (service)" fail "not running"
    fi
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

# --- 4. Fonts -------------------------------------------------------------
if fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font"; then
    report "JetBrainsMono Nerd Font" ok
else
    report "JetBrainsMono Nerd Font" fail "not found — re-run installFonts.sh"
fi

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

# --- 7. Services -----------------------------------------------------------
service_state bluetooth bluetoothd optional
service_state tlp tlp optional
service_state cups cupsd optional
service_state chrony chronyd optional

echo
echo -e "${GREEN}  ${PASS} passed${NC}, ${RED}${FAIL} failed${NC}, ${YELLOW}${WARN} warnings${NC}"
if [ "$FAIL" -gt 0 ]; then
    echo
    log_err "Some checks failed — see lines above, then re-run the relevant script."
    exit 1
fi
exit 0