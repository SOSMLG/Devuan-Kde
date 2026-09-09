#!/usr/bin/env bash
# =======================================================
# Timeshift — system snapshot/restore
# -------------------------------------------------------
# Mint's signature safety-net feature: take a snapshot
# before a risky change, roll back with a couple of clicks
# if something breaks. On Debian/Devuan the package depends
# on plain "cron", not systemd — so this works fine on
# Devuan's default sysvinit/runit setup, unlike some
# distros' packaging that leans on systemd timers instead.
#
# This installs the tool and makes sure a cron daemon is
# present, but deliberately does NOT auto-configure a
# snapshot device or schedule — that's a one-time choice
# with real disk-space implications, and Timeshift's own
# setup wizard (first launch) is quick and worth doing
# deliberately rather than silently guessing on your behalf.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Timeshift${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# cron is normally already present on Devuan/Debian by default, but this
# is defensive in case it was ever removed — Timeshift hard-depends on it.
install_pkgs "cron" cron
install_pkgs "Timeshift" timeshift

if is_installed timeshift; then
    echo -e "${GREEN}Timeshift installed.${NC}"
    log_warn "One-time setup needed: run 'sudo timeshift-launcher' (or find Timeshift in the"
    log_warn "app menu) to choose rsync vs BTRFS mode, where snapshots are stored, and a"
    log_warn "schedule. That choice is left to you rather than guessed automatically."
else
    log_err "Timeshift installation failed."
    exit 1
fi
