#!/usr/bin/env bash
# =======================================================
# Catppuccin Plasma — the toolkit's theming step
# -------------------------------------------------------
# Catppuccin Mocha, Red accent — the same palette/identity used across
# this toolkit's XFCE sibling project. Uses the OFFICIAL catppuccin/kde
# Global Theme installer (github.com/catppuccin/kde) — prebuilt/pre-
# rendered by their own CI (Whiskers), so unlike a from-source KDE
# theme there's no compile step here at all.
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
# 2. Icons — ljmill/catppuccin-icons "Catppuccin-SE", same source and same
#    memory-optimized "Local" variant as this toolkit's XFCE sibling.
#    catppuccin/kde's Global Theme doesn't ship app icons itself (that's
#    a separate concern in the Catppuccin ecosystem), so this fills that
#    gap the same way.
# ---------------------------------------------------------------------------
ICONS_DIR="$(getent passwd "$ACTUAL_USER" | cut -d: -f6)/.local/share/icons"
ICON_BASE="$ICONS_DIR/Catppuccin-SE"
ACTIVE_ICON_THEME=""
if ask "Install the Catppuccin-SE icon set (ljmill/catppuccin-icons)?"; then
    run_as_user mkdir -p "$ICONS_DIR"
    log_info "Resolving latest release..."
    ICON_URL=$(curl -fsSL https://api.github.com/repos/ljmill/catppuccin-icons/releases/latest \
        | grep -oP '"browser_download_url":\s*"\K[^"]+Catppuccin-SE\.tar\.bz2' | head -1)
    [ -z "$ICON_URL" ] && { log_warn "GitHub API lookup failed, using a fallback known-good release URL."; \
        ICON_URL="https://github.com/ljmill/catppuccin-icons/releases/download/v0.2.0/Catppuccin-SE.tar.bz2"; }

    ICON_TARBALL="$WORK_DIR/Catppuccin-SE.tar.bz2"
    if curl -fsSL --progress-bar -o "$ICON_TARBALL" "$ICON_URL"; then
        rm -rf "$ICON_BASE"
        if tar -xjf "$ICON_TARBALL" -C "$ICONS_DIR"; then
            if [ ! -d "$ICON_BASE" ]; then
                FOUND=$(find "$ICONS_DIR" -maxdepth 2 -type d -iname "Catppuccin-SE" | head -1)
                [ -n "$FOUND" ] && [ "$FOUND" != "$ICON_BASE" ] && mv "$FOUND" "$ICON_BASE"
            fi
            chown -R "$ACTUAL_USER" "$ICON_BASE" 2>/dev/null || true
            log_ok "Catppuccin-SE installed to $ICON_BASE ($(du -sh "$ICON_BASE" 2>/dev/null | cut -f1))"

            # Lean local variant, same trick as the XFCE sibling: keep the
            # small UI-chrome categories wholesale, only pull app icons
            # for software actually installed, trim Inherits= to
            # Breeze+hicolor (KDE's own base, not Adwaita, since Breeze
            # is what's guaranteed present on a KDE system).
            LOCAL_ICON_DIR="$ICONS_DIR/Catppuccin-SE-Local"
            rm -rf "$LOCAL_ICON_DIR"
            run_as_user mkdir -p "$LOCAL_ICON_DIR"

            DESIRED_ICONS="$WORK_DIR/desired-icons.txt"
            grep -h '^Icon=' /usr/share/applications/*.desktop \
                "$(getent passwd "$ACTUAL_USER" | cut -d: -f6)/.local/share/applications"/*.desktop 2>/dev/null \
                | sed 's/^Icon=//' | sort -u > "$DESIRED_ICONS"
            cat >> "$DESIRED_ICONS" << 'EOF'
plasmashell
systemsettings
konsole
dolphin
kate
firefox
firefox-esr
vlc
EOF
            sort -u -o "$DESIRED_ICONS" "$DESIRED_ICONS"
            log_info "Matching against $(wc -l < "$DESIRED_ICONS") installed app icon names..."

            KEEP_CATS=(places status actions categories devices mimetypes emblems panel preferences)
            APPS_COPIED=0
            for size_dir in "$ICON_BASE"/*/; do
                [ -d "$size_dir" ] || continue
                size_name=$(basename "$size_dir")
                [ "$size_name" = "cursors" ] && continue
                for cat in "${KEEP_CATS[@]}"; do
                    if [ -d "${size_dir}${cat}" ]; then
                        mkdir -p "$LOCAL_ICON_DIR/$size_name"
                        cp -r "${size_dir}${cat}" "$LOCAL_ICON_DIR/$size_name/" 2>/dev/null
                    fi
                done
                if [ -d "${size_dir}apps" ]; then
                    mkdir -p "$LOCAL_ICON_DIR/$size_name/apps"
                    while IFS= read -r -d '' f; do
                        base="$(basename "$f")"; name="${base%.*}"
                        if grep -qxF "$name" "$DESIRED_ICONS"; then
                            cp "$f" "$LOCAL_ICON_DIR/$size_name/apps/" 2>/dev/null
                            APPS_COPIED=$((APPS_COPIED + 1))
                        fi
                    done < <(find "${size_dir}apps" -maxdepth 1 -type f -print0 2>/dev/null)
                fi
            done

            if [ -f "$ICON_BASE/index.theme" ]; then
                cp "$ICON_BASE/index.theme" "$LOCAL_ICON_DIR/index.theme"
                sed -i 's/^Inherits=.*/Inherits=breeze,hicolor/' "$LOCAL_ICON_DIR/index.theme"
                sed -i 's/^Name=.*/Name=Catppuccin-SE-Local/' "$LOCAL_ICON_DIR/index.theme"
            fi
            chown -R "$ACTUAL_USER" "$LOCAL_ICON_DIR" 2>/dev/null || true
            command_exists gtk-update-icon-cache && gtk-update-icon-cache -f -t "$LOCAL_ICON_DIR" 2>/dev/null || true

            log_ok "Catppuccin-SE-Local built: $APPS_COPIED matched app icons."
            log_ok "Size: $(du -sh "$ICON_BASE" 2>/dev/null | cut -f1) (full, kept as fallback) -> $(du -sh "$LOCAL_ICON_DIR" 2>/dev/null | cut -f1) (Local, active)."
            log_warn "Anything not in your installed-apps list falls back to Breeze — rerun this script"
            log_warn "after installing new apps to refresh it."
            ACTIVE_ICON_THEME="Catppuccin-SE-Local"
        else
            log_err "Extraction failed."
        fi
    else
        log_err "Icon download failed. Skipping icon theme."
    fi
fi

if [ -n "$ACTIVE_ICON_THEME" ]; then
    kwrite_user --file kdeglobals --group Icons --key Theme "$ACTIVE_ICON_THEME"
    if command_exists plasma-changeicons; then
        run_as_user plasma-changeicons "$ACTIVE_ICON_THEME" >/dev/null 2>&1 \
            && log_ok "Icon theme applied live: $ACTIVE_ICON_THEME" \
            || log_warn "Icon theme set in kdeglobals — takes effect at next login if it didn't apply live."
    else
        log_warn "Icon theme set in kdeglobals ($ACTIVE_ICON_THEME) — takes effect at next login."
    fi
fi

# ---------------------------------------------------------------------------
# 3. Konsole "Catppuccin Red" profile — self-authored (not a downloaded
#    file, so there's
#    nothing here whose contents you can't read in two seconds). Uses the
#    official Catppuccin Mocha terminal ANSI mapping, RGB triples (Konsole
#    colorscheme files use decimal R,G,B, not hex).
# ---------------------------------------------------------------------------
if ask "Create a 'Catppuccin Red' Konsole profile and set it as default?"; then
    HOME_DIR=$(getent passwd "$ACTUAL_USER" | cut -d: -f6)
    KONSOLE_DIR="$HOME_DIR/.local/share/konsole"
    run_as_user mkdir -p "$KONSOLE_DIR"

    SCHEME_FILE="$KONSOLE_DIR/CatppuccinRed.colorscheme"
    run_as_user tee "$SCHEME_FILE" > /dev/null << 'EOF'
[General]
Description=Catppuccin Red
Opacity=0.92
Wallpaper=

[Background]
Color=30,30,46

[BackgroundIntense]
Color=30,30,46

[Foreground]
Color=205,214,244

[ForegroundIntense]
Color=205,214,244

[Color0]
Color=69,71,90
[Color0Intense]
Color=88,91,112

[Color1]
Color=243,139,168
[Color1Intense]
Color=243,139,168

[Color2]
Color=166,227,161
[Color2Intense]
Color=166,227,161

[Color3]
Color=249,226,175
[Color3Intense]
Color=249,226,175

[Color4]
Color=137,180,250
[Color4Intense]
Color=137,180,250

[Color5]
Color=245,194,231
[Color5Intense]
Color=245,194,231

[Color6]
Color=148,226,213
[Color6Intense]
Color=148,226,213

[Color7]
Color=186,194,222
[Color7Intense]
Color=166,173,200
EOF
    log_ok "Colorscheme written to $SCHEME_FILE"

    PROFILE_FILE="$KONSOLE_DIR/CatppuccinRed.profile"
    run_as_user tee "$PROFILE_FILE" > /dev/null << 'EOF'
[Appearance]
ColorScheme=CatppuccinRed
Font=Monospace,11,-1,5,50,0,0,0,0,0

[General]
Name=Catppuccin Red
Parent=FALLBACK/
EOF
    log_ok "Profile written to $PROFILE_FILE"

    kwrite_user --file konsolerc --group "Desktop Entry" --key DefaultProfile "CatppuccinRed.profile" \
        && log_ok "Set as the default Konsole profile."
    log_info "Existing open Konsole windows won't pick this up until you open a new tab/window."
else
    log_warn "Skipped the Konsole profile."
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
log_info "Appearance > Global Themes) to change the look at any time."
