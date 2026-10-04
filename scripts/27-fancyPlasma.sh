#!/usr/bin/env bash
# DEVMKDE_DESC: Desktop polish: Noto Sans font, borderless maximize, blur, switcher, Night Color, effects
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# Fancy Plasma — theming/productivity pass for KDE Plasma
# -------------------------------------------------------
# The Plasma port of the sibling toolkit's "fancy Cinnamon" script.
# Everything here is either:
#   (a) a built-in KWin/Plasma feature, toggled via kwinrc with kwriteconfig
#       — zero extra dependency, zero third-party code, or
#   (b) a single opt-in third-party KWin effect (Burn My Windows) pulled
#       straight from its upstream GitHub releases, installed to your user
#       KWin effects dir — same Home-dir-only, no-system-repo philosophy as
#       everything else here.
#
# What's deliberately left out: browsing gnome-look/KDE Store visually for
# a specific community theme/icon/cursor pack (no stable way to script "the
# exact one shown in a video" reliably), and the sponsor segment.
#
# KWin reload helper: KWin picks up kwinrc changes on
# 'qdbus org.kde.KWin /KWin reconfigure'; fonts need KGlobalSettings
# reparse + often a re-login. Both are attempted below where relevant.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Fancy Plasma"
log_info "Session: ${DEVMKDE_SESSION:-unknown} (Wayland/X11 agnostic configs)"

# qdbus binary — qdbus6 on Plasma 6, qdbus (Qt5) elsewhere.
QDBUS=""
if command_exists qdbus6; then
    QDBUS="qdbus6"
elif command_exists qdbus; then
    QDBUS="qdbus"
fi

kwin_reload() {
    if [ -n "$QDBUS" ]; then
        run_as_user "$QDBUS" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
    fi
}

# ---------------------------------------------------------------------------
# 1. Custom UI font — Noto Sans, from Debian's fonts-noto-core.
#
#    This used to install Inter by downloading the variable font from
#    google/fonts on GitHub. Inter reads as too heavy on a dark desktop:
#    it has a very high x-height and a dark colour/stroke weight, which
#    fontconfig's subpixel rendering (rgba=rgb + hintstyle=hintslight)
#    then emboldens a little further. Users kept reading it as "bold"
#    even though the weight field was 400/Regular. Noto Sans has a
#    normal-weight colour at the same pt size, ships a full
#    Thin..Black ladder as static TTFs, and is already the fontconfig
#    sans-serif default on this box -- so it also needs no download.
#
#    Plasma font string format (comma separated, no spaces):
#      family,pointSize,pixelSize,styleHint,weight,stretch,bitmap,kerning,...
#    pixelSize -1 means "use pointSize". Field 5 is the weight, written
#    the CSS way (100..900, 400 = Regular).
# ---------------------------------------------------------------------------
UI_FONT="${UI_FONT:-Noto Sans}"

# font_available <family> — true only if fontconfig resolves <family> to that
# same family. A family that isn't installed silently resolves to the
# sans-serif default instead (fc-match "No Such Font" -> "Noto Sans" on a box
# where Noto is the default), so "did it resolve" has to be an EQUALITY test,
# not an exit-status test — the default font matches, everything else doesn't.
font_available() {
    local want="$1" got
    got="$(fc-match "$want" -f '%{family[0]}' 2>/dev/null | head -1)"
    [ -n "$got" ] && [ "${got,,}" = "${want,,}" ]
}

if ask "Use $UI_FONT as your Plasma UI font?"; then
    if ! command_exists fc-match; then
        log_warn "fc-match not found — can't verify $UI_FONT; skipping the font change."
    elif ! font_available "$UI_FONT"; then
        log_info "$UI_FONT not installed yet — installing fonts-noto-core..."
        install_pkgs "$UI_FONT (fonts-noto-core)" fonts-noto-core
        fc-cache -f >/dev/null 2>&1 || true
    fi

    if font_available "$UI_FONT"; then
        log_ok "$UI_FONT resolves to $(fc-match "$UI_FONT" -f '%{file} (%{family[0]} %{style[0]})\n' 2>/dev/null)"
        kwrite_user --file kdeglobals --group General --key font "$UI_FONT,10,-1,5,400,0,0,0,0,0"
        kwrite_user --file kdeglobals --group General --key activeFont "$UI_FONT,10,-1,5,400,0,0,0,0,0"
        kwrite_user --file kdeglobals --group General --key smallestReadableFont "$UI_FONT,8,-1,5,400,0,0,0,0,0"
        log_ok "$UI_FONT set as the Plasma UI font (weight 400 / Regular)."
        # Plasma 6 retired org.kde.KGlobalSettings entirely — the service is
        # simply absent, so calling it reparseConfiguration fails with
        # "Service ... does not exist". KConfig already picked the change
        # up via kwriteconfig; plasmashell and any running app need their own
        # restart. Only try the nudge if the service really is there.
        if [ -n "$QDBUS" ] && run_as_user "$QDBUS" org.kde.KGlobalSettings /KGlobalSettings \
                reparseConfiguration >/dev/null 2>&1; then
            log_info "KGlobalSettings reparse requested — running apps may still need a restart."
        else
            log_info "Config written. Restart plasmashell (or log out/in) for the new font to show."
        fi
    else
        log_warn "fontconfig can't resolve '$UI_FONT' — leaving the current font alone."
    fi
fi

# ---------------------------------------------------------------------------
# 2. Borderless maximized windows — hide the titlebar when maximized
#    (the "annoying system title bar gone" moment from the walkthroughs).
#    KWin built-in; hold Alt + left-click-drag to move a borderless window.
# ---------------------------------------------------------------------------
if ask "Hide the titlebar on maximized windows (double-click is a free maximize toggle)?"; then
    kwrite_user --file kwinrc --group Windows --key BorderlessMaximizedWindows true
    kwin_reload
    log_ok "Borderless maximized windows enabled (Alt+drag still moves them)."
fi

# ---------------------------------------------------------------------------
# 3. Window blur — blurs the panel/menu/translucent windows to blend with
#    your wallpaper, same effect as the walkthroughs' blur extension pick.
# ---------------------------------------------------------------------------
if ask "Enable the Blur window effect?"; then
    # Plasma 6 folded the old kwineffectsrc into kwinrc: an effect is a KWin
    # plugin, and plugin state lives under [Plugins] in kwinrc. Writing to
    # kwineffectsrc still "succeeds" but KWin never reads it back.
    kwrite_user --file kwinrc --group Plugins --key blurEnabled true
    kwin_reload
    log_ok "Blur enabled (any translucent plasma panel/window now blurs)."
fi

# ---------------------------------------------------------------------------
# 4. Alt-Tab switcher style -> Coverflow (KWin built-in, no third-party
#    task switcher config needed).
# ---------------------------------------------------------------------------
if ask "Switch Alt-Tab to the Coverflow switcher style?"; then
    # KWin 6 replaced [TabBox] Mode/DesktopMode with a single LayoutName
    # holding an enum: compact | big_icons | coverswitch | flipswitch |
    # sidebar | thumbnail_grid. There is no "coverflow" and no "composeonboard"
    # -- writing either leaves Alt-Tab on the default layout while the script
    # reports success. Coverswitch is the 3D one people mean by Coverflow.
    kwrite_user --file kwinrc --group TabBox --key LayoutName coverswitch
    kwin_reload
    log_ok "Alt-Tab style set to coverswitch (the 3D Coverflow look) — tweak in System Settings > Window Management."
fi

# ---------------------------------------------------------------------------
# 5. Night Color — reduces blue light in the evening, follows
#    sunset/sunrise like Cinnamon's Night Light.
# ---------------------------------------------------------------------------
if ask "Enable Night Color (automatic sunset/sunrise schedule)?"; then
    kwrite_user --file kwinrc --group NightColor --key Active true
    kwrite_user --file kwinrc --group NightColor --key Mode Auto
    kwrite_user --file kwinrc --group NightColor --key LastManualOffset 0
    kwrite_user --file kwinrc --group NightColor --key LastLatitude "0.000000"
    kwrite_user --file kwinrc --group NightColor --key LastLongitude "0.000000"
    kwin_reload
    log_ok "Night Color enabled (automatic schedule). Adjust latitude/longitude or times in System Settings > Display and Monitor > Night Color."
fi

# ---------------------------------------------------------------------------
# 6. Magic Lamp — genie-style minimize animation. Built into KWin since
#    forever; just an effect toggle, no third-party code.
# ---------------------------------------------------------------------------
if ask "Enable the Magic Lamp minimize animation?" "N"; then
    kwrite_user --file kwinrc --group Plugins --key magicLampEnabled true
    kwin_reload
    log_ok "Magic Lamp enabled."
fi

# ---------------------------------------------------------------------------
# 7. Burn My Windows (opt-in) — animated window open/close effects, the
#    KWin port of Schneegans' GNOME extension. Downloads the prebuilt
#    effects tarball from the project's GitHub releases into your user
#    KWin effects dir — no system package, no KDE Store account. Enable
#    whatever you like afterward in System Settings > Desktop Effects.
#    Needs KWin 5.25+ (Devuan's Plasma 5.27 qualifies).
# ---------------------------------------------------------------------------
if ask "Download Burn My Windows window open/close effects (GitHub release, ~2 MB)?" "N"; then
    EFF_DIR="$HOME/.local/share/kwin/effects"
    mkdir -p "$EFF_DIR"
    if [ -d "$EFF_DIR/burnmywindows" ]; then
        log_ok "Burn My Windows already installed in $EFF_DIR."
    else
        if [ -n "$KWRITECONFIG" ] && [ "$KWRITECONFIG" = "kwriteconfig6" ]; then
            ASSET="burn_my_windows_kwin6.tar.gz"
        else
            ASSET="burn_my_windows_kwin5.tar.gz"
        fi
        WORK=$(mktemp -d)
        trap 'rm -rf "$WORK"' EXIT
        TARBALL="$WORK/$ASSET"
        log_info "Downloading $ASSET from github.com/Schneegans/Burn-My-Windows releases..."
        if curl -fsSL -o "$TARBALL" "https://github.com/Schneegans/Burn-My-Windows/releases/latest/download/$ASSET" \
            && verify_download "$TARBALL" 262144; then
            tar -xzf "$TARBALL" -C "$EFF_DIR"
            log_ok "Burn My Windows effects installed to $EFF_DIR."
            log_warn "Enable them in System Settings > Desktop Effects, then press Apply — this runs on your next KWin restart."
        else
            log_warn "Burn My Windows download failed — skipping (cosmetic only; safe to retry later)."
        fi
    fi
fi

echo -e "${GREEN}Fancy Plasma step complete.${NC}"
log_warn "If an effect/swap doesn't show right away, log out and back in — KWin caches some state per-session."