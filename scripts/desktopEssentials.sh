#!/usr/bin/env bash
# =======================================================
# Desktop Essentials
# -------------------------------------------------------
# The "closest to Mint" completeness pass: a unified
# software center, plug-and-play printing, a partition
# tool, and a firewall control panel — all surfaced through
# native KDE System Settings / Discover rather than bolted-
# on GTK tools, matching the rest of this toolkit.
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
echo -e "${CYAN} Desktop Essentials${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Flatpak + Flathub + Discover's Flatpak backend — makes Discover a
#    unified software center (apt + Flatpak) like Mint's Software Manager.
# ---------------------------------------------------------------------------
if ask "Set up Flatpak + Flathub + Discover integration?"; then
    install_pkgs "Flatpak" flatpak plasma-discover-backend-flatpak

    if command -v flatpak >/dev/null 2>&1; then
        if sudo flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            log_ok "Flathub remote added system-wide."
        else
            log_warn "Could not add the Flathub remote (may already exist)."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 1b. PackageKit — the piece Discover actually needs to see (and notify
#     about) apt updates at all. Without it, Discover can browse Flatpak
#     fine but has nothing wired up for the base system's own packages,
#     so the "updates available" panel notification never fires — the
#     closest thing Devuan/Debian has to Mint's Update Manager icon.
# ---------------------------------------------------------------------------
if ask "Install PackageKit (lets Discover see + notify about apt updates)?"; then
    install_pkgs "PackageKit" packagekit
    log_ok "Discover will now show a panel notification when apt updates are available."
    log_info "First check can take a minute — PackageKit builds its own package cache on first run."
fi

# ---------------------------------------------------------------------------
# 2. Printing — CUPS + broad driver set + network printer auto-discovery
# ---------------------------------------------------------------------------
if ask "Install printing support (CUPS + drivers + network printer auto-discovery)?"; then
    install_pkgs "Printing" cups cups-browsed printer-driver-all

    if is_installed cups; then
        start_service cups
        log_ok "CUPS started."
    fi

    if getent group lpadmin >/dev/null 2>&1; then
        if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx lpadmin; then
            log_ok "$ACTUAL_USER already in the lpadmin group."
        elif sudo usermod -aG lpadmin "$ACTUAL_USER"; then
            log_ok "Added $ACTUAL_USER to lpadmin (manage printers without a password prompt each time)."
            log_warn "Log out and back in for this to take effect."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 3. KDE Partition Manager
# ---------------------------------------------------------------------------
if ask "Install KDE Partition Manager?"; then
    install_pkgs "Partition Manager" partitionmanager
fi

# ---------------------------------------------------------------------------
# 4. Firewall control panel. Installed by default; enabling is a separate,
#    explicit opt-in with an SSH-safe guard, since flipping on
#    default-deny-incoming blind could silently break something you rely
#    on (SSH into this machine, local file sharing).
# ---------------------------------------------------------------------------
if ask "Install firewall control panel (plasma-firewall + ufw)?"; then
    install_pkgs "Firewall" plasma-firewall ufw

    if is_installed ufw && ask "Also enable it now (deny-incoming/allow-outgoing baseline, SSH-safe)?" "N"; then
        NEEDS_SSH_RULE=0
        if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]; then
            NEEDS_SSH_RULE=1
        elif command -v ss >/dev/null 2>&1 && ss -tln 2>/dev/null | grep -qE ':22\b'; then
            NEEDS_SSH_RULE=1
        fi
        if [ "$NEEDS_SSH_RULE" -eq 1 ]; then
            log_info "Active SSH session or listening sshd detected — allowing SSH before enabling default-deny."
            sudo ufw allow ssh comment 'preserve SSH access before enabling default-deny' \
                || log_warn "Couldn't add the SSH allow-rule — double-check before enabling ufw if you're on SSH."
        fi
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        if sudo ufw --force enable; then
            log_ok "ufw enabled: incoming denied by default, outgoing allowed. Manage exceptions via System"
            log_ok "Settings > Firewall or 'sudo ufw allow <port>'."
        else
            log_warn "ufw failed to enable — check 'sudo ufw status verbose'."
        fi
    else
        log_warn "Installed only — ufw is NOT enabled. Turn it on yourself via System Settings > Firewall"
        log_warn "(or 'sudo ufw enable') once you've confirmed it won't block anything you rely on."
    fi
fi

echo -e "${GREEN}Desktop essentials step complete.${NC}"
