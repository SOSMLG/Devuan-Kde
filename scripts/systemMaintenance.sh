#!/usr/bin/env bash
# =======================================================
# System Maintenance
# -------------------------------------------------------
# Init-agnostic tidy-up: apt cleanup, removal of an
# obsolete transitional package, removal of dead ~/.local/bin
# symlinks, and an optional full upgrade. Each step asks —
# safe to run any time, on systemd, OpenRC, or sysvinit.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "System Maintenance"

# --- 1. APT housekeeping --------------------------------------------------
if ask "Run apt autoclean + autoremove (remove unneeded packages)?"; then
    sudo apt-get autoclean || true
    sudo apt-get autoremove -y || log_warn "autoremove reported issues (continuing)."
fi

# --- 2. Obsolete transitional package -------------------------------------
# pipewire-audio-client-libraries became an empty transitional package and
# has been dropped by the PipeWire packaging; if it lingers it's pure cruft.
if is_installed pipewire-audio-client-libraries; then
    if ask "Remove obsolete pipewire-audio-client-libraries (now an empty transitional package)?"; then
        sudo apt-get purge -y pipewire-audio-client-libraries || log_warn "Removal failed — ignorable if APT is mid-transition."
    fi
fi

# --- 3. Dead ~/.local/bin symlinks ---------------------------------------
# Toolkit scripts create symlinks (e.g. ~/.local/bin/telegram) that dangle
# if the target was moved/removed. List them and let you remove.
local_links=$({ for f in "$HOME"/.local/bin/*; do [ -L "$f" ] && [ ! -e "$f" ] && printf '%s\n' "$f"; done; } 2>/dev/null)
if [ -n "$local_links" ]; then
    echo -e "${YELLOW}[!] Dead symlinks found in $HOME/.local/bin:${NC}"
    while IFS= read -r lnk; do
        [ -z "$lnk" ] && continue
        echo "     $lnk → $(readlink "$lnk")"
    done <<< "$local_links"
    if ask "Remove these dead symlinks?"; then
        while IFS= read -r lnk; do
            [ -z "$lnk" ] && continue
            rm "$lnk" && log_ok "Removed: $lnk"
        done <<< "$local_links"
    fi
else
    log_ok "No dead symlinks in ~/.local/bin."
fi

# --- 4. Optional full upgrade ---------------------------------------------
if ask "Run 'apt full-upgrade' (upgrade all installed packages)? This can be large. (y/N)?" "N"; then
    apt_update
    sudo apt-get full-upgrade -y
fi

echo -e "${GREEN}Maintenance complete.${NC}"