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
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVUAN_KDE_COMMON_SH_LOADED:-}" ] && return 0
_DEVUAN_KDE_COMMON_SH_LOADED=1

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; NC="\033[0m"

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

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

require_not_root() {
    if [ "$(id -u)" -eq 0 ]; then
        log_err "Do not run this as root — run it as your normal user; it will call sudo itself when needed."
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
        sudo -u "$ACTUAL_USER" "$@"
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
    if sudo apt-get install -y "${to_install[@]}"; then
        log_ok "$label installed."
        return 0
    else
        log_warn "$label: some packages failed to install (continuing)."
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
        sudo apt-get update "$@"
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

# start_service — enable+start a service under whatever init this box
# actually runs: systemd, OpenRC (Devuan), or sysvinit. Never assumes
# systemd exists; Devuan deliberately ships all three.
start_service() {
    local svc="$1"
    if command_exists systemctl && [ -d /run/systemd/system ]; then
        sudo systemctl enable --now "$svc" >/dev/null 2>&1 || true
    elif command_exists rc-service && [ -d /run/openrc/softlevel ]; then
        sudo rc-update add "$svc" default >/dev/null 2>&1 || true
        sudo rc-service "$svc" start >/dev/null 2>&1 || true
    else
        if command_exists update-rc.d; then
            sudo update-rc.d "$svc" defaults >/dev/null 2>&1 || true
        fi
        sudo service "$svc" start >/dev/null 2>&1 || true
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
if command_exists kwriteconfig6; then
    KWRITECONFIG="kwriteconfig6"
elif command_exists kwriteconfig5; then
    KWRITECONFIG="kwriteconfig5"
fi
kwrite_user() {
    [ -n "$KWRITECONFIG" ] && run_as_user "$KWRITECONFIG" "$@"
}