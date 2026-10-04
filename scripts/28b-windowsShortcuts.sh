#!/usr/bin/env bash
# DEVMKDE_DESC: Add Windows-like global shortcuts (Win+E/R/D/S/I, Quick Tile, etc.)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# Windows-like Shortcuts — familiar keybindings for Plasma
# -------------------------------------------------------
# Adds common Windows keybindings using Meta (Super/Windows key):
#   Win+E -> Dolphin (File Explorer)
#   Win+R -> KRunner (Run)
#   Win+D -> Show Desktop
#   Win+S -> KRunner/Search
#   Win+I -> System Settings
#   Win+Shift+S -> Spectacle (screenshot region)
#   Win+Left/Right/Up/Down -> Quick Tile window
#
# KWin built-in actions (Show Desktop, Quick Tile) are set in [kwin]
# group of kglobalshortcutsrc. Custom commands use .desktop + kglobalshortcutsrc
# as per Plasma 6 conventions (via bind_global_shortcut).
#
# Non-destructive: skips bindings that are already set by user.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Windows-like Shortcuts"

log_info "Adding familiar Windows keybindings (Meta = Windows key):"
cat << 'EOF'
   Meta+E        -> Dolphin (File Explorer)
   Meta+R        -> KRunner (Run)
   Meta+D        -> Show Desktop
   Meta+S        -> KRunner (Search)
   Meta+I        -> System Settings
   Meta+Shift+S  -> Spectacle (screenshot region)
   Meta+Left     -> Quick Tile Left
   Meta+Right    -> Quick Tile Right
   Meta+Up       -> Quick Tile Top
   Meta+Down     -> Quick Tile Bottom
EOF
echo

if ! ask "Apply Windows-like shortcuts now?"; then
    log_warn "Skipped."
    exit 0
fi

if [ -z "$KWRITECONFIG" ]; then
    log_err "kwriteconfig not found — is this a KDE Plasma session?"
    exit 1
fi

ADDED=0
SKIPPED=0

# Custom command shortcuts (.desktop + kglobalshortcutsrc)
CUSTOM_BINDINGS=(
    "devuan-kde-windows-files|Dolphin (File Explorer)|Meta+E|dolphin"
    "devuan-kde-windows-run|KRunner|Meta+R|krunner"
    "devuan-kde-windows-search|KRunner (Search)|Meta+S|krunner"
    "devuan-kde-windows-settings|System Settings|Meta+I|systemsettings"
    "devuan-kde-windows-spectacle|Spectacle|Meta+Shift+S|spectacle -r"
)

for b in "${CUSTOM_BINDINGS[@]}"; do
    IFS='|' read -r id name key cmd <<< "$b"
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

# KWin built-in actions
KWIN_ACTIONS=(
    "ShowDesktop|Meta+D|Show Desktop"
    "Window Quick Tile Left|Meta+Left|Quick Tile Left"
    "Window Quick Tile Right|Meta+Right|Quick Tile Right"
    "Window Quick Tile Top|Meta+Up|Quick Tile Top"
    "Window Quick Tile Bottom|Meta+Down|Quick Tile Bottom"
)

for ka in "${KWIN_ACTIONS[@]}"; do
    IFS='|' read -r action key name <<< "$ka"
    # Check if already bound (non-empty)
    current="$(kread_user --file kglobalshortcutsrc --group kwin --key "$action" 2>/dev/null || true)"
    if [ -n "$current" ] && [ "$current" != "none,none," ]; then
        log_warn "  $name ($action): already bound, leaving untouched."
        SKIPPED=$((SKIPPED + 1))
        continue
    fi
    if bind_kwin_action "$action" "$key" "$name"; then
        log_ok "  Added $key -> $name"
        ADDED=$((ADDED + 1))
    else
        log_err "  Failed to set $name."
    fi
done

if [ "$ADDED" -eq 0 ]; then
    log_ok "Nothing new to add — all ${SKIPPED} binding(s) already present."
else
    log_ok "Added ${ADDED} shortcut(s); ${SKIPPED} already present."
    log_info "kglobalaccel reads shortcuts at session start — log out and back in to activate."
fi

echo -e "${GREEN}Windows-like shortcuts complete.${NC}"
