#!/usr/bin/env bash
# =======================================================
# graphitePlasma.sh -- local Graphite Amber Plasma theming utility
# -------------------------------------------------------
# A standalone re-apply of the shipped look, using only in-tree assets:
#   1. Palette engine: Konsole scheme + profile, Plasma color scheme,
#      Global Theme and accent, rendered from themes/palettes.sh by
#      scripts/lib/theme.sh. No upstream theme and no network fetch.
#   2. Papirus-Dark icons (Debian's papirus-icon-theme).
#   3. A locally generated wallpaper in the palette's own colors.
#
# 14-plasmaTheme.sh runs the same engine during install; this utility is
# for re-applying it later without going through the full step list.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"
# shellcheck source=lib/theme.sh
source "$SCRIPT_DIR/lib/theme.sh"

require_not_root
log_head "Graphite Amber Plasma"

if [ -z "$KWRITECONFIG" ]; then
    log_warn "Neither kwriteconfig6 nor kwriteconfig5 found - writing files only."
    log_warn "The generated schemes still land on disk for the next Plasma login."
fi

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Palette engine -- Graphite Amber is the default; any registered palette
#    can be chosen at the prompt. Everything renders from one source of truth.
# ---------------------------------------------------------------------------
DEFAULT_PALETTE="${DEVMKDE_DEFAULT_PALETTE:-graphite-amber}"
PALETTE_CHOICE=""

log_info "Palettes available: $(list_palettes | cut -d'|' -f3 | tr '\n' ',' | sed 's/,$//')"
if ask "Apply the Graphite Amber palette (graphite surfaces, amber accent)?"; then
    PALETTE_CHOICE="$DEFAULT_PALETTE"
else
    read -rp "   Palette id (blank = skip): " PALETTE_CHOICE
fi

PALETTE_APPLIED=0
if [ -n "$PALETTE_CHOICE" ]; then
    if list_palettes | cut -d'|' -f1 | grep -qx -- "$PALETTE_CHOICE"; then
        apply_palette "$PALETTE_CHOICE" || { log_err "Palette apply failed."; exit 1; }
        PALETTE_APPLIED=1
        log_info "Existing open Konsole windows need a new tab/window to pick this up."
    else
        log_err "Unknown palette '$PALETTE_CHOICE' - leaving the current one alone."
    fi
else
    log_warn "Skipped the palette engine."
fi

# ---------------------------------------------------------------------------
# 2. Icons -- Papirus-Dark. The id is case-sensitive and must match the
#    installed directory and index.theme Name= exactly.
# ---------------------------------------------------------------------------
ICON_THEME="${ICON_THEME:-Papirus-Dark}"
ICONS_OK=0
if ask "Install the Papirus-Dark KDE icon theme (Debian package) and set it active?"; then
    if check_repo_package papirus-icon-theme "main"; then
        install_pkgs "Papirus KDE icon theme" papirus-icon-theme && ICONS_OK=1
    else
        log_warn "papirus-icon-theme is not in the configured repos - keeping the current icons."
    fi
fi

if [ "$ICONS_OK" -eq 1 ]; then
    ICON_THEME_DIR=""
    for CAND in "/usr/share/icons/$ICON_THEME" "/usr/local/share/icons/$ICON_THEME" \
                "$HOME/.local/share/icons/$ICON_THEME"; do
        [ -f "$CAND/index.theme" ] && { ICON_THEME_DIR="$CAND"; break; }
    done
    if [ -n "$ICON_THEME_DIR" ] && [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file kdeglobals --group Icons --key Theme "$ICON_THEME"
        log_ok "Icon theme set in kdeglobals: $ICON_THEME"
    else
        log_warn "Icon theme not set - install Papirus-Dark and re-run, or set it in System Settings."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Wallpaper -- generated locally with the palette's canvas/mantle colors
#    and an amber glow. No download and no bundled binary asset.
# ---------------------------------------------------------------------------
HOME_DIR="$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
BG_HEX="#${C_BG:-16181d}"
MANTLE_HEX="#${C_MANTLE:-1c1f24}"
ACCENT_HEX="#${C_ACCENT:-e8a33d}"
WALLPAPER_PATH="$HOME_DIR/.local/share/backgrounds/devuan-kde-${PALETTE_CHOICE:-plain}.png"

if [ "$PALETTE_APPLIED" -eq 1 ] && ask "Generate a wallpaper in this palette (local, no download)?"; then
    if ! command_exists convert; then
        install_pkgs "ImageMagick" imagemagick
    fi
    if command_exists convert; then
        run_as_user mkdir -p "$(dirname "$WALLPAPER_PATH")"
        if run_as_user convert -size 1920x1080 "gradient:${BG_HEX}-${MANTLE_HEX}" \
            \( -size 1920x1080 xc:none -fill "$ACCENT_HEX" -draw "circle 1600,900 1900,900" -blur 0x200 \) \
            -compose over -composite "$WALLPAPER_PATH"; then
            log_ok "Wallpaper generated at $WALLPAPER_PATH"
        else
            log_warn "ImageMagick composite failed - skipping wallpaper (cosmetic only)."
            WALLPAPER_PATH=""
        fi
    else
        log_warn "ImageMagick unavailable - skipping wallpaper generation."
        WALLPAPER_PATH=""
    fi
else
    WALLPAPER_PATH=""
fi

# Apply live only when asked: changing the visible desktop is a taste call.
if [ -n "$WALLPAPER_PATH" ] && [ -f "$WALLPAPER_PATH" ] \
   && ask "Apply this wallpaper to your Plasma desktop now?" "N"; then
    if command_exists plasma-apply-wallpaperimage; then
        run_as_user plasma-apply-wallpaperimage "$WALLPAPER_PATH" >/dev/null 2>&1 \
            && log_ok "Wallpaper applied to all screens." \
            || log_warn "Could not apply the wallpaper - set it manually in System Settings."
    else
        log_info "Set $WALLPAPER_PATH as the wallpaper when you next log in."
    fi
fi

for RECONFIG_CMD in "qdbus6 org.kde.KWin /KWin reconfigure" "qdbus org.kde.KWin /KWin reconfigure"; do
    # shellcheck disable=SC2086
    run_as_user $RECONFIG_CMD >/dev/null 2>&1 && break
done

echo -e "${GREEN}Graphite Amber Plasma step complete.${NC}"
log_info "Re-run this utility (or use 46-applyThemes.sh) to change the look later."
