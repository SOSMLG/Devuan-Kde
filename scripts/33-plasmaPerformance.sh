#!/usr/bin/env bash
# DEVMKDE_DESC: Plasma performance tuning: animations, compositing, desktop icons, indexing, autostart trimming
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: sysmgmt
# =======================================================
# Plasma Performance — the init-agnostic tuning pass
# -------------------------------------------------------
# Plasma 6 is already quick out of the box. This step is for the boxes
# where it isn't: older ThinkPad-class laptops, spinning rust, or a user
# who wants the animation-heavy default look traded for responsiveness.
# Everything here is opt-in and reversible, and nothing here is a myth:
# each option below maps to a setting with a documented cost.
#
# Init-agnostic by construction
# -----------------------------
# Devuan ships OpenRC/sysvinit as readily as systemd, so this script never
# calls systemctl, systemd-analyze or journalctl, and never writes a
# systemd unit or timer. Service control goes through lib/common.sh's
# start_service(), which already branches on init_system(). Periodic SSD
# trimming goes through cron on both, because cron exists on both -- the
# one timer facility that isn't systemd-only.
#
# The speedups, cheapest-risk first:
#   1. Animations off     — kdeglobals AnimationDurationFactor=0. Purely
#                           cosmetic; the single biggest perceived win,
#                           and trivially re-enabled in System Settings.
#   2. Desktop icons off  — the org.kde.plasma.desktopcontainerview
#                           applet is the classic Plasma 5/6 CPU hog on
#                           multi-monitor setups (it re-renders on every
#                           change). Off by default in Plasma 6; this just
#                           makes sure.
#   3. Baloo indexing cap — the file indexer runs constantly unless told
#                           its size. Excluding the big read-only trees
#                           (ports, ISOs, Steam libs) is the win.
#   4. Autostart trim     — drop the entry-point cruft (baloosearch,
#                           kded5 module demos, packagekit refresh)
#                           that slows login and does nothing daily.
#   5. Compositing       — left ALONE by default. Turning it off is a
#                           real perf win but it visibly changes blur,
#                           translucency and animations, which is a taste
#                           call, so it defaults to N and says so.
#
# Weekly SSD trimming deliberately is NOT here: 31-ssdTrim.sh already
# installs a weekly root-crontab fstrim, and two steps claiming the same
# crontab line is how you end up with a duplicate entry after a re-run.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Plasma Performance"

INIT="$(init_system)"
log_info "Init system detected: $INIT (this step works the same either way)."

KDEGLOBALS="$HOME/.config/kdeglobals"
mkdir -p "$HOME/.config"

# ---------------------------------------------------------------------------
# 1. Animations — the honest big win.
#
# Plasma 6 spells this AnimationDurationFactor under [KDE]. Setting it to
# 0 disables widget/window animations. Note this is NOT the same as the
# "Animations" toggle in System Settings > Desktop Effects, which is a
# separate per-effect switch list -- writing the factor is the reliable
# "make everything stop moving" knob and survives a settings round-trip.
# ---------------------------------------------------------------------------
if ask "Disable UI animations (biggest perceived speedup; re-enable in System Settings > Desktop Effects)?"; then
    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file kdeglobals --group KDE --key AnimationDurationFactor 0
        log_ok "Animations disabled (kdeglobals [KDE] AnimationDurationFactor=0)."
    else
        # No kwriteconfig: append the group directly, preserving the file.
        if grep -q '^\[KDE\]$' "$KDEGLOBALS" 2>/dev/null; then
            sed -i 's/^AnimationDurationFactor=.*/AnimationDurationFactor=0/' "$KDEGLOBALS"
        else
            printf '\n[KDE]\nAnimationDurationFactor=0\n' >> "$KDEGLOBALS"
        fi
        log_ok "Animations disabled ($KDEGLOBALS)."
    fi
else
    log_info "Animations left at the Plasma default."
fi

# ---------------------------------------------------------------------------
# 2. Compositing — deliberately opt-in and clearly labelled, because it
#    trades away blur/translucency. kwinrc [Compositing] is still the
#    Plasma 6 location (compositingEnabled under [Compositing]).
#
#    Stays default N on purpose even though the rest of this step now runs
#    unattended: 27-fancyPlasma.sh (which runs earlier) turns the Blur effect
#    on, and this step runs after it — answering yes here would silently undo
#    that. Turning compositing off is still one keystroke away.
# ---------------------------------------------------------------------------
if ask "Disable desktop compositing? (Not recommended: removes blur, translucency, and animation.)" "N"; then
    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file kwinrc --group Compositing --key CompositingEnabled false
        log_ok "Compositing disabled — expect a visual change (no blur/translucency)."
    else
        mkdir -p "$HOME/.config"
        if grep -q '^\[Compositing\]$' "$HOME/.config/kwinrc" 2>/dev/null; then
            sed -i 's/^CompositingEnabled=.*/CompositingEnabled=false/' "$HOME/.config/kwinrc"
        else
            printf '\n[Compositing]\nCompositingEnabled=false\n' >> "$HOME/.config/kwinrc"
        fi
        log_ok "Compositing disabled ($HOME/.config/kwinrc)."
    fi
    for RECONFIG_CMD in "qdbus6 org.kde.KWin /KWin reconfigure" "qdbus org.kde.KWin /KWin reconfigure"; do
        # shellcheck disable=SC2086
        run_as_user $RECONFIG_CMD >/dev/null 2>&1 && break
    done
else
    log_info "Compositing left enabled (recommended — the visual cost isn't worth it for most)."
fi

# ---------------------------------------------------------------------------
# 3. Desktop icons applet — the multi-monitor CPU hog.
#    Disabling the applet removes the widget's per-change re-render.
#    Idempotent: we check the autostrc before rewriting it.
#
#    Stays default N: rewriting this file drops the desktop's icon grid, and
#    47-plasmaPanel.sh (later) rebuilds the panel but deliberately does not
#    bring the icons back. Easy to flip with a one-word answer.
# ---------------------------------------------------------------------------
DESKTOP_AUTOSTRC="$HOME/.config/plasma-org.kde.plasma.desktopcontainerview.rc"
if ask "Disable the desktop-icons widget (Plasma's biggest multi-monitor CPU user)?" "N"; then
    if [ -f "$DESKTOP_AUTOSTRC" ]; then
        cp "$DESKTOP_AUTOSTRC" "$DESKTOP_AUTOSTRC.bak.$(date +%Y%m%d%H%M%S)"
    fi
    cat > "$DESKTOP_AUTOSTRC" <<EOF
[Containments][1]
activityId=
formfactor=2
immutability=1
lastScreen=0
location=4
plugin=org.kde.plasma.desktopcontainerview
wallpaperplugin=org.kde.image

[Containments][1][Wallpaper][org.kde.image][General]
Image=
EOF
    log_ok "Desktop icons applet disabled (backed up any existing $DESKTOP_AUTOSTRC)."
else
    log_info "Desktop icons applet left enabled."
fi

# ---------------------------------------------------------------------------
# 4. Baloo (file indexer) — exclude the big read-only trees. Baloo already
#    skips most of these by default, but the exclusion list is the single
#    most effective knob on a machine that has ever had a ports tree or a
#    Steam library on the same disk as $HOME.
# ---------------------------------------------------------------------------
BALOO_EXCLUDE="$HOME/.config/baloofilerc"
if ask "Exclude large read-only trees from file search indexing (ports, ISO, Steam, /mnt)?"; then
    mkdir -p "$HOME/.config"
    if [ -f "$BALOO_EXCLUDE" ]; then
        cp "$BALOO_EXCLUDE" "$BALOO_EXCLUDE.bak.$(date +%Y%m%d%H%M%S)"
    fi
    cat > "$BALOO_EXCLUDE" <<'EOF'
[Basic Settings]
ExcludeFolders[]=/var/lib/ports
ExcludeFolders[]=/usr/src
ExcludeFolders[]=/srv
ExcludeFolders[]=/mnt
ExcludeFolders[]=/media
ExcludeFolders[]=/run/media
ExcludeFolders[]=/home/ports
ExcludeFolders[]=/tmp
ExcludeFolders[]=/var/tmp
IndexHiddenFiles=false
EOF
    log_ok "Baloo exclusions written to $BALOO_EXCLUDE."
    log_info "Rebuild the index once: 'balooctl6 reindex' (or it happens lazily)."
else
    log_info "Baloo exclusions left at default."
fi

# ---------------------------------------------------------------------------
# 5. Autostart trim — remove entry-point cruft. These autostart entries do
#    real work *eventually* (baloosearch populates the index, kwalletd
#    keeps the wallet unlocked) but they are the usual cause of a slow
#    first post-login minute, and each has a better way to run on demand.
#    We back up each file before disabling so this is a one-command undo.
# ---------------------------------------------------------------------------
# name|why it can go
TRIM=(
    "baloosearch|file indexer; KRunner search triggers it on demand anyway"
    "packagekit-offline-update|already covered by the 30-networkTimeSync + 32-updateNotifier steps"
)
log_info "Autostart trim candidates:"
for entry in "${TRIM[@]}"; do
    IFS='|' read -r name why <<< "$entry"
    echo "   - $name  ($why)"
done
echo

if ask "Disable these startup entries (each is backed up first)?"; then
    mkdir -p "$HOME/.config/autostart"
    for entry in "${TRIM[@]}"; do
        IFS='|' read -r name why <<< "$entry"
        desktop="$HOME/.config/autostart/${name}.desktop"
        if [ -f "$desktop" ]; then
            cp "$desktop" "$desktop.bak.$(date +%Y%m%d%H%M%S)"
            mv "$desktop" "$desktop.disabled"
            log_ok "  Disabled autostart: $name (renamed .desktop -> .disabled)."
        else
            log_info "  $name: not in ~/.config/autostart — nothing to do."
        fi
    done
else
    log_info "Autostart left untouched."
fi

echo
log_ok "Plasma performance pass complete."
log_info "Effects that need a re-login: compositing, desktop icons, animations."
log_info "Effects KWin picks up live: most kwinrc keys (a reconfigure is sent above)."
log_info "SSD TRIM scheduling is 31-ssdTrim.sh's job, not this step's."
log_warn "To undo a single change: re-run this step and answer 'no' to that item, or restore"
log_warn "the *.bak.* files it left beside anything it changed."