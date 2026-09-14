#!/usr/bin/env bash
# =======================================================
# applyThemes.sh — swap the active KDE Plasma palette
# -------------------------------------------------------
# The theme engine ships 8 palettes (themes/<name>/palette.sh). Each is a
# single source of truth for a full look: Konsole scheme + profile, Plasma
# color scheme (.colors) and the kdeglobals accent color.
#
#   applyThemes.sh               interactive picker (default: mocha-red)
#   applyThemes.sh <palette-id>  apply that palette directly
#   applyThemes.sh --list        list available palettes
#
# Currently active palette: cat ~/.local/state/devuan-kde-setup/current-theme
# =======================================================
set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# shellcheck source=lib/theme.sh
source "$SCRIPT_DIR/lib/theme.sh"

require_not_root

usage() {
    echo "Usage: $0 [palette-id|--list]"
    echo
    echo "Available palettes:"
    list_palettes | while IFS='|' read -r id short name; do
        printf '  %-14s %s\n' "$id" "$name"
    done
    echo
    echo "The active palette is recorded in $CURRENT_THEME_FILE" 2>/dev/null || true
}

log_head "Devuan KDE — color palette"

case "${1:-}" in
    --list|-l|help|--help|-h)
        usage
        exit 0
        ;;
    "")
        # no arg: interactive picker, mocha-red as the default answer
        list_palettes | while IFS='|' read -r id short name; do
            printf '%s\n' "  $id  ($name)"
        done
        if [ "${DEVMKDE_ASSUME_YES:-0}" = "1" ]; then
            log_info "DEVMKDE_ASSUME_YES set — applying the default palette instead of prompting."
            apply_palette "mocha-red"
            exit $?
        fi
        printf '\nPick a palette id (default: mocha-red): '
        read -r chosen
        [ -n "$chosen" ] || chosen="mocha-red"
        apply_palette "$chosen"
        exit $?
        ;;
    *)
        # a palette id was given
        if [ ! -d "$THEMES_DIR/$1" ]; then
            log_err "Unknown palette '$1'."
            usage
            exit 1
        fi
        apply_palette "$1"
        exit $?
        ;;
esac