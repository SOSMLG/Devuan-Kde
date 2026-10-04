#!/usr/bin/env bash
# DEVMKDE_DESC: Refresh package lists + full-upgrade before anything else (run first on a fresh install)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# System Update — run this first
# -------------------------------------------------------
# The "update everything before you start" step, deliberately its own
# script rather than baked silently into run.sh's startup, so it's still
# just an ordinary y/N step you can skip if you'd rather update later or
# on your own schedule.
#
# Ported from the devuan-cinnamon-setup sibling toolkit (DE-agnostic).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "System Update"

if ask "Refresh package lists and install all available updates now?"; then
    log_info "Running apt-get update..."
    if ! apt_update; then
        log_err "apt-get update failed — check your network/sources.list before continuing."
        exit 1
    fi

    UPGRADABLE=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)
    if [ "${UPGRADABLE:-0}" -eq 0 ]; then
        log_ok "Already up to date — nothing to install."
    else
        log_info "${UPGRADABLE} package(s) can be upgraded."
        if ask "Proceed with 'apt full-upgrade'?"; then
            priv apt-get full-upgrade -y && log_ok "System updated." \
                || log_warn "full-upgrade reported issues — check the output above."
        else
            log_warn "Skipped the actual upgrade — package lists are refreshed, nothing installed."
        fi
    fi

    if ask "Also remove now-unneeded packages (apt autoremove)?"; then
        priv apt-get autoremove --purge -y && log_ok "Cleaned up orphaned packages."
    fi
else
    log_warn "Skipped."
fi

echo -e "${GREEN}System update step complete.${NC}"
log_warn "If the kernel or a core library was updated, a reboot before continuing is a good idea."