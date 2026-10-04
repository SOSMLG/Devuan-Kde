#!/usr/bin/env bash
# DEVMKDE_DESC: The look: Darkmatter palette + Global Theme, accent, Konsole profile, icons, wallpaper
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# Plasma Theme — the toolkit's unified theming step
# -------------------------------------------------------
# The whole visual identity in one script:
#   1. Palette engine (Darkmatter by default): renders a Plasma color
#      scheme + Global Theme, Konsole scheme + profile, and the accent
#      from themes/palettes.sh via scripts/lib/theme.sh. This is
#      self-contained -- no network, no upstream theme required, and it
#      installs cleanly on a headless box.
#   2. The official Catppuccin Global Theme (app style, window decoration,
#      splash, cursor) from the pinned upstream release -- the shipped
#      default. This owns the Plasma look: widgets, aurorae window
#      decoration, cursor and splash all come from upstream, maintained by
#      Catppuccin. The palette above stays in charge of Konsole, the
#      wallpaper and the generated .colors file, and
#      scripts/lib/theme.sh re-applies Catppuccin after any later palette
#      swap so this look is what you keep.
#   3. A KDE-native icon set -- Papirus-Dark (Debian's own
#      papirus-icon-theme): every Plasma app ships a Papirus icon, uses
#      real KDE-friendly symlink handling, and tints dark properly.
#   4. A locally generated wallpaper (ImageMagick, no download), tinted
#      to whichever palette you picked.
#
# Why a pinned tarball instead of `git clone --depth=1`
# ----------------------------------------------------
# A shallow clone tracks whatever the default branch points at *today*:
# re-running this step months later silently installs a different theme,
# and a compromised or force-pushed upstream tag becomes a supply-chain
# hole. We fetch one immutable commit's tarball and verify its SHA256, so
# this step is reproducible forever. Override the pins only if you know
# why you need to:
#   CATPUCCIN_KDE_REF=6606b5179cfc1e9ba5c3b6b70e15c468e2dddca2
#   CATPUCCIN_KDE_SHA256=79ff6736afef26eb49a978392174801f2a6d28c7e328ac79499e10da8a55f1b9
#
# Upstream CLI note (catppuccin/kde v0.4.0 install.sh):
#   [-q|--quiet] [-c|--local-cursor <path>] [-n|--no-cursor]
#   <Flavour 1-4> <Accent 1-14> <WindowDec 1/2> <Debug|auto>
#     Flavour  1 = Mocha (of: mocha macchiato frappe latte)
#     Accent   5 = Red
#     WindowDec 2 = Classic (1 = Modern/aurorae, which the project's own
#                    install.sh warns has extra button-placement rules)
#     Debug    auto = auto-answer the remaining confirmation prompt, so the
#                    call is non-interactive under `-q`.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

# Upstream pins. Commit SHA, never a branch: branches float, commits don't.
CATPUCCIN_KDE_REF="${CATPUCCIN_KDE_REF:-6606b5179cfc1e9ba5c3b6b70e15c468e2dddca2}"
CATPUCCIN_KDE_SHA256="${CATPUCCIN_KDE_SHA256:-79ff6736afef26eb49a978392174801f2a6d28c7e328ac79499e10da8a55f1b9}"
CATPUCCIN_KDE_URL="https://codeload.github.com/catppuccin/kde/tar.gz/${CATPUCCIN_KDE_REF}"

# Icon theme id. Case-sensitive: this must match the installed directory name
# AND the index.theme Name= field exactly ("Papirus-Dark", not "papirus-dark").
ICON_THEME="${ICON_THEME:-Papirus-Dark}"

log_head "Plasma Theme"

if [ -z "$KWRITECONFIG" ]; then
    log_warn "Neither kwriteconfig6 nor kwriteconfig5 found — falling back to file writes only."
    log_warn "Default settings (Konsole profile, accent, icon theme) won't persist across logout."
    log_warn "On a real Plasma install this step should not be running; it works anyway."
fi

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Palette engine — Darkmatter is the default; every palette under
#    themes/ is selectable. This is the part that needs no network and no
#    upstream theme: templates in themes/_base/tpl/ are expanded with the
#    palette's colors into a .colors scheme, a Global Theme package
#    (metadata.json + colors symlink), and a Konsole scheme + profile.
# ---------------------------------------------------------------------------
DEFAULT_PALETTE="darkmatter"
PALETTE_CHOICE=""

if [ -f "$SCRIPT_DIR/lib/theme.sh" ]; then
    # shellcheck source=lib/theme.sh
    source "$SCRIPT_DIR/lib/theme.sh"

    AVAILABLE=$(list_palettes | cut -d'|' -f1)
    log_info "Palettes available: $(list_palettes | cut -d'|' -f3 | tr '\n' ', ' | sed 's/, $//')"

    if ask "Apply the Darkmatter palette (near-black, red accent)?"; then
        PALETTE_CHOICE="$DEFAULT_PALETTE"
    else
        log_info "Pick another palette id, or press Enter to skip theming for now."
        read -rp "   Palette id (blank = skip): " PALETTE_CHOICE
    fi
else
    log_err "lib/theme.sh not found — cannot render palettes."
    PALETTE_CHOICE=""
fi

PALETTE_APPLIED=0
if [ -n "$PALETTE_CHOICE" ]; then
    case "$AVAILABLE" in
        *"$PALETTE_CHOICE"*)
            if apply_palette "$PALETTE_CHOICE"; then
                PALETTE_APPLIED=1
                log_info "Open Konsole windows won't pick up the new scheme until you open a new tab."
            else
                log_err "Palette '$PALETTE_CHOICE' failed to apply."
            fi
            ;;
        *)
            log_err "'$PALETTE_CHOICE' isn't a known palette id. Known: $(echo "$AVAILABLE" | tr '\n' ' ')"
            ;;
    esac
else
    log_warn "Skipped the palette engine — no color scheme applied."
fi

# ---------------------------------------------------------------------------
# 2. Catppuccin Global Theme (optional) — application style, window
#    decoration, splash screen and cursor from upstream. Distinct from the
#    palette engine above: this is a full theme with its own widgets and
#    QML splash, not just colors.
# ---------------------------------------------------------------------------
CATPPUCCIN_OK=0
if ask "Also install the upstream Catppuccin Global Theme (Mocha, Red, Classic)?"; then
    install_pkgs "fetch/extract tooling" curl tar

    TARBALL="$WORK_DIR/catppuccin-kde.tar.gz"
    log_info "Fetching pinned catppuccin/kde @ ${CATPUCCIN_KDE_REF:0:12}..."
    if curl -fsSL -o "$TARBALL" "$CATPUCCIN_KDE_URL"; then
        if sha256_verify "$TARBALL" "$CATPUCCIN_KDE_SHA256"; then
            if tar xzf "$TARBALL" -C "$WORK_DIR"; then
                SRC="$(find "$WORK_DIR" -mindepth 1 -maxdepth 1 -type d -name 'kde-*' | head -1)"
                if [ -n "$SRC" ] && [ -f "$SRC/install.sh" ]; then
                    chmod +x "$SRC/install.sh"
                    if ( cd "$SRC" && run_as_user ./install.sh -q 1 5 2 auto ) >"$WORK_DIR/catppuccin.log" 2>&1; then
                        log_ok "Catppuccin Global Theme installed (Mocha, Red, Classic)."
                        CATPPUCCIN_OK=1
                    else
                        log_err "Upstream install.sh failed. Log: $WORK_DIR/catppuccin.log"
                        log_warn "The theme files may still have landed — check System Settings > Global Themes"
                        log_warn "for 'Catppuccin Mocha Red' either way."
                    fi
                else
                    log_err "Upstream tarball has no install.sh — unexpected layout, skipping."
                fi
            else
                log_err "Failed to extract the Catppuccin tarball."
            fi
        fi
    else
        log_err "Download failed — check your network/DNS. URL: $CATPUCCIN_KDE_URL"
    fi
else
    log_warn "Skipped the Catppuccin Global Theme — the generated palette theme above stays active instead."
fi

# Re-assert the look-and-feel package so the Catppuccin theme is actually
# selected — install.sh can succeed while the active LNF is still the old one.
if [ "$CATPPUCCIN_OK" -eq 1 ] && command_exists plasma-apply-lookandfeel; then
    LNF_ID=$(run_as_user plasma-apply-lookandfeel --list 2>/dev/null \
        | grep -i "catppuccin.*mocha.*red\|catppuccin-mocha-red" | head -1 | awk '{print $1}')
    if [ -n "$LNF_ID" ]; then
        run_as_user plasma-apply-lookandfeel --apply "$LNF_ID" >/dev/null 2>&1 \
            && log_ok "Re-asserted the look-and-feel package ($LNF_ID) to be sure it's active."
    else
        log_warn "Couldn't match a Catppuccin Mocha Red LNF id — set it in System Settings > Global Themes."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Icons — Papirus-Dark (Debian's papirus-icon-theme). The de-facto
#    icon theme for KDE: every Plasma app ships a Papirus icon, symlink
#    aliasing resolves properly under Plasma, and -Dark fits this look.
#
#    The id is CASE-SENSITIVE and must match the directory name and the
#    index.theme Name= exactly: "Papirus-Dark". Writing the all-lowercase
#    "papirus-dark" (as this step used to) names a theme that does not
#    exist, so Plasma silently falls back to whatever it liked before —
#    which is how this box ended up on the XFCE-era Zafiro-icons-Dark.
# ---------------------------------------------------------------------------
ICONS_OK=0
if ask "Install the Papirus-Dark KDE icon theme (Debian package) and set it active?"; then
    if check_repo_package papirus-icon-theme "main"; then
        install_pkgs "Papirus KDE icon theme" papirus-icon-theme && ICONS_OK=1
    else
        log_warn "Keeping the current icon theme."
    fi
fi

if [ "$ICONS_OK" -eq 1 ] && [ -n "$KWRITECONFIG" ]; then
    # Verify the id resolves to a real installed theme BEFORE writing it. A
    # typo or wrong case here is invisible: kdeglobals accepts any string and
    # Plasma quietly keeps the previous theme, so the only symptom is that
    # the setting never sticks.
    ICON_THEME_DIR=""
    for CAND in "/usr/share/icons/$ICON_THEME" "/usr/local/share/icons/$ICON_THEME" \
                "$HOME/.local/share/icons/$ICON_THEME"; do
        [ -f "$CAND/index.theme" ] && { ICON_THEME_DIR="$CAND"; break; }
    done

    if [ -z "$ICON_THEME_DIR" ]; then
        log_err "Icon theme '$ICON_THEME' is not installed (no index.theme) — not writing it."
        log_err "Refusing to write a theme id that can't resolve; Plasma would silently ignore it."
    else
        kwrite_user --file kdeglobals --group Icons --key Theme "$ICON_THEME"
        log_ok "Icon theme set in kdeglobals: $ICON_THEME ($ICON_THEME_DIR)"
        log_warn "Plasma 6 ships no live icon-theme setter (there is no plasma-changeicons"
        log_warn "binary), so this takes effect at the next plasmashell restart or login."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Wallpaper — generated locally (no download), a gradient in the
#    current palette's own background/mantle colors with an accent glow.
#    Skips cleanly if ImageMagick can't be installed rather than failing
#    the whole step over something purely cosmetic.
# ---------------------------------------------------------------------------
HOME_DIR="$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6)"
[ -n "$HOME_DIR" ] || HOME_DIR="$HOME"
BG_HEX="#${C_BG:-121113}"
MANTLE_HEX="#${C_MANTLE:-171618}"
ACCENT_HEX="#${C_ACCENT:-e75353}"
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
            log_warn "ImageMagick composite failed — skipping wallpaper (cosmetic only)."
            WALLPAPER_PATH=""
        fi
    else
        log_warn "ImageMagick unavailable — skipping wallpaper generation."
        WALLPAPER_PATH=""
    fi
else
    WALLPAPER_PATH=""
fi

# ---------------------------------------------------------------------------
# Wrap a folder of images you already have into a real Plasma wallpaper entry.
#
# The generated gradient above is a fallback, not a choice. Plasma 6 only lists
# a wallpaper folder in System Settings > Desktop > Wallpaper when it carries a
# metadata.json, so a plain folder of images can only ever be reached by typing
# its path. This builds that wrapper around a directory on THIS machine --
# nothing is downloaded and no image is bundled in the repo (the consistency
# checks forbid bundled binaries, and shipping other people's wallpapers would
# mean shipping their licence terms).
# ---------------------------------------------------------------------------
if declare -f install_wallpaper_package >/dev/null 2>&1 \
   && ask "Install an existing folder of images as a selectable Plasma wallpaper?" "N"; then
    WP_SRC=""
    if [ -n "${DEVMKDE_ASSUME_YES:-}" ]; then
        log_info "Non-interactive: set DEVMKDE_WALLPAPER_SRC=/path/to/images to use this."
    else
        read -rp "   Source directory (blank = skip): " WP_SRC
    fi
    [ -n "${WP_SRC:-}" ] || WP_SRC="${DEVMKDE_WALLPAPER_SRC:-}"
    if [ -z "$WP_SRC" ]; then
        log_info "No source directory given — skipping wallpaper package."
    else
        # Expand a leading ~ so the answer behaves the way it reads.
        case "$WP_SRC" in
            "~") WP_SRC="$HOME_DIR" ;;
            "~/"*) WP_SRC="$HOME_DIR/${WP_SRC#\~/}" ;;
        esac
        WP_PKG="$(install_wallpaper_package "$HOME_DIR" "$WP_SRC" "${PALETTE_CHOICE:-devuan-kde}" "${PALETTE_NAME:-$PALETTE_CHOICE}")"
        if [ -n "$WP_PKG" ] && ask "Set the first image from that folder as the current wallpaper?" "N"; then
            first_img="$(find "$WP_PKG/contents/images" -maxdepth 1 -type f 2>/dev/null | sort | head -1)"
            apply_wallpaper_image "$HOME_DIR" "$first_img" 4 || true
        fi
    fi
fi

# ---------------------------------------------------------------------------
# Apply the wallpaper to the current session. plasma-apply-wallpaperimage
# is the supported one-liner; falls back to a plasmashell dbus script.
# Off by default -- it changes the live desktop, which is a taste call.
# ---------------------------------------------------------------------------
if [ -n "$WALLPAPER_PATH" ] && [ -f "$WALLPAPER_PATH" ] && ask "Apply this wallpaper to your Plasma desktop now?" "N"; then
    if command_exists plasma-apply-wallpaperimage; then
        run_as_user plasma-apply-wallpaperimage "$WALLPAPER_PATH" >/dev/null 2>&1 \
            && log_ok "Wallpaper applied to all screens." \
            || log_warn "Could not apply it via plasma-apply-wallpaperimage — set it in System Settings > Wallpaper."
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
# Nudge KWin to re-read kwinrc (effects, decoration, compositing) so the
# look settles without a logout where KWin allows it.
# ---------------------------------------------------------------------------
for RECONFIG_CMD in "qdbus6 org.kde.KWin /KWin reconfigure" "qdbus org.kde.KWin /KWin reconfigure"; do
    # shellcheck disable=SC2086
    run_as_user $RECONFIG_CMD >/dev/null 2>&1 && break
done

echo -e "${GREEN}Plasma theme step complete.${NC}"
log_warn "Log out and back in for anything that didn't visibly apply live to fully settle."
log_info "Swap palettes any time: 'bash $0', or pick a Global Theme in System Settings > Appearance."