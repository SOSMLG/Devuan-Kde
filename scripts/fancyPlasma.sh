#!/usr/bin/env bash
# =======================================================
# Fancy Plasma — theming/productivity pass for KDE Plasma
# -------------------------------------------------------
# The Plasma port of the sibling toolkit's "fancy Cinnamon" script.
# Everything here is either:
#   (a) a built-in KWin/Plasma feature, toggled via kwinrc / kwineffectsrc
#       with kwriteconfig — zero extra dependency, zero third-party code, or
#   (b) a single opt-in third-party KWin effect (Burn My Windows) pulled
#       straight from its upstream GitHub releases, installed to your user
#       KWin effects dir — same Home-dir-only, no-system-repo philosophy as
#       everything else here.
#
# What's deliberately left out: browsing gnome-look/KDE Store visually for
# a specific community theme/icon/cursor pack (no stable way to script "the
# exact one shown in a video" reliably), and the sponsor segment.
#
# KWin reload helper: KWin picks up kwinrc/kwineffectsrc changes on
# 'qdbus org.kde.KWin /KWin reconfigure'; fonts need KGlobalSettings
# reparse + often a re-login. Both are attempted below where relevant.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Fancy Plasma"

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
# 1. Custom UI font — Inter, fetched straight from google/fonts on GitHub
#    (the same font the classic appearance walkthroughs use, pulled from
#    source instead of needing a browser).
# ---------------------------------------------------------------------------
if ask "Install and apply the Inter font as your UI font?"; then
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    if [ -f "$FONT_DIR/Inter.ttf" ]; then
        log_ok "Inter already installed."
    else
        log_info "Fetching Inter (variable font) from google/fonts..."
        API_URL="https://api.github.com/repos/google/fonts/contents/ofl/inter"
        DL_URL=$(curl -fsSL "$API_URL" 2>/dev/null | python3 -c '
import json, sys
try:
    entries = json.load(sys.stdin)
    for e in entries:
        if e.get("name") == "Inter[opsz,wght].ttf":
            print(e["download_url"])
            break
except Exception:
    pass
' 2>/dev/null)
        if [ -n "$DL_URL" ] && curl -fsSL -o "$FONT_DIR/Inter.ttf" "$DL_URL"; then
            fc-cache -f "$FONT_DIR" >/dev/null 2>&1
            log_ok "Inter installed to $FONT_DIR"
        else
            log_warn "Could not fetch Inter from GitHub — skipping font install (nothing else here depends on it)."
        fi
    fi

    if [ -f "$FONT_DIR/Inter.ttf" ]; then
        # Plasma's font format: "Family,Size,pt,charset,weight,italic,underline,strikeout,spacing"
        kwrite_user --file kdeglobals --group General --key font "Inter,10,-1,5,400,0,0,0,0,0"
        kwrite_user --file kdeglobals --group General --key activeFont "Inter,10,-1,5,400,0,0,0,0,0"
        kwrite_user --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0"
        log_ok "Inter set as the Plasma UI font."
        if [ -n "$QDBUS" ]; then
            run_as_user "$QDBUS" org.kde.KGlobalSettings /KGlobalSettings reparseConfiguration >/dev/null 2>&1 || true
            log_info "KGlobalSettings asked to reload — running apps may still need a restart to pick up the new font."
        else
            log_warn "qdbus not found — the font applies at next login."
        fi
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
    kwrite_user --file kwineffectsrc --group Plugins --key blurEnabled true
    kwin_reload
    log_ok "Blur enabled (any translucent plasma panel/window now blurs)."
fi

# ---------------------------------------------------------------------------
# 4. Alt-Tab switcher style -> Coverflow (KWin built-in, no third-party
#    task switcher config needed).
# ---------------------------------------------------------------------------
if ask "Switch Alt-Tab to the Coverflow switcher style?"; then
    kwrite_user --file kwinrc --group TabBox --key Mode coverflow
    kwrite_user --file kwinrc --group TabBox --key DesktopMode coverflow
    kwin_reload
    log_ok "Alt-Tab style set to Coverflow (default: 'composeonboard') — tweak in System Settings > Window Management."
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
    kwrite_user --file kwineffectsrc --group Plugins --key magicLampEnabled true
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