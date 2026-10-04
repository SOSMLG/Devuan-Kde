#!/usr/bin/env bash
# =======================================================
# common.sh — shared helpers, sourced by every toolkit script
# -------------------------------------------------------
# Every script in this toolkit sources this file for the shared helpers
# (colors, logging, is_installed, ask, install_pkgs, service management,
# download verification). Each script remains independently runnable —
# `bash scripts/<name>.sh` works fine because lib/ ships with the repo.
#
# Environment variables honored (all optional):
#   DEVMKDE_ASSUME_YES=1    ask() answers with its default instead of prompting
#   DEVMKDE_SKIP_APT_UPDATE=1  apt_update() is a no-op (run.sh updates once)
#   DEVMKDE_ISO_BUILD=1     require_not_root()/require_priv() pass (ISO chroot)
#   DEVMKDE_PRIV=sudo|doas  force the escalation helper instead of auto-detect
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVUAN_KDE_COMMON_SH_LOADED:-}" ] && return 0
_DEVUAN_KDE_COMMON_SH_LOADED=1

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; BLUE="\033[1;34m"; CYAN="\033[0;36m"; NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

log_head() {
    echo -e "${CYAN}=========================================================${NC}"
    echo -e "${CYAN} $1${NC}"
    echo -e "${CYAN}=========================================================${NC}"
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Session detection (Wayland/X11) -----------------------------------------
# Detect current desktop session type for agnostic behavior across Wayland/X11.
detect_session() {
    local stype="${XDG_SESSION_TYPE:-}"
    if [ -z "$stype" ] && [ -n "${WAYLAND_DISPLAY:-}" ]; then
        stype="wayland"
    fi
    if [ -z "$stype" ] && [ -n "${DISPLAY:-}" ]; then
        stype="x11"
    fi
    [ -n "$stype" ] && echo "${stype,,}" || echo "unknown"
}

# Cached session type for this shell
DEVMKDE_SESSION="$(detect_session)"
export DEVMKDE_SESSION

# --- Privilege escalation ---------------------------------------------------
# Every privileged call in this toolkit goes through priv() so a box without
# sudo isn't a dead end, and so the escalation mechanism can be swapped without
# touching 30 scripts. Detection order:
#
#   1. DEVMKDE_PRIV=sudo|doas  explicit override, always wins
#   2. sudo, if present        sudo-first: the overwhelmingly common case on
#                              Debian/Devuan, and it keeps existing muscle
#                              memory and sudoers config working
#   3. doas, if present        fallback for minimal / Doas-first installs
#   4. neither                 hard error naming what's missing, so the failure
#                              is actionable instead of "command not found"
#
# Resolved once, lazily, on first use and then cached -- scripts call priv() in
# loops and a command -v per call is wasted work.
PRIV_BIN=""
_priv_resolve() {
    [ -n "$PRIV_BIN" ] && return 0
    local want="${DEVMKDE_PRIV:-}"
    if [ -n "$want" ]; then
        if command_exists "$want"; then
            PRIV_BIN="$want"
            return 0
        fi
        log_err "DEVMKDE_PRIV=$want was requested but '$want' isn't installed."
        PRIV_BIN="__missing__"
        return 1
    fi
    if command_exists sudo; then
        PRIV_BIN="sudo"
    elif command_exists doas; then
        PRIV_BIN="doas"
    else
        PRIV_BIN="__missing__"
        return 1
    fi
    return 0
}

# priv <cmd> [args...] -- run a command with elevated privileges.
priv() {
    if ! _priv_resolve; then
        log_err "No privilege-escalation tool available (tried DEVMKDE_PRIV, sudo, doas)."
        log_err "On Devuan: 'doas apt-get install sudo' (or configure doas), then re-run this step."
        return 127
    fi
    "$PRIV_BIN" "$@"
}

# priv_n <cmd> [args...] -- non-interactive variant, for contexts where a
# hanging password prompt would be worse than a failure (cron, systemd timers).
# sudo -n / doas -n both fail fast instead of blocking on a tty that isn't there.
priv_n() {
    if ! _priv_resolve; then
        return 127
    fi
    "$PRIV_BIN" -n "$@"
}

# priv_as <user> <cmd> [args...] -- run as another (non-root) user.
priv_as() {
    local user="$1"; shift
    if ! _priv_resolve; then
        return 127
    fi
    "$PRIV_BIN" -u "$user" "$@"
}

# require_priv -- preflight for steps that should fail fast and legibly rather
# than half-way through with a raw "command not found". Honours
# DEVMKDE_ISO_BUILD the same way require_not_root does, so it can't break a bake.
require_priv() {
    if [ "${DEVMKDE_ISO_BUILD:-0}" = "1" ]; then
        return 0
    fi
    if ! _priv_resolve; then
        log_err "This step needs elevated privileges, but neither sudo nor doas is installed."
        log_err "On Devuan: 'doas apt-get install sudo' (or configure doas), then re-run this step."
        exit 1
    fi
    log_info "Escalation helper: $PRIV_BIN (override with DEVMKDE_PRIV)."
}

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

require_not_root() {
    [ "${DEVMKDE_ISO_BUILD:-0}" = "1" ] && return 0
    if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
        log_err "Do not run this as root — run it as your normal user; it escalates itself via priv() when needed."
        exit 1
    fi
}

# Real (non-root) user, even if this got invoked via sudo somewhere upstream.
ACTUAL_USER="${SUDO_USER:-$USER}"
[ -z "$ACTUAL_USER" ] && ACTUAL_USER="$(id -un)"

run_as_user() {
    if [ "$(id -un)" = "$ACTUAL_USER" ]; then
        "$@"
    else
        priv_as "$ACTUAL_USER" "$@"
    fi
}

# ask() — "Y/n" (default Y) or "y/N" (default N) prompt. With
# DEVMKDE_ASSUME_YES set (run.sh --yes, or ISO build hooks), the default is
# taken without prompting so the toolkit can run unattended.
ask() {
    local prompt="$1" default="${2:-Y}" reply
    local hint="(Y/n)"
    [ "$default" = "N" ] && hint="(y/N)"
    if [ -n "${DEVMKDE_ASSUME_YES:-}" ]; then
        reply="$default"
    else
        read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
        reply=${reply:-$default}
    fi
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [ "${#to_install[@]}" -eq 0 ]; then
        log_ok "$label already installed."
        return 0
    fi
    log_info "$label: installing ${to_install[*]}"
    if priv apt-get install -y "${to_install[@]}"; then
        log_ok "$label installed."
        return 0
    else
        log_warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

# install_deb_file -- install a locally downloaded .deb without touching
# sources.list. Used by the steps that pull a .deb straight off an upstream
# GitHub release because the project isn't packaged (Heroic, Vesktop).
#   install_deb_file "Heroic" /tmp/heroic_*.deb
#   install_deb_file "Vesktop" /tmp/vesktop_*.deb --repair
# --repair maps to `apt-get install -f -y`: the "fix broken dependencies" path
# for a .deb whose own deps aren't in the cache yet. We prefer the resolved
# install over `dpkg -i` because dpkg doesn't pull dependencies at all.
install_deb_file() {
    local label="$1"; shift
    local repair=0
    local args=()
    local a
    for a in "$@"; do
        case "$a" in
            --repair) repair=1 ;;
            *) args+=("$a") ;;
        esac
    done

    if [ "${#args[@]}" -eq 0 ]; then
        log_err "$label: no .deb file given."
        return 1
    fi
    local deb
    for deb in "${args[@]}"; do
        if [ ! -f "$deb" ]; then
            log_err "$label: $deb not found."
            return 1
        fi
    done

    if [ "$repair" -eq 1 ]; then
        log_info "$label: resolving dependencies for ${args[*]}"
        if priv apt-get install -f -y; then
            log_ok "$label dependencies resolved."
            return 0
        fi
        log_warn "$label: dependency repair failed — falling back to a direct install."
    fi

    log_info "$label: installing ${args[*]}"
    if priv apt-get install -y "${args[@]}"; then
        log_ok "$label installed."
        return 0
    else
        log_warn "$label: install failed (continuing)."
        return 1
    fi
}

# apt_update — refresh package lists exactly once per run. run.sh updates
# once up front and exports DEVMKDE_SKIP_APT_UPDATE=1 so the per-script
# refreshes are no-ops; standalone runs still refresh here. Returns
# apt-get update's exit code so callers can abort if they want to.
apt_update() {
    [ -n "${DEVMKDE_SKIP_APT_UPDATE:-}" ] && return 0
    if command_exists apt-get; then
        priv apt-get update "$@"
    else
        log_err "apt-get not found — this needs a Debian/Devuan APT system."
        return 1
    fi
}

# check_repo_package — probe whether a package is even available before
# trying to install it. If it isn't, that almost always means a repo
# component (non-free-firmware / contrib) isn't enabled in sources.list.
# Usage: check_repo_package <probe-pkg> <component-hint>  -> 0 if available
check_repo_package() {
    local probe="$1" component="$2"
    local cand
    cand="$(apt-cache policy "$probe" 2>/dev/null | awk -F': ' '/Candidate:/{gsub(/ /,"",$2); print $2; exit}')"
    if [ -n "$cand" ] && [ "$cand" != "(none)" ]; then
        return 0
    fi
    log_warn "$probe is not available — the '$component' repo component is probably missing."
    log_warn "On Devuan, add the component to /etc/apt/sources.list (e.g. append"
    log_warn "'$component' to the suite line), run 'sudo apt-get update', then re-run this step."
    return 1
}

# init_system — print which init system this box actually runs: "systemd",
# "openrc" (Devuan), "sysvinit", or "unknown". Never guesses; Devuan ships all
# three and the auto-detection below matches what each one leaves in /run.
init_system() {
    if command_exists systemctl && [ -d /run/systemd/system ]; then
        echo "systemd"
    elif command_exists rc-service && [ -d /run/openrc/softlevel ]; then
        echo "openrc"
    elif command_exists service; then
        echo "sysvinit"
    else
        echo "unknown"
    fi
}

# start_service — enable+start a service under whatever init this box
# actually runs: systemd, OpenRC (Devuan), or sysvinit. Never assumes
# systemd exists; Devuan deliberately ships all three.
start_service() {
    local svc="$1"
    case "$(init_system)" in
        systemd)
            priv systemctl enable --now "$svc" >/dev/null 2>&1 || true
            ;;
        openrc)
            priv rc-update add "$svc" default >/dev/null 2>&1 || true
            priv rc-service "$svc" start >/dev/null 2>&1 || true
            ;;
        *)
            if command_exists update-rc.d; then
                priv update-rc.d "$svc" defaults >/dev/null 2>&1 || true
            fi
            priv service "$svc" start >/dev/null 2>&1 || true
            ;;
    esac
}

# service_restart — restart a running service without touching enable state.
service_restart() {
    local svc="$1"
    case "$(init_system)" in
        systemd)
            priv systemctl restart "$svc" >/dev/null 2>&1 || true
            ;;
        openrc)
            priv rc-service "$svc" restart >/dev/null 2>&1 || true
            ;;
        *)
            priv service "$svc" restart >/dev/null 2>&1 || true
            ;;
    esac
}

# purge_if_installed — y/N-guarded removal that only purges what's actually
# installed (never guesses, re-runs are safe). Usage:
#   purge_if_installed "KDE games" kmahjongg kpat kpat kmines ksudoku
purge_if_installed() {
    local label="$1"; shift
    local to_purge=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" && to_purge+=("$pkg")
    done
    if [ "${#to_purge[@]}" -eq 0 ]; then
        log_ok "$label: nothing to purge."
        return 0
    fi
    log_info "$label: purging ${to_purge[*]}"
    if priv apt-get purge -y "${to_purge[@]}"; then
        log_ok "$label purged."
        return 0
    else
        log_warn "$label: some packages failed to purge (continuing)."
        return 1
    fi
}

# sha256_verify — strict checksum verification where upstream publishes a
# known-good hash. Usage: sha256_verify <file> <expected-sha256>
sha256_verify() {
    local file="$1" expected="$2"
    [ -f "$file" ] || { log_err "sha256_verify: $file not found"; return 1; }
    local actual
    actual="$(sha256sum "$file" | cut -d' ' -f1)"
    if [ "$actual" = "$expected" ]; then
        log_ok "sha256 verified for $(basename "$file")."
        return 0
    fi
    log_err "sha256 MISMATCH for $(basename "$file")."
    log_err "  got:      $actual"
    log_err "  expected: $expected"
    return 1
}

# verify_download — structural sanity check for anything this toolkit
# fetches: non-empty, and a valid archive/package/zip of its expected
# kind. This is a *plausibility* check (catches truncation, HTML error
# pages, 404 bodies), not a substitute for sha256_verify where upstream
# publishes hashes. Always logs the computed sha256 so you can compare
# against a release page manually.
# Usage: verify_download <file> [min-size-bytes]  (min default 1024)
verify_download() {
    local file="$1"
    local min_size="${2:-1024}"
    [ -f "$file" ] || { log_err "verify_download: $file not found."; return 1; }

    local size
    size="$(stat -c%s "$file" 2>/dev/null || echo 0)"
    if [ "$size" -lt "$min_size" ]; then
        log_err "$(basename "$file") looks empty/truncated (${size} bytes)."
        return 1
    fi

    case "$file" in
        *.deb)
            if ! dpkg-deb --info "$file" >/dev/null 2>&1; then
                log_err "$(basename "$file") is not a valid .deb package."
                return 1
            fi
            ;;
        *.tar.gz|*.tgz)
            if ! tar -tzf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.gz."; return 1; fi
            ;;
        *.tar.bz2)
            if ! tar -tjf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.bz2."; return 1; fi
            ;;
        *.tar.xz)
            if ! tar -tJf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar.xz."; return 1; fi
            ;;
        *.tar)
            if ! tar -tf "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid tar."; return 1; fi
            ;;
        *.zip)
            if ! unzip -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid zip."; return 1; fi
            ;;
        *.gz)
            if ! gzip -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid gzip."; return 1; fi
            ;;
        *.xz)
            if ! xz -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid xz."; return 1; fi
            ;;
        *.bz2)
            if ! bzip2 -t "$file" >/dev/null 2>&1; then log_err "$(basename "$file") is not a valid bz2."; return 1; fi
            ;;
    esac

    log_ok "Download verified: $(basename "$file") (${size} bytes)."
    return 0
}

# KDE ships kwriteconfig6 (Plasma 6) or kwriteconfig5 (Plasma 5) — resolve
# once here so callers don't have to repeat the detection.
KWRITECONFIG=""
KREADCONFIG=""
if command_exists kwriteconfig6; then
    KWRITECONFIG="kwriteconfig6"
    KREADCONFIG="kreadconfig6"
elif command_exists kwriteconfig5; then
    KWRITECONFIG="kwriteconfig5"
    KREADCONFIG="kreadconfig5"
fi
# kwrite_user <kwriteconfig args> — write a KDE config key as the desktop user.
#
# THEME_HOME_DIR is honoured by pointing XDG_CONFIG_HOME at the sandbox for the
# duration of the call. Without this, kwriteconfig6 resolves ~/.config through
# XDG and writes to the REAL home even when the caller redirected everything else
# into a temp dir — which is how running the unit tests rewrote the developer's
# live kcminputrc and silently dropped their cursorTheme. In production
# THEME_HOME_DIR is unset, so behaviour is unchanged.
kwrite_user() {
    [ -n "$KWRITECONFIG" ] || return 0
    if [ -n "${THEME_HOME_DIR:-}" ]; then
        run_as_user env XDG_CONFIG_HOME="$THEME_HOME_DIR/.config" "$KWRITECONFIG" "$@"
    else
        run_as_user "$KWRITECONFIG" "$@"
    fi
}

# DEVMKDE_GENERATED_MARKER — the filename this toolkit drops into every directory
# it generates, so "is this upstream's, or ours?" is answered by provenance
# rather than by pattern-matching directory names.
#
# Defined ONCE, here, because three modules write or consult it (otto.sh's
# discovery, moe.sh, and the Global Theme builder in theme.sh) and the failure
# mode of a divergence is invisible: a generated wrapper that no longer looks
# generated gets discovered as the upstream theme it was derived from and is then
# recoloured as its own source. On a rerun the id grows a suffix each time.
DEVMKDE_GENERATED_MARKER=".devmkde-generated"

# ini_set_key <file> <group> <key> <value> — set one key in one group of a KDE
# INI file, creating the file/group as needed, then verify it actually landed.
#
# WHY THIS EXISTS ALONGSIDE kwrite_user: kwriteconfig6 exits 0 but silently
# refuses to write some keys — verified on Plasma 6.3, `kwriteconfig6 --file
# kcminputrc --group Mouse --key cursorTheme <id>` returns 0, writes nothing, and
# leaves every other key in that same group writable. A cursor theme set that way
# is simply never applied, with no error anywhere. The same value written by hand
# as a plain append works and survives. So for keys KDE declines to store through
# its own API, fall back to editing the file, and always read the value back
# instead of trusting an exit code.
#
# Pure awk on purpose: no python dependency in a library every script sources.
ini_set_key() {
    local file="$1" group="$2" key="$3" value="$4"
    local tmp
    tmp="$(mktemp 2>/dev/null)" || return 1

    # The parent has to exist. In production ~/.config always does, so this is
    # invisible until a caller points at a fresh home (the unit sandbox, or a
    # --home override) — where the write would otherwise fail on a missing dir.
    mkdir -p "$(dirname "$file")" 2>/dev/null || { rm -f "$tmp"; return 1; }

    if [ -f "$file" ]; then
        awk -v g="$group" -v k="$key" -v v="$value" '
            function trim(s) { sub(/[ \t\r]+$/, "", s); return s }
            /^[ \t]*\[/ {
                # Leaving the target group without having written the key yet?
                if (ingrp && !done) { print k "=" v; done = 1 }
                ingrp = (trim($0) == "[" g "]")
                seen  = seen || ingrp
                print; next
            }
            ingrp && $0 ~ ("^[ \t]*" k "[ \t]*=") { print k "=" v; done = 1; next }
            { print }
            END {
                if (ingrp && !done) print k "=" v
                # Separator blank only when there is something above it to
                # separate from; on an empty (or group-less) file it just
                # leaves a stray blank first line.
                if (!seen) {
                    if (NR > 0) print ""
                    print "[" g "]"
                    print k "=" v
                }
            }
        ' "$file" > "$tmp" || { rm -f "$tmp"; return 1; }
    else
        printf '[%s]\n%s=%s\n' "$group" "$key" "$value" > "$tmp" || { rm -f "$tmp"; return 1; }
    fi

    # Failure here is a real failure the caller must hear about from the return
    # code, not from cp's stderr — so the message is dropped rather than printed.
    run_as_user cp "$tmp" "$file" 2>/dev/null || { rm -f "$tmp"; return 1; }
    rm -f "$tmp"

    # Read the value back out of the file we just wrote and compare. Deliberately
    # NOT kreadconfig: that tool takes a bare basename and resolves it through the
    # XDG config dirs, so for any path outside ~/.config it silently answers from
    # a different file than the one written. awk always reads the right one.
    local got
    got="$(awk -v g="$group" -v k="$key" '
        function trim(s) { sub(/[ \t\r]+$/, "", s); return s }
        /^[ \t]*\[/ { ingrp = (trim($0) == "[" g "]"); next }
        ingrp && $0 ~ ("^[ \t]*" k "[ \t]*=") {
            sub(/^[^=]*=[ \t]*/, "", $0)
            sub(/[ \t\r]+$/, "", $0)
            print; exit
        }
    ' "$file" 2>/dev/null)"
    [ "$got" = "$value" ]
}

# write_cursor_theme <home> <cursor-id> — apply a cursor theme and confirm it is
# really in kcminputrc before the caller claims success.
#
# Deliberately does NOT call kwriteconfig first. On Plasma 6.3 that call exits 0
# and writes nothing for this key, so it bought nothing in production — while in
# the unit tests it was actively destructive: kwriteconfig6 resolves ~/.config
# through XDG, so it rewrote the developer's real kcminputrc from KConfig's
# in-memory copy, which has no cursorTheme, wiping the live setting every time
# the suite ran. ini_set_key is both the path that works and the side-effect-free
# one.
write_cursor_theme() {
    local home_dir="${1:-$HOME}" id="$2" target
    target="$home_dir/.config/kcminputrc"
    [ -n "$id" ] || return 1
    ini_set_key "$target" Mouse cursorTheme "$id"
}
kread_user() {
    [ -n "$KREADCONFIG" ] && run_as_user "$KREADCONFIG" "$@"
}

# bind_global_shortcut <id> <friendly-name> <key-sequence> <command>
#
# Plasma 6 retired KHotKeys' khotkeysrc entirely, so writing it produces a
# config that looks right and does nothing. A *custom* shortcut in Plasma 6 is
# two files working together, which is exactly what "System Settings >
# Shortcuts > Add Command..." writes:
#
#   ~/.local/share/applications/<id>.desktop
#     [Desktop Entry] ... Exec=<command>
#     X-KDE-GlobalAccel-CommandShortcut=true   <- makes KGlobalAccel offer it
#
#   ~/.config/kglobalshortcutsrc, group "<id>.desktop"
#     _k_friendly_name=<friendly-name>
#     _launch=<key-sequence>,none,<friendly-name>
#
# The ",none," in _launch is KGlobalAccel's "current key placeholder" field;
# omitting it makes the row render blank in System Settings.
#
# Idempotent by construction: both files are keyed by <id>, so re-running
# overwrites in place instead of stacking duplicate rows. Takes effect at the
# next login -- KGlobalAccel reads these at session start, not live.
bind_global_shortcut() {
    local id="$1" name="$2" key="$3" cmd="$4"
    local desktop_name="${id}.desktop"
    local apps_dir="$HOME/.local/share/applications"

    if [ -z "$KWRITECONFIG" ]; then
        log_err "bind_global_shortcut: no kwriteconfig found — is this a KDE Plasma session?"
        return 1
    fi

    mkdir -p "$apps_dir"
    cat > "$apps_dir/$desktop_name" << EOF
[Desktop Entry]
Exec=$cmd
Name=$name
NoDisplay=true
StartupNotify=false
Type=Application
X-KDE-GlobalAccel-CommandShortcut=true
EOF

    kwrite_user --file kglobalshortcutsrc --group "$desktop_name" --key "_k_friendly_name" "$name"
    kwrite_user --file kglobalshortcutsrc --group "$desktop_name" --key "_launch" "$key,none,$name"
    return 0
}

# global_shortcut_bound <id> — true if this id already has an assigned key.
global_shortcut_bound() {
    local desktop_name="${1}.desktop"
    [ -n "$KWRITECONFIG" ] || return 1
    [ -n "$(kread_user --file kglobalshortcutsrc --group "$desktop_name" --key _launch 2>/dev/null)" ]
}

# bind_kwin_action <action> <key-sequence> [friendly-name]
#
# Set a KWin built-in global shortcut in kglobalshortcutsrc [kwin] group.
# KWin actions (like ShowDesktop, Quick Tile Left/Right, etc.) are NOT
# custom commands - they live under the "kwin" group with specific action keys.
# This writes the action mapping in the format KGlobalAccel expects.
# Idempotent - overwrites existing binding for the action.
bind_kwin_action() {
    local action="$1" key="$2" name="${3:-$action}"
    [ -n "$KWRITECONFIG" ] || {
        log_err "bind_kwin_action: no kwriteconfig found — is this a KDE Plasma session?"
        return 1
    }
    # KGlobalAccel format: <key-sequence>,<default>,<description>
    kwrite_user --file kglobalshortcutsrc --group kwin --key "$action" "$key,none,$name"
    return 0
}

# kwin_action_bound <action> — true if this KWin action already has a binding.
kwin_action_bound() {
    local action="$1"
    [ -n "$KWRITECONFIG" ] || return 1
    [ -n "$(kread_user --file kglobalshortcutsrc --group kwin --key "$action" 2>/dev/null | grep -v '^$')" ]
}

# wait_for_plasmashell [tries] — block until plasmashell is ready to run a
# Plasma Shell scripting payload, then return 0. Returns 1 if it never came up.
#
# WHY THIS IS NEEDED: plasmashell gets *restarted* by anything that applies a
# color scheme or a Global Theme (46-applyThemes.sh does both). On a full
# run.sh pass the steps are ordered by plain `find -name '[0-9]*.sh' | sort`,
# so the step right after the theme step fires while plasmashell is still
# coming back up. D-Bus then answers
#
#   Cannot find 'org.kde.PlasmaShell.evaluateScript' in object /PlasmaShell
#   at org.kde.plasmashell
#
# and the caller tears down and exits 1, having changed nothing. The symptom
# looks exactly like "the scripting API doesn't exist" — it does exist, the
# object just isn't re-registered yet. (This bit 47-plasmaPanel.sh: a panel
# step failed with that message and silently left the stock KDE default panel
# behind.)
#
# The probe is a no-op script rather than a mere object listing, so it also
# proves the scripting engine finished loading and not just that the D-Bus
# service came back. "1;" evaluates to nothing and changes no state.
wait_for_plasmashell() {
    local tries="${1:-30}" i=0
    local dbus=""
    if command_exists qdbus6; then
        dbus="qdbus6"
    elif command_exists qdbus; then
        dbus="qdbus"
    else
        log_err "Neither qdbus6 nor qdbus found — can't reach plasmashell."
        return 1
    fi

    while [ "$i" -lt "$tries" ]; do
        if run_as_user "$dbus" org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript "1;" >/dev/null 2>&1; then
            [ "$i" -gt 0 ] && log_info "plasmashell came up after ${i}s."
            return 0
        fi
        i=$((i + 1))
        sleep 1
    done
    return 1
}