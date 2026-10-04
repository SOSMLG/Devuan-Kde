#!/usr/bin/env bash
# DEVMKDE_DESC: Add custom Plasma global shortcuts (terminal, Dolphin, editor, system monitor)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# Hotkeys — Plasma custom keyboard shortcuts
# -------------------------------------------------------
# Plasma's own defaults (Super opens the launcher, Alt+Tab to switch,
# Ctrl+Alt+T for Konsole, Meta+E for Dolphin, screenshot keys, etc.) are
# left alone — this only *adds* a small set of bindings for one-key
# access to terminal, file manager, editor, and system monitor.
#
# Mechanism (Plasma 6 / KGlobalAccel)
# -----------------------------------
# This used to write ~/.config/khotkeysrc. KHotKeys was retired after
# Plasma 5.27 and that file no longer exists in a Plasma 6 session, so the
# old approach produced a config that looked perfectly correct and bound
# nothing at all. A *custom* shortcut in Plasma 6 is two files:
#
#   ~/.local/share/applications/<id>.desktop   the action, flagged with
#                                              X-KDE-GlobalAccel-CommandShortcut
#   ~/.config/kglobalshortcutsrc              group "<id>.desktop" holding
#                                              _k_friendly_name + _launch
#
# which is precisely what "System Settings > Shortcuts > Add Command..."
# writes. bind_global_shortcut() in lib/common.sh does all of it.
#
# Idempotent: every binding is keyed by a fixed id, so re-running overwrites
# that entry in place instead of stacking duplicates.
#
# Note: KGlobalAccel reads these at session start, not live — log out and
# back in (or restart kglobalaccel) for them to take effect.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Hotkeys"

# id|friendly-name|key-sequence|command
BINDINGS=(
    "devuan-kde-terminal|Terminal|Meta+Return|konsole"
    "devuan-kde-files|File Manager|Meta+f|dolphin"
    "devuan-kde-editor|Text Editor|Ctrl+Meta+e|kate"
    "devuan-kde-monitor|System Monitor|Ctrl+Shift+Escape|ksysguard"
)

log_info "This will add ${#BINDINGS[@]} custom shortcuts to your Plasma session:"
for b in "${BINDINGS[@]}"; do
    IFS='|' read -r id name key cmd <<< "$b"
    echo -e "   ${CYAN}${key}${NC} -> ${name} (${cmd})"
done
echo

if ! ask "Apply these shortcuts now?"; then
    log_warn "Skipped."
    exit 0
fi

if [ -z "$KWRITECONFIG" ]; then
    log_err "kwriteconfig not found — is this a KDE Plasma session?"
    exit 1
fi

ADDED=0
SKIPPED=0
for b in "${BINDINGS[@]}"; do
    IFS='|' read -r id name key cmd <<< "$b"

    # Idempotence: this id already has an assigned key → leave it alone so we
    # never clobber a binding the user has since changed in System Settings.
    if global_shortcut_bound "$id"; then
        log_warn "  $name: already bound, leaving untouched."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi

    if bind_global_shortcut "$id" "$name" "$key" "$cmd"; then
        log_ok "  Added $key -> $name ($cmd)"
        ADDED=$((ADDED + 1))
    else
        log_err "  Failed to write $name."
    fi
done

if [ "$ADDED" -eq 0 ]; then
    log_ok "Nothing new to add — all ${SKIPPED} binding(s) already present."
else
    log_ok "Added ${ADDED} shortcut(s); ${SKIPPED} already present."
    log_info "kglobalaccel reads shortcuts at session start — log out and back in to activate."
fi

echo -e "${GREEN}Hotkeys step complete.${NC}"
log_warn "Review/edit these any time in System Settings > Shortcuts > Custom Shortcuts."
log_warn "Removing one: delete ~/.local/share/applications/<id>.desktop and its"
log_warn "group in ~/.config/kglobalshortcutsrc, or clear the key in System Settings."