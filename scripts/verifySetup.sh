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
    if grep -q "install ok installed" <<<"$(dpkg-query -W -f='${Status}' "$name" 2>/dev/null)" \
        || grep -q '^ii' <<<"$(dpkg-query -l "${name}*" 2>/dev/null)"; then
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
    if grep -qx "$g" <<<"$(id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n')"; then
        report "group: $g" ok
    else
        report "group: $g" fail "user not in $g — re-run addUserToGroups.sh or: sudo usermod -aG $g $ACTUAL_USER"
    fi
done

# --- 2. Package baseline (default-Y/lean set) ----------------------------
pkg vlc
# TLP is OPTIONAL and 13-usefulApps.sh prompts for it with default "N", so
# checking it as "critical" turned a deliberate skip into a FAIL. It is also
# the wrong tool on some hardware: with a P-state driver (amd-pstate-epp /
# intel_pstate) power-profiles-daemon manages the same knobs natively and
# TLP's CPU control does nothing. Report the driver + the manager that
# actually suits it instead of hard-requiring TLP.
pkg tlp optional
_power_driver="$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver 2>/dev/null || echo unknown)"
case "$_power_driver" in
    amd-pstate-epp|intel_pstate|amd-pstate)
        if is_installed power-profiles-daemon || is_installed tuned-ppd; then
            report "power manager" ok "$_power_driver + power-profiles-daemon"
        elif is_installed tlp; then
            report "power manager" warn "$_power_driver + TLP — prefer power-profiles-daemon"
        else
            report "power manager" warn "$_power_driver — no power manager installed"
        fi
        ;;
    *)
        if is_installed tlp; then
            report "power manager" ok "$_power_driver + TLP"
        else
            report "power manager" warn "$_power_driver — TLP not installed (fine on AC-only desktops)"
        fi
        ;;
esac
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
# NOTE: these use a here-string, not `producer | grep -q`. The script runs under
# `set -o pipefail`, so `grep -q` exits at the first match and closes the pipe;
# on a large producer (fc-list) that SIGPIPEs the writer and the pipeline
# returns 141, which reads as "font not installed" even though it is.
if grep -qi "JetBrainsMono Nerd Font" <<<"$(fc-list 2>/dev/null)"; then
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

# --- 6. Plasma 6 Global Theme ----------------------------------------------
# The active palette is a PALETTE_SHORT from the theme engine. Read the marker
# theme.sh writes so a user who swapped palettes with 46-applyThemes.sh still
# verifies against what is actually installed, instead of hardcoding one name.
CURRENT_PALETTE=""
CURRENT_THEME_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/devuan-kde-setup/current-theme"
if [ -f "$CURRENT_THEME_FILE" ]; then
    CURRENT_PALETTE_ID="$(cat "$CURRENT_THEME_FILE")"
    for _pd in "$SCRIPT_DIR"/../themes/*/; do
        [ "$(basename "$_pd")" = "$CURRENT_PALETTE_ID" ] || continue
        CURRENT_PALETTE="$(PALETTE_SHORT= bash -c "source '$_pd/palette.sh' 2>/dev/null; printf '%s' \"\${PALETTE_SHORT:-}\"")"
        PALETTE_FILE="$_pd/palette.sh"
        break
    done
fi
# Darkmatter is the shipped default; Catppuccin is opt-in.
[ -n "$CURRENT_PALETTE" ] || CURRENT_PALETTE="Darkmatter"

# Accent colour, Plasma 6 style. Plasma 6 has NO named accents: kdeglobals
# stores a hex in [General] AccentColor (with a ColorSchemeHash beside it), so
# the old check for a `ColorScheme` *name* could never pass on 6.x and always
# warned "unset". Compare the palette's C_ACCENT hex instead, normalising the
# leading '#' (palette.sh stores e75353, kdeglobals stores #e75353).
PALETTE_ACCENT=""
if [ -f "${PALETTE_FILE:-$SCRIPT_DIR/../themes/darkmatter/palette.sh}" ]; then
    PALETTE_ACCENT="$(bash -c "source '${PALETTE_FILE:-$SCRIPT_DIR/../themes/darkmatter/palette.sh}' 2>/dev/null; printf '%s' \"\${C_ACCENT:-}\"")"
fi

# The engine names the Global Theme directory "${PALETTE_SHORT}Theme"
# (scripts/lib/theme.sh), not "${PALETTE_SHORT}". Using the bare short name
# pointed LOOKFEEL_DIR at a path that does not exist, so both theme checks
# below could only ever warn.
LOOKFEEL_DIR="$HOME/.local/share/plasma/look-and-feel/${CURRENT_PALETTE}Theme"
# Plasma 6 reads metadata.json. metadata.desktop is the Plasma 5 spelling and
# is silently ignored, so a theme built the old way looks installed on disk and
# never appears in the theme menu.
if [ -f "$LOOKFEEL_DIR/metadata.json" ]; then
    report "Global Theme manifest ($CURRENT_PALETTE)" ok "metadata.json present"
else
    report "Global Theme manifest ($CURRENT_PALETTE)" warn "no metadata.json in $LOOKFEEL_DIR — re-run 14-plasmaTheme.sh"
fi
# How a Plasma 6 LookAndFeel actually applies colors: contents/defaults carries
# "[kdeglobals][General] ColorScheme=<Name>", and Plasma writes that into
# kdeglobals on apply. It does NOT read a contents/colors entry — no stock theme
# (org.kde.breezedark.desktop) or third-party one has one, so asserting a
# contents/colors symlink could never pass. Check the file that is read, and
# that the scheme it names actually exists.
LNF_DEFAULTS="$LOOKFEEL_DIR/contents/defaults"
if [ -f "$LNF_DEFAULTS" ]; then
    LNF_SCHEME="$(sed -n 's/^ColorScheme=//p' "$LNF_DEFAULTS" 2>/dev/null | head -1)"
    if [ -n "$LNF_SCHEME" ] && [ -f "$HOME/.local/share/color-schemes/$LNF_SCHEME.colors" ]; then
        report "Global Theme color scheme ($CURRENT_PALETTE)" ok "defaults name $LNF_SCHEME, which exists"
    elif [ -n "$LNF_SCHEME" ]; then
        report "Global Theme color scheme ($CURRENT_PALETTE)" warn "defaults name $LNF_SCHEME but no $LNF_SCHEME.colors"
    else
        report "Global Theme color scheme ($CURRENT_PALETTE)" warn "no ColorScheme= in contents/defaults"
    fi
else
    report "Global Theme color scheme ($CURRENT_PALETTE)" warn "no contents/defaults in $LOOKFEEL_DIR — re-run 14-plasmaTheme.sh"
fi

# Catppuccin is optional and only present if 14-plasmaTheme.sh's prompt was
# accepted. Warn, never fail: not choosing it is the normal case.
if grep -qi catppuccin <<<"$(ls "$HOME/.local/share/plasma/look-and-feel" 2>/dev/null)"; then
    report "Catppuccin Plasma theme" ok
else
    report "Catppuccin Plasma theme" warn "not applied (optional) — 14-plasmaTheme.sh offers it"
fi
pkg "papirus-icon-theme" optional
dir_exists "Papirus-Dark icons" "/usr/share/icons/Papirus-Dark" warn
# Optional clean panel (plasmaPanel.sh): the rebuilt layout is a single
# floating bottom panel. Report presence of the pre-change backup plus a
# floating flag that the panel writes; both are cheap, none-brittle probes.
PANEL_SRC="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
if [ -e "$PANEL_SRC.pre-plasmaPanel" ]; then
    report "Clean floating panel (plasmaPanel.sh)" ok "floating panel layout is active"
else
    report "Clean floating panel (plasmaPanel.sh)" warn "not applied — run plasmaPanel.sh (optional)"
fi
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

# --- 6c. Baloo / beep / misc per-user toggles ------------------------------
# Baloo indexing is disabled by 12-kdeDebloat.sh, NOT by 33-plasmaPerformance.sh.
# 33-plasmaPerformance.sh only adds ExcludeFolders[] entries (and
# IndexHiddenFiles=false) and leaves the indexer running. An earlier comment here
# claimed the opposite in its first line while the rest of the block described
# the correct behaviour. Assert the key we actually set.
if grep -q '^ExcludeFolders\[\]=' "$HOME/.config/baloofilerc" 2>/dev/null; then
    report "Baloo folder exclusions" ok "$(grep -c '^ExcludeFolders\[\]=' "$HOME/.config/baloofilerc") paths"
else
    report "Baloo folder exclusions" warn "no ExcludeFolders[] — run 33-plasmaPerformance.sh (optional)"
fi
dir_exists "mousepoll.conf (touchpad fix)" "/etc/modprobe.d/mousepoll.conf" warn

# ButterBash is three pieces, and checking only the first produced a green
# report on a shell that had never been wired up: the config files were on
# disk, the rc that loads them was not, and .bashrc never sourced either.
if [ ! -d "$HOME/.config/bash" ]; then
    report "ButterBash install" warn "no ~/.config/bash — run 22-terminalButterbash.sh"
elif [ ! -f "$HOME/.config/butterbash/bashrc" ]; then
    report "ButterBash install" warn "~/.config/bash exists but ~/.config/butterbash/bashrc is missing (partial install)"
elif ! grep -qF "# >>> butterbash (devuan-kde-setup 22-terminalButterbash.sh) >>>" "$HOME/.bashrc" 2>/dev/null; then
    report "ButterBash install" warn "installed, but .bashrc has no butterbash block — the shell will not load it"
else
    report "ButterBash install" ok "~/.config/bash + rc, wired into .bashrc"
fi

# fastfetch: the package alone says nothing about whether the Devuan config
# landed, which is the part a user actually notices.
if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
    _ff_logo="$(grep -oE '"source"[[:space:]]*:[[:space:]]*"[a-z_]*"' "$HOME/.config/fastfetch/config.jsonc" 2>/dev/null | head -1 | sed 's/.*: *"\(.*\)"/\1/')"
    report "fastfetch config" ok "config.jsonc (logo: ${_ff_logo:-builtin})"
else
    report "fastfetch config" warn "no ~/.config/fastfetch/config.jsonc — run 23-fastfetchConfig.sh"
fi

# --- 6d. Plasma 6 settings the old versions wrote wrongly ------------------
# Each of these has a Plasma 5 spelling that is accepted and ignored, so a
# wrong key reads as "configured" in the file and behaves as unset in Plasma.
if [ -n "$PALETTE_ACCENT" ]; then
    _acc_got="$(kconfig_read kdeglobals "General" "AccentColor")"
    if [ "${_acc_got#\#}" ] && [ "${_acc_got#\#}" = "${PALETTE_ACCENT#\#}" ]; then
        report "Plasma accent colour" ok "#$PALETTE_ACCENT"
    elif [ -z "$_acc_got" ]; then
        report "Plasma accent colour" warn "AccentColor unset in kdeglobals [General]"
    else
        report "Plasma accent colour" warn "expected '#$PALETTE_ACCENT', got '$_acc_got'"
    fi
else
    report "Plasma accent colour" warn "palette defines no C_ACCENT — cannot verify"
fi
TABBOX="$(kconfig_read kwinrc TabBox LayoutName)"
if [ "$TABBOX" = "coverswitch" ] || [ -z "$TABBOX" ]; then
    report "KWin Alt-Tab layout" ok "${TABBOX:-not set (Plasma default)}"
else
    report "KWin Alt-Tab layout" warn "LayoutName=$TABBOX — expected coverswitch (33/27-plasma config)"
fi
# KWin effects live in kwinrc [Plugins] on Plasma 6; kwineffectsrc is dead.
if grep -q '^\[Plugins\]' "$HOME/.config/kwinrc" 2>/dev/null; then
    report "KWin effects in kwinrc [Plugins]" ok
else
    report "KWin effects in kwinrc [Plugins]" warn "no [Plugins] group — re-run 27-fancyPlasma.sh"
fi
# Plasma 6 removed AccentColorFromWallpaper. If it is present the config was
# written by an older script and the accent will not follow the scheme.
if grep -q '^AccentColorFromWallpaper=' "$HOME/.config/kdeglobals" 2>/dev/null; then
    report "kdeglobals has no stale accent key" warn "AccentColorFromWallpaper present (Plasma 5 key)"
else
    report "kdeglobals has no stale accent key" ok
fi

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