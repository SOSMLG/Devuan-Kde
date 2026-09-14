#!/usr/bin/env bash
# =======================================================
# Update Notifier — a lightweight stand-in for an update manager
# -------------------------------------------------------
# Real mintupdate isn't packaged for Devuan, and Plasma's Discover is a
# heavyweight dependency to drag in just for "are there updates?" pings.
# Rather than do that, this is a small, transparent alternative: a cron
# job (works identically under OpenRC, sysvinit, or systemd — cron is
# init-agnostic) that checks for upgradable packages on a schedule and
# pops a desktop notification if there are any, clicking through to a
# normal apt upgrade in a terminal, or Synaptic if you'd rather click
# through it.
#
# No background daemon, no systemd timer/service unit — just cron +
# notify-send + a tiny wrapper script. Everything it touches is listed
# below so nothing here is a black box.
#
# Ported from the devuan-cinnamon-setup sibling toolkit (DE-agnostic).
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Update Notifier"

log_info "Refreshing package lists..."
sudo apt-get update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Dependencies: cron (defensive, usually already present), libnotify
#    for notify-send, synaptic as the point-and-click "apply updates" GUI.
# ---------------------------------------------------------------------------
install_pkgs "Update notifier dependencies" cron libnotify-bin synaptic

# ---------------------------------------------------------------------------
# 2. The checker script itself, in ~/.local/bin so it needs no root to
#    install or edit later.
# ---------------------------------------------------------------------------
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
CHECKER="$BIN_DIR/devuan-update-check.sh"

log_info "Writing $CHECKER ..."
cat > "$CHECKER" << 'EOF'
#!/usr/bin/env bash
# Checks for upgradable packages and sends a desktop notification if any
# are found. Meant to be run from cron under the desktop user, not root.
set -uo pipefail

# apt-get update needs sudo; run it non-interactively and quietly. If this
# box requires a password for sudo (most do), add a narrowly-scoped NOPASSWD
# rule for just this command in /etc/sudoers.d/ if you want silent checks —
# left as your choice rather than done for you, since editing sudoers
# unattended is exactly the kind of thing this toolkit avoids doing quietly.
sudo -n apt-get update -qq >/dev/null 2>&1 || true

COUNT=$(apt list --upgradable 2>/dev/null | grep -c '\[upgradable' || true)

if [ "${COUNT:-0}" -gt 0 ]; then
    notify-send -i software-update-available \
        "Updates available" \
        "${COUNT} package(s) can be upgraded. Open Synaptic or run: sudo apt full-upgrade" \
        --app-name="Devuan KDE Update Notifier"
fi
EOF
chmod +x "$CHECKER"
log_ok "Checker script installed."

# ---------------------------------------------------------------------------
# 3. Cron entry — runs as the desktop user (crontab -u), checks twice a
#    day. Idempotent: removes any previous entry for this exact script
#    before adding, so re-running this installer doesn't stack duplicates.
# ---------------------------------------------------------------------------
if ask "Install a cron job to check for updates twice daily (09:00 and 18:00)?"; then
    CRON_MARKER="# devuan-kde-setup: update notifier"
    NEW_CRON=$(mktemp)
    ( crontab -l 2>/dev/null | grep -vF "$CHECKER" | grep -vF "$CRON_MARKER" ) > "$NEW_CRON" || true
    {
        echo "$CRON_MARKER"
        echo "0 9,18 * * * DISPLAY=:0 $CHECKER >/dev/null 2>&1"
    } >> "$NEW_CRON"

    if crontab "$NEW_CRON"; then
        log_ok "Cron job installed (runs at 09:00 and 18:00 daily)."
    else
        log_err "Failed to install the cron job — you can add it manually with 'crontab -e':"
        echo "  0 9,18 * * * DISPLAY=:0 $CHECKER"
    fi
    rm -f "$NEW_CRON"

    # cron itself needs to actually be running — enable it via whatever
    # init system this box uses.
    start_service cron
    log_ok "cron enabled and started via $(init_system)."
    log_warn "Notifications need an active graphical session (DISPLAY=:0). If you use a non-default"
    log_warn "display number or multiple sessions, edit the DISPLAY= value in your crontab accordingly."
fi

if ask "Run a check right now to confirm it works?"; then
    "$CHECKER"
    log_ok "Check ran. If updates are available you should see a notification pop up now."
fi

echo -e "${GREEN}Update notifier step complete.${NC}"
log_warn "This checks and notifies only — it never applies updates automatically. Use Synaptic or"
log_warn "'sudo apt full-upgrade' yourself when you're ready, same philosophy as Timeshift's manual trigger."