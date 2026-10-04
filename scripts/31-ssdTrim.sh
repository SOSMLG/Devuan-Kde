#!/usr/bin/env bash
# DEVMKDE_DESC: Weekly fstrim via cron (init-agnostic, works on OpenRC/sysvinit)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: sysmgmt
# =======================================================
# SSD Trim — weekly fstrim via cron
# -------------------------------------------------------
# Debian/Devuan's fstrim usually ships as a systemd timer
# (fstrim.timer) that doesn't exist under OpenRC/sysvinit — this is the
# same idea (a periodic 'fstrim -av' across all TRIM-capable mounted
# filesystems) done with cron instead, so it works under any init
# system this toolkit supports.
#
# Safe to run even with no SSD present: fstrim -av silently skips any
# filesystem that doesn't support TRIM, so this only actually does
# anything on drives where it's safe to.
#
# Ported from the devuan-cinnamon-setup sibling toolkit (DE-agnostic).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "SSD Trim"

install_pkgs "util-linux (provides fstrim, almost always already installed)" util-linux
install_pkgs "cron" cron

if ask "Run 'fstrim -av' once now to confirm it works on this system?"; then
    if priv fstrim -av; then
        log_ok "fstrim ran successfully."
    else
        log_warn "fstrim reported an issue — check the output above (harmless if no TRIM-capable filesystem is mounted)."
    fi
fi

if ask "Install a weekly cron job for automatic fstrim (root crontab, Sunday 03:30)?"; then
    MARKER="# devuan-kde-setup: weekly fstrim"
    NEW_CRON=$(mktemp)
    ( priv crontab -l 2>/dev/null | grep -vF "fstrim -av" | grep -vF "$MARKER" ) > "$NEW_CRON" || true
    {
        echo "$MARKER"
        echo "30 3 * * 0 /sbin/fstrim -av >/var/log/fstrim.log 2>&1"
    } >> "$NEW_CRON"

    if priv crontab "$NEW_CRON"; then
        log_ok "Weekly fstrim cron job installed (root crontab, Sundays 03:30)."
    else
        log_err "Failed to install the cron job — add it manually with 'sudo crontab -e':"
        echo "  30 3 * * 0 /sbin/fstrim -av >/var/log/fstrim.log 2>&1"
    fi
    rm -f "$NEW_CRON"

    start_service cron
    log_ok "cron enabled and started via $(init_system)."
fi

echo -e "${GREEN}SSD Trim step complete.${NC}"