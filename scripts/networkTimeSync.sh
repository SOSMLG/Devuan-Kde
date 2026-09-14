#!/usr/bin/env bash
# =======================================================
# Time Sync (NTP) via chrony
# -------------------------------------------------------
# Enables automatic time synchronization with chrony, the
# default NTP daemon on Devuan/Debian. Works under any
# init (systemd, OpenRC, sysvinit) through start_service().
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Time Sync (NTP)"

if is_installed chrony; then
    log_ok "chrony already installed."
else
    if ask "Install and enable NTP time sync via chrony?"; then
        apt_update || { log_err "apt-get update failed, aborting."; exit 1; }
        install_pkgs "chrony" chrony
    else
        log_info "Skipped."
        exit 0
    fi
fi

# A competing NTP daemon (openntpd ships on some netinstall spins) would
# fight chrony for the same socket/clock — park it under whatever init
# this box runs before enabling chrony.
if is_installed openntpd; then
    log_info "openntpd detected — parking it so chrony owns the clock."
    case "$(init_system)" in
        systemd)
            sudo systemctl disable --now openntpd >/dev/null 2>&1 || true
            ;;
        openrc)
            sudo rc-service openntpd stop >/dev/null 2>&1 || true
            sudo rc-update del openntpd default >/dev/null 2>&1 || true
            ;;
        *)
            sudo update-rc.d openntpd disable >/dev/null 2>&1 || true
            sudo service openntpd stop >/dev/null 2>&1 || true
            ;;
    esac
fi

start_service chrony

# Sanity check — chronyc tracking as a normal user usually works.
if sleep 2 && command_exists chronyc && chronyc tracking >/dev/null 2>&1; then
    log_ok "chrony is tracking time; system clock will stay in sync."
else
    log_warn "chrony is installed but not tracking yet (normal on the first boot before"
    log_warn "it picks a server). Verify later with: chronyc tracking"
fi