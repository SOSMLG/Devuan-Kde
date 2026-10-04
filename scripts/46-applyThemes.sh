#!/usr/bin/env bash
# DEVMKDE_DESC: Swap the active palette anytime (Konsole + Plasma color scheme + accent + Global Theme)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: optional
# =======================================================
# applyThemes.sh — swap the active KDE Plasma palette
# -------------------------------------------------------
# The theme engine ships 12 palettes, each a palette_<id>() function in
# themes/palettes.sh. A palette is a single source of truth for a full look:
# Konsole scheme + profile, Plasma color scheme (.colors) and the kdeglobals
# accent color.
#
# Two palettes go one step further, both best-effort — the palette itself is
# fully applied either way:
#
#   otto      if the Otto Plasma theme is installed (Discover), its Global
#             Theme, Kvantum and window decoration are recoloured to match, so
#             the whole desktop shares one red. Nothing about it requires Otto
#             — see scripts/lib/otto.sh.
#   moe-dark  installs the pinned upstream Moe v2.6 Global Theme from a mirror
#             and sanitises it, so the desktop carries Moe's own identity with
#             the panel and the components Moe does not ship left alone — see
#             scripts/lib/moe.sh.
#
#   applyThemes.sh               interactive picker (default: darkmatter)
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
    # Resolve the path at print time: CURRENT_THEME_FILE is only populated once
    # apply_palette has run, so relying on the sourced value here prints an empty
    # path and tells the user nothing.
    echo "The active palette is recorded in $(theme_state_dir)/current-theme"
}

# One source of truth for the shipped palette, shared with 14-plasmaTheme.sh.
DEFAULT_PALETTE="${DEVMKDE_DEFAULT_PALETTE:-darkmatter}"

log_head "Devuan KDE — color palette"

case "${1:-}" in
    --list|-l|help|--help|-h)
        usage
        exit 0
        ;;
    "")
        # no arg: interactive picker, darkmatter as the default answer.
        # This must stay in step with DEFAULT_PALETTE in 14-plasmaTheme.sh —
        # install.sh exports DEVMKDE_ASSUME_YES, so an unattended run of this
        # step used to land on the pre-migration Catppuccin palette instead of
        # the Darkmatter one the toolkit had just installed.
        list_palettes | while IFS='|' read -r id short name; do
            printf '%s\n' "  $id  ($name)"
        done
        if [ "${DEVMKDE_ASSUME_YES:-0}" = "1" ]; then
            log_info "DEVMKDE_ASSUME_YES set — applying the default palette instead of prompting."
            apply_palette "$DEFAULT_PALETTE"
            exit $?
        fi
        printf '\nPick a palette id (default: %s): ' "$DEFAULT_PALETTE"
        read -r chosen
        [ -n "$chosen" ] || chosen="$DEFAULT_PALETTE"
        apply_palette "$chosen"
        exit $?
        ;;
    *)
        # a palette id was given. Checked against the registry, not against a
        # directory: the palettes share one file now, so "[ -d themes/$1 ]" is
        # not a question the tree can answer, and it would have rejected every
        # palette in the kit.
        if ! list_palettes | cut -d'|' -f1 | grep -qx -- "$1"; then
            log_err "Unknown palette '$1'."
            usage
            exit 1
        fi
        apply_palette "$1"
        exit $?
        ;;
esac