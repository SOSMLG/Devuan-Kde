#!/usr/bin/env bash
# =======================================================
# Catppuccin Plasma — the toolkit's unified theming step
# -------------------------------------------------------
# The whole visual identity in one script:
#   1. Catppuccin Global Theme (app style, color scheme, window
#      decoration, splash, cursor) from the official catppuccin/kde
#      installer, prebuilt by their own CI.
#   2. A proper KDE-native icon set — Papirus-Dark (Debian's own
#      papirus-icon-theme), the de-facto icon theme among Plasma users:
#      it ships every Plasma app icon, uses real KDE-friendly symlink
#      handling, and tinters dark. (Replaces the earlier Catppuccin-SE
#      "Local" build, which is a GTK-leaning Papirus port whose symlinked
#      app-icon aliases consistently break under Plasma.)
#   3. The palette engine: Konsole scheme + profile + Plasma color scheme
#      + accent, rendered from themes/mocha-red by scripts/lib/theme.sh.
#   4. A locally generated Catppuccin-toned wallpaper (ImageMagick,
#      no download).
#
# catppuccin/kde's own install.sh handles Global Theme + colorscheme +
# window decoration + cursor theme all in one documented, verified call
# (README example: `./install.sh 1 13 2 auto` = Mocha, Blue, Classic,
# auto-confirm). This script uses the equivalent for Mocha + RED:
#
#   Flavour index 1  = Mocha       (of: mocha macchiato frappe latte)
#   Accent  index 5  = Red         (of: rosewater flamingo pink mauve
#                                       RED maroon peach yellow green
#                                       teal sky sapphire blue lavender)
#   WinDec  index 2  = Classic     (index 1 = "Modern"/aurorae, which
#                                    the project's own install.sh warns
#                                    has extra button-placement rules —
#                                    Classic avoids that class of issue)
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
echo -e "${CYAN} Catppuccin Plasma (Mocha, Red)${NC}"
echo -e "${CYAN}=========================================================${NC}"

if [ -z "$KWRITECONFIG" ]; then
    log_err "Neither kwriteconfig6 nor kwriteconfig5 found — this needs to run on an actual Plasma install."
    exit 1
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Global Theme — application style, color scheme, window decoration,
#    splash screen, and cursor theme, all from catppuccin/kde's own
#    install.sh in one call.
# ---------------------------------------------------------------------------
GLOBAL_THEME_OK=0
if ask "Install the Catppuccin Global Theme (Mocha, Red accent, Classic window decoration)?"; then
    install_pkgs "fetch/extract tooling" git curl unzip

    if git clone --depth=1 https://github.com/catppuccin/kde.git "$WORK_DIR/catppuccin-kde" 2>/tmp/catppuccin-kde-clone.log; then
        cd "$WORK_DIR/catppuccin-kde"
        chmod +x install.sh

        # `auto` at the end auto-answers install.sh's own "Install X Y with
        # Z window decorations? [y/N]" confirmation prompt — needed for
        # this to run non-interactively.
        if run_as_user ./install.sh -q 1 5 2 auto >/tmp/catppuccin-kde-install.log 2>&1; then
            log_ok "Catppuccin Global Theme installed and applied (Mocha, Red, Classic)."
            GLOBAL_THEME_OK=1
        else
            log_err "install.sh failed. Log: /tmp/catppuccin-kde-install.log"
            log_warn "Falling back to a plain 'plasma-apply-lookandfeel' attempt in case the theme"
            log_warn "files landed but the apply step tripped — check System Settings > Global Themes"
            log_warn "for 'Catppuccin Mocha Red' either way."
        fi
        cd "$WORK_DIR"
    else
        log_err "Clone failed — check your network/DNS. Log: /tmp/catppuccin-kde-clone.log"
    fi
else
    log_warn "Skipped the Global Theme."
fi

if [ "$GLOBAL_THEME_OK" -eq 1 ] && command_exists plasma-apply-lookandfeel; then
    LNF_ID=$(run_as_user plasma-apply-lookandfeel --list 2>/dev/null | grep -i "catppuccin.*mocha.*red\|catppuccin-mocha-red" | head -1 | awk '{print $1}')
    if [ -n "$LNF_ID" ]; then
        run_as_user plasma-apply-lookandfeel --apply "$LNF_ID" >/dev/null 2>&1 \
            && log_ok "Re-asserted the look-and-feel package ($LNF_ID) to be sure it's active."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Icons — Papirus-Dark (Debian's papirus-icon-theme). The de-facto
#    icon theme for KDE: every Plasma app ships a Papirus icon, symlink
#    aliasing resolves properly under Plasma, and the -Dark variant fits
#    the Catppuccin look. Replaces the earlier Catppuccin-SE/SE-Local
#    download (a GTK-leaning Papirus port whose symlinked app-icon
#    aliases were dropped by the old Local builder, leaving generic
#    icons in the launcher/taskbar — the exact thing reported broken).
# ---------------------------------------------------------------------------
ICONS_OK=0
if ask "Install the Papirus-Dark KDE icon theme (Debian package) and set it active?"; then
    if apt-cache show papirus-icon-theme >/dev/null 2>&1; then
        install_pkgs "Papirus KDE icon theme" papirus-icon-theme
        ICONS_OK=1
    else
        log_warn "papirus-icon-theme isn't in your configured repos — keeping the current icon theme."
    fi
fi

if [ "$ICONS_OK" -eq 1 ]; then
    kwrite_user --file kdeglobals --group Icons --key Theme "papirus-dark"
    if command_exists plasma-changeicons; then
        run_as_user plasma-changeicons "papirus-dark" >/dev/null 2>&1 \
            && log_ok "Icon theme applied live: papirus-dark" \
            || log_warn "Icon theme set in kdeglobals (papirus-dark) — takes effect at next login."
    else
        log_warn "Icon theme set in kdeglobals (papirus-dark) — takes effect at next login."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Palette engine — Konsole "Catppuccin Red" profile + the matching
#    Plasma color scheme and accent, both rendered from themes/mocha-red/
#    by scripts/lib/theme.sh (single palette source of truth; Konsole
#    ANSI colors, .colors groups and the accent all derive from it).
# ---------------------------------------------------------------------------
if ask "Create the 'Catppuccin Red' Konsole profile + Plasma color scheme (palette engine)?"; then
    # shellcheck source=lib/theme.sh
    source "$SCRIPT_DIR/lib/theme.sh"
    apply_palette "mocha-red" || { log_err "Palette apply failed."; exit 1; }
    log_info "Existing open Konsole windows won't pick this up until you open a new tab/window."
else
    log_warn "Skipped the palette engine step."
fi

# ---------------------------------------------------------------------------
# 4. Wallpaper — generated locally (no download needed), a Catppuccin
#    Mocha-toned gradient with a red accent glow, carries over the
#    ImageMagick generator from the retired mintLookPlasma.sh. Skips
#    cleanly if ImageMagick isn't present rather than force-installing it.
# ---------------------------------------------------------------------------
HOME_DIR="$(getent passwd "$ACTUAL_USER" | cut -d: -f6)"
WALLPAPER_PATH="$HOME_DIR/.local/share/backgrounds/devuan-kde-catppuccin.png"
if ask "Generate a Catppuccin Mocha-toned wallpaper (local, no download — needs ImageMagick)?"; then
    if ! command_exists convert; then
        install_pkgs "ImageMagick" imagemagick
    fi
    if command_exists convert; then
        run_as_user mkdir -p "$(dirname "$WALLPAPER_PATH")"
        # Mocha base fading to mantle, with the Catppuccin red accent glow.
        if run_as_user convert -size 1920x1080 gradient:'#1e1e2e'-'#181825' \
            \( -size 1920x1080 xc:none -fill '#f38ba8' -draw "circle 1600,900 1900,900" -blur 0x200 \) \
            -compose over -composite "$WALLPAPER_PATH"; then
            log_ok "Wallpaper generated at $WALLPAPER_PATH"
        else
            log_warn "ImageMagick composite failed — skipping wallpaper (cosmetic only)."
            WALLPAPER_PATH=""
        fi
    else
        log_warn "ImageMagick unavailable — skipping wallpaper generation."
        WALLPAPER_PATH=""
    fi
fi

# ---------------------------------------------------------------------------
# Apply the wallpaper to the current Plasma session. plasma-apply-
# wallpaperimage (Plasma 5.18+) is the supported one-liner; falls back
# to a plasmashell dbus script on older versions. Not applied by default
# — it changes the live desktop, which is a taste call.
# ---------------------------------------------------------------------------
if [ -n "$WALLPAPER_PATH" ] && [ -f "$WALLPAPER_PATH" ] && ask "Apply this wallpaper to your Plasma desktop now?" "N"; then
    if command_exists plasma-apply-wallpaperimage; then
        run_as_user plasma-apply-wallpaperimage "$WALLPAPER_PATH" >/dev/null 2>&1 \
            && log_ok "Wallpaper applied to all screens." \
            || log_warn "Could not apply the wallpaper via plasma-apply-wallpaperimage — set it manually in System Settings > Wallpaper."
    elif command_exists qdbus && pgrep -x plasmashell >/dev/null 2>&1; then
        run_as_user qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "{
            var desktops = desktops();
            for (var i = 0; i < desktops.length; i++) {
                desktops[i].wallpaperPlugin = 'org.kde.image';
                desktops[i].currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
                desktops[i].writeConfig('Image', 'file://$WALLPAPER_PATH');
            }
        }" >/dev/null 2>&1 && log_ok "Wallpaper applied to all desktops via plasmashell." \
            || log_warn "Could not apply the wallpaper — set it manually in System Settings > Wallpaper."
    else
        log_warn "No session / wallpaper tooling available — apply $WALLPAPER_PATH manually later."
    fi
fi

# ---------------------------------------------------------------------------
# Apply live where possible
# ---------------------------------------------------------------------------
for RECONFIG_CMD in "qdbus6 org.kde.KWin /KWin reconfigure" "qdbus org.kde.KWin /KWin reconfigure"; do
    # shellcheck disable=SC2086
    run_as_user $RECONFIG_CMD >/dev/null 2>&1 && break
done

echo -e "${GREEN}Catppuccin Plasma step complete.${NC}"
log_warn "Log out and back in for anything that didn't visibly apply live to fully settle."
log_info "This is the toolkit's theming step. Re-run it (or swap themes in System Settings >"
log_info "Appearance > Global Themes and Icons > Icons) to change the look at any time."
