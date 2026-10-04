#!/usr/bin/env bash
# DEVMKDE_DESC: Plasma 6 plugins, KRunner runners, extra image formats, apps (Debian-first), user kpackages
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: optional
# =======================================================
# Plasma Addons — the "make it feel like my box" step
# -------------------------------------------------------
# Plasma 6 ships a deliberately small plugin set; the rest lives in
# separate packages. This installs the ones that earn their disk space,
# grouped so you can take a whole group or skip it.
#
# Every package name here was checked against the Devuan excalibur
# archive, and the names are the ones that actually exist -- which is not
# always what you'd guess. The interesting ones:
#
#   kde-spectacle        not "spectacle"  (KDE renamed it when porting to 6)
#   kwallet6             not "kwallet"    (KF6 split; kwalletmanager is the GUI)
#   kimageformat6-plugins not "kimageformats" (same KF6 rename)
#   plasma-runners-addons, -wallpapers-addons, -widgets-addons,
#   -dataengines-addons  these ARE the KRunner/widget/wallpaper plugin
#                        bundles; there is no "krunner-plugins" package
#                        any more. In Plasma 5 that was one metapackage.
#
# About KDE Store widgets
# -----------------------
# store.kde.org is behind an anti-bot wall and cannot be scripted, and this
# toolkit does not ship hardcoded GitHub widget URLs it cannot verify --
# an unverified URL in an installer is a supply-chain liability. Instead
# the last section takes a kpackage .git URL *from you*, on your machine,
# and installs it with the official tool. That works for any widget from
# the Store's "Download from Git" button, and you can see exactly what
# you're installing first.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Plasma Addons"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Plasma 6 plugin bundles + the everyday KDE apps. One apt call for the
#    whole group: they're all small, all from the archive, and installing
#    them piecemeal is four extra round-trips for no benefit.
# ---------------------------------------------------------------------------
CORE_ADDONS=(
    plasma-runners-addons      # KRunner plugins: web search, translate,
                               # character/emoji pickers, recent docs
    plasma-wallpapers-addons   # extra wallpaper sources
    plasma-widgets-addons      # extra widgets
    plasma-dataengines-addons  # extra data engines
    kimageformat6-plugins      # Qt6 image format plugins (webp, jxl, tiff...)
    kde-spectacle              # screenshot tool (named kde-spectacle in KF6)
    kcolorchooser              # the color dialog all GTK apps delegate to
    kio-extras                 # extra Dolphin/KIO protocol handlers
    dolphin-plugins            # version control, file metadata in Dolphin
    ark                        # the archive manager Dolphin delegates to
    kcalc                      # calculator (also the KDE Calculator app)
    plasma-vault               # KWallet system tray applet
    kwalletmanager             # KWallet GUI
    kwallet6                   # the wallet daemon itself
)

log_info "Group 1: Plasma 6 plugin bundles and core KDE apps (${#CORE_ADDONS[@]} packages)."
if ask "Install the plugin bundles and core KDE apps?"; then
    apt_update -qq || true
    install_pkgs "Plasma plugins + KDE apps" "${CORE_ADDONS[@]}" \
        || log_warn "Some packages failed — the rest still installed."
else
    log_info "Group 1 skipped."
fi

# ---------------------------------------------------------------------------
# 2. SSH key agent integration. ksshaskpass plugs KWallet into SSH so
#    unlocked keys are used automatically. On an OpenRC box this matters
#    more than on systemd: there is no gnome-keyring fallback sitting
#    behind it.
# ---------------------------------------------------------------------------
if ask "Install ksshaskpass (KWallet-aware SSH key agent)?"; then
    install_pkgs ksshaskpass
fi

# ---------------------------------------------------------------------------
# 3. Apps — Debian-native first, Flatpak only where Debian has nothing.
#
# Note the naming: there's no "plasma-discover-software-center" on
# Debian 13 -- the Software Center is built from plasma-discover plus a
# per-store backend. flatpak itself is the store-less one.
#
# Policy: prefer the distro package. It's already on the update path, shares
# the session's libraries and theme, and costs no second copy of a runtime.
# Flatpak is the fallback for the apps Debian genuinely doesn't package. The
# split below is verified against the archive rather than assumed, so it is
# also the one place to look when a package shows up in Debian later.
#
#   app      Debian pkg        Flatpak id                 verdict
#   ---------------------------------------------------------------------
#   VLC      vlc               org.videolan.VLC           apt (13 already did it)
#   Blender  blender           org.blender.Blender        apt
#   Krita    krita             org.kde.krita              apt
#   Flatseal flatseal          com.github.tchx84.Flatseal apt
#   Steam    --                com.valvesoftware.Steam     44 installs Valve's .deb
#   Heroic   --                com.heroicgameslauncher.hgl 44 installs the .deb
#   Discord  --                com.discordapp.Discord     flatpak (no Debian pkg)
#
# Steam and Heroic do have Flatpak IDs, but this toolkit already installs both
# from their vendor .debs in 44-gamingSetup.sh — a Flatpak copy on top would be
# a second copy of an app you already have, so we skip them rather than guess.
# ---------------------------------------------------------------------------
DEBIAN_APPS=(
    "vlc|VLC media player"
    "blender|Blender (3D)"
    "krita|Krita (painting)"
    "flatseal|Flatseal (GUI for Flatpak permissions)"
)
DEBIAN_PKGS=(vlc blender krita flatseal)

# Everything with no Debian equivalent. Kept separate from DEBIAN_APPS so the
# interactive picker only ever offers Flatpak IDs it can actually install.
FLATPAK_ONLY=(
    "com.discordapp.Discord|Discord (no Debian package; Vesktop from 45 is the FOSS alternative)"
)

echo
log_info "Installing from Debian first (one copy, shared updates, no extra runtime):"
for entry in "${DEBIAN_APPS[@]}"; do
    IFS='|' read -r pkg label <<< "$entry"
    printf '   %-10s %s\n' "$pkg" "$label"
done
echo
install_pkgs "Debian-native apps" "${DEBIAN_PKGS[@]}"

if ask "Set up Flatpak (Discover Flatpak backend + Flathub remote)?"; then
    install_pkgs "Flatpak + Discover backend" flatpak plasma-discover-backend-flatpak xdg-desktop-portal-gtk

    if command_exists flatpak; then
        # --if-not-exists keeps this idempotent across re-runs.
        if flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
            log_ok "Flathub remote present."
            log_info "Refreshing (large on first run)..."
            flatpak update --appstream >/dev/null 2>&1 || true
        else
            log_err "Could not add the Flathub remote — check your network."
        fi

        echo
        log_info "No Debian package for these, so they come from Flatpak:"
        for entry in "${FLATPAK_ONLY[@]}"; do
            IFS='|' read -r appid label <<< "$entry"
            printf '   %-38s %s\n' "$appid" "$label"
        done
        echo

        SELECTED=()
        if [ "${DEVMKDE_ASSUME_YES:-0}" = "1" ]; then
            # Never block on a read here: an unattended run has nobody to
            # answer it, so a bare `read -rp` would sit forever on a tty.
            # Taking the list wholesale is the same choice the Debian pass
            # above already made — every entry is already a "no apt package".
            log_info "DEVMKDE_ASSUME_YES set — installing the Flatpak-only apps."
            for entry in "${FLATPAK_ONLY[@]}"; do
                IFS='|' read -r appid label <<< "$entry"
                SELECTED+=("$appid")
            done
        else
            log_info "Install any by Flatpak ID, 'all' for every one, or press Enter to skip."
            log_info "Anything already installed is left alone."
            read -rp "   Which ones? " WANTED || WANTED=""

            if [ -n "$WANTED" ]; then
                if [ "$WANTED" = "all" ]; then
                    for entry in "${FLATPAK_ONLY[@]}"; do
                        IFS='|' read -r appid label <<< "$entry"
                        SELECTED+=("$appid")
                    done
                else
                    # Tokenise on commas/whitespace, then keep only ids we listed
                    # above -- an unknown id here would be a typo, and passing it
                    # straight to flatpak would just produce a confusing error.
                    WANTED_NORM=$(printf '%s' "$WANTED" | tr ',[:upper:]' '[:lower:]')
                    for entry in "${FLATPAK_ONLY[@]}"; do
                        IFS='|' read -r appid label <<< "$entry"
                        if printf '%s' "$WANTED_NORM" | tr ' ' '\n' | grep -qxF "$appid"; then
                            SELECTED+=("$appid")
                        fi
                    done
                    for token in $(printf '%s' "$WANTED" | tr ',' ' '); do
                        LOW=$(printf '%s' "$token" | tr '[:upper:]' '[:lower:]')
                        [ "$LOW" = "all" ] && continue
                        FOUND=0
                        for entry in "${FLATPAK_ONLY[@]}"; do
                            IFS='|' read -r appid label <<< "$entry"
                            [ "$appid" = "$LOW" ] && FOUND=1 && break
                        done
                        [ "$FOUND" -eq 0 ] && [ -n "$LOW" ] && log_warn "  '$LOW' isn't in the list above — skipping it."
                    done
                fi
            fi
        fi

        for appid in "${SELECTED[@]}"; do
            if flatpak info "$appid" >/dev/null 2>&1; then
                log_ok "  $appid already installed."
            else
                log_info "  Installing $appid (first run downloads a lot)..."
                flatpak install -y --noninteractive flathub "$appid" >/dev/null 2>&1 \
                    && log_ok "  $appid installed." \
                    || log_warn "  $appid failed to install — try: flatpak install flathub $appid"
            fi
        done
    else
        log_warn "flatpak didn't install — skipping the Flatpak section."
    fi
else
    log_info "Flatpak skipped — only the Debian-native apps above were installed."
fi

# ---------------------------------------------------------------------------
# 4. Community widgets via kpackagetool6.
#
# Deliberately interactive: paste the .git URL you got from the widget's
# KDE Store page ("Download from Git") and it's installed with the official
# tool. Nothing is hardcoded, because a URL baked into an installer that
# nobody re-verifies is exactly how an update hijack happens.
# ---------------------------------------------------------------------------
if ask "Install a community widget from KDE Store by URL (kpackagetool6)?" "N"; then
    if ! command_exists kpackagetool6; then
        log_warn "kpackagetool6 not found."
        log_warn "It's shipped by the libkf6package-dev package -- installing that."
        install_pkgs "libkf6package-dev (provides kpackagetool6)" libkf6package-dev
    fi

    if command_exists kpackagetool6; then
        log_info "Find a widget on store.kde.org, click 'Download from Git', and paste the"
        log_info "git URL here. It installs into your user account only."
        log_info "Installed plugins: kpackagetool6 --list | grep Plugin"
        echo
        read -rp "   Widget git URL (blank = skip): " WP_URL

        if [ -n "$WP_URL" ]; then
            case "$WP_URL" in
                https://*.git|git@*|*://*)
                    log_info "Installing from $WP_URL ..."
                    if kpackagetool6 --type Plasma/Applet --install "$WP_URL"; then
                        log_ok "Widget installed. Restart the panel (or log out and in) to load it."
                    else
                        log_err "kpackagetool6 couldn't install it."
                        log_warn "Most common causes: not a git URL, the repo isn't a Plasma/Applet"
                        log_warn "kpackage, or it needs KDE Frameworks 6 to build."
                    fi
                    ;;
                *)
                    log_warn "That doesn't look like a git URL — skipping."
                    log_warn "It should start with https://…git or git@"
                    ;;
            esac
        fi
    else
        log_warn "Still no kpackagetool6 — skipping the widget section."
    fi
else
    log_info "Community widgets skipped."
fi

# ---------------------------------------------------------------------------
# Tell KRunner and plasmashell to pick up the new runners/widgets.
# ---------------------------------------------------------------------------
if command_exists qdbus6 || command_exists qdbus; then
    QDBUS=$(command_exists qdbus6 && echo qdbus6 || echo qdbus)
    run_as_user "$QDBUS" org.kde.krunner1 /AppLauncher reparseApplications >/dev/null 2>&1 && \
        log_ok "KRunner re-parsed (new runners available)."
fi

echo
log_ok "Plasma addons step complete."
log_info "New KRunner runners and widgets appear on the next login (or restart plasmashell:"
log_info "  'systemctl --user restart plasmashell' — or 'pkill plasmashell' under OpenRC, it respawns)."
log_warn "Nothing here is required for a working desktop — it's all convenience. Removing a"
log_warn "package later with apt is a clean uninstall; Flatpaks uninstall with"
log_warn "  flatpak uninstall <id>."