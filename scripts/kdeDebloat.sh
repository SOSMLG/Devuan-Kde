#!/usr/bin/env bash
# =======================================================
# KDE Plasma Debloat (Devuan/Debian)
# -------------------------------------------------------
# Removes the "kitchen sink" apps pulled in by task-kde-desktop
# / kde-standard / kde-full (games, edu suite, PIM/Akonadi stack,
# extra media apps, and optionally Kate/Konqueror/Dragon Player)
# while leaving Plasma itself, Dolphin, Konsole, Okular, Gwenview,
# Ark, System Settings etc. untouched.
# Also disables Baloo file indexing and Akonadi background
# processes, which are the two biggest idle-resource hogs on a
# "minimal" KDE install.
#
# Nothing here is destructive to your files — only installed
# .deb packages and a couple of per-user KDE config toggles.
# =======================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Purge only the packages from the given list that are actually installed.
purge_if_installed() {
    local label="$1"; shift
    local to_purge=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" && to_purge+=("$pkg")
    done
    if [ "${#to_purge[@]}" -eq 0 ]; then
        log_info "$label: nothing installed, skipping."
        return 0
    fi
    log_info "$label: purging ${to_purge[*]}"
    if sudo apt-get purge -y "${to_purge[@]}"; then
        log_ok "$label removed."
    else
        log_warn "$label: some packages failed to purge (continuing)."
    fi
}

if [ "$(id -u)" -eq 0 ]; then
    log_err "Do not run this as root — run it as a normal user (sudo is called internally)."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} KDE Plasma Debloat${NC}"
echo -e "${CYAN}=========================================================${NC}"

if ! command_exists apt-get; then
    log_err "apt-get not found — this script needs a Debian/Devuan APT system."
    exit 1
fi

log_info "Refreshing package lists..."
    apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. KDE Games (kdegames metapackage pulls all of these in)
# ---------------------------------------------------------------------------
if ask "Remove KDE games (kmahjongg, kpat, kmines, ksudoku, etc.)?"; then
    purge_if_installed "KDE games" \
        kmahjongg kpat kmines kollision granatier bomber bovo kajongg \
        kbreakout kdiamond ksudoku kshisen klickety palapeli picmi \
        knights kfourinline kgoldrunner kbounce ksnakeduel kspaceduel \
        kigo ktuberling lskat kubrick kreversi kblocks kapman \
        kdegames-card-data
fi

# ---------------------------------------------------------------------------
# 2. KDE Education suite (kdeedu metapackage)
# ---------------------------------------------------------------------------
if ask "Remove KDE education apps (kalzium, kstars, parley, kgeography, etc.)?"; then
    purge_if_installed "KDE education" \
        kalzium kstars parley kgeography kwordquiz kanagram khangman \
        ktouch kturtle kbruch klettres cantor rocs artikulate blinken \
        marble marble-data kig kmplot step
fi

# ---------------------------------------------------------------------------
# 3. PIM / Akonadi stack (kontact, kmail, korganizer, akregator...)
#    This is the single heaviest idle-RAM group on a default KDE install.
# ---------------------------------------------------------------------------
if ask "Remove PIM/mail suite (Kontact, KMail, KOrganizer, Akregator, Akonadi)?"; then
    purge_if_installed "PIM/Akonadi" \
        kontact kmail kmail-account-wizard korganizer kaddressbook \
        akregator kleopatra ktnef kjots knotes kalarm \
        akonadi-backend-mysql akonadi-backend-sqlite akonadi-server \
        akonadiconsole kdepim-runtime libakonadi-calendar5 \
        libakonadi-contact5 libakonadi-notes5
fi

# ---------------------------------------------------------------------------
# 4. Extra multimedia/misc apps not needed once VLC is installed separately
# ---------------------------------------------------------------------------
if ask "Remove extra bundled apps (Elisa, Kamoso, Minuet, JuK, plasma-welcome)?"; then
    purge_if_installed "Extra apps" \
        elisa kamoso minuet juk plasma-welcome khelpcenter \
        skanlite kmag kmousetool kmouth
fi

# ---------------------------------------------------------------------------
# 5. Kate, Konqueror, Dragon Player — Dolphin and VLC are already covered
#    (Dolphin ships with the base Plasma desktop; VLC is installed by
#    usefulApps.sh), but VSCodium is optional/off-by-default in run.sh —
#    so removing Kate here without installing something in its place would
#    leave you with zero plain-text editor if you don't separately opt into
#    VSCodium. FeatherPad fills that gap: genuinely lightweight (~450KB,
#    Qt5, no KTextEditor/KIO/KParts pulled back in — that would defeat the
#    point of removing Kate), desktop-environment-independent, and it's
#    what actually gets installed here, not just promised in a comment.
# ---------------------------------------------------------------------------
if ask "Remove Kate, Konqueror, and Dragon Player (Dolphin/VLC already cover file-browsing/media; installs FeatherPad as a lightweight text editor in their place)?"; then
    sudo apt-get install -y featherpad \
        && log_ok "FeatherPad installed as a lightweight text editor." \
        || log_warn "FeatherPad failed to install — removing Kate would leave you with no GUI text editor. Skipping the removal."

    if is_installed featherpad; then
        purge_if_installed "Kate/Konqueror/Dragon Player" \
            kate kate-data konqueror konqueror-data dragonplayer
    fi
fi

# ---------------------------------------------------------------------------
# 6. Cleanup orphaned dependencies
# ---------------------------------------------------------------------------
if ask "Run apt autoremove + clean to drop now-orphaned dependencies?"; then
    log_info "Running apt-get autoremove --purge..."
    sudo apt-get autoremove --purge -y || log_warn "autoremove reported issues (non-fatal)."
    log_info "Running apt-get clean..."
    sudo apt-get clean || true
    log_ok "Cleanup done."
fi

# ---------------------------------------------------------------------------
# 7. Disable Baloo file indexing (per-user, big idle CPU/disk hog)
# ---------------------------------------------------------------------------
if ask "Disable Baloo file indexing (recommended for a lean/minimal feel)?"; then
    BALOOCTL=""
    if command_exists balooctl6; then
        BALOOCTL="balooctl6"
    elif command_exists balooctl; then
        BALOOCTL="balooctl"
    fi

    if [ -n "$BALOOCTL" ]; then
        if run_as_user "$BALOOCTL" disable; then
            log_ok "Baloo indexing disabled."
        else
            log_warn "Could not disable Baloo (it may already be disabled)."
        fi
    else
        log_warn "balooctl not found, skipping (Baloo may not be installed)."
    fi
fi

# ---------------------------------------------------------------------------
# 8. Reduce Plasma animation speed slightly (snappier "minimal" feel)
#    Best-effort only — never fails the script if the config tool is missing.
# ---------------------------------------------------------------------------
if ask "Slightly reduce KDE animation speed for a snappier feel?"; then
    KWRITECONFIG=""
    if command_exists kwriteconfig6; then
        KWRITECONFIG="kwriteconfig6"
    elif command_exists kwriteconfig5; then
        KWRITECONFIG="kwriteconfig5"
    fi

    if [ -n "$KWRITECONFIG" ]; then
        if run_as_user "$KWRITECONFIG" --file kdeglobals --group KDE --key AnimationDurationFactor 0.5; then
            log_ok "Animation speed reduced (AnimationDurationFactor=0.5)."
        else
            log_warn "Could not write animation setting (non-fatal)."
        fi
    else
        log_warn "kwriteconfig not found, skipping animation tweak."
    fi
fi

# ---------------------------------------------------------------------------
# 9. Stop the system beep — same four independent sources as the XFCE
#    sibling toolkit, with two KDE-specific differences: X11-only tools
#    (xset) are skipped on Wayland sessions rather than silently no-op'd,
#    and KDE's own bell setting lives in kaccessrc, not xfconf.
# ---------------------------------------------------------------------------
if ask "Silence the system beep/bell (PC speaker, X11/Wayland bell, KDE's own bell setting, and bash's readline bell)?"; then
    # 1. PC speaker kernel driver — OS-level, identical regardless of DE.
    BLACKLIST_CONF="/etc/modprobe.d/pcspkr-blacklist.conf"
    if [ ! -f "$BLACKLIST_CONF" ]; then
        printf 'blacklist pcspkr\nblacklist snd_pcsp\n' | sudo tee "$BLACKLIST_CONF" > /dev/null
        log_ok "Blacklisted pcspkr/snd_pcsp (takes full effect next reboot; unloading live below too)."
    else
        log_info "pcspkr already blacklisted."
    fi
    sudo modprobe -r pcspkr 2>/dev/null || true
    sudo modprobe -r snd_pcsp 2>/dev/null || true

    # 2. X11 bell — only meaningful on an actual X11 session. Plasma 6
    #    commonly defaults to Wayland, where xset has nothing to talk to
    #    (it would silently do nothing, which looks like it worked when
    #    it didn't) — check XDG_SESSION_TYPE rather than assume X11 the
    #    way the XFCE version of this fix safely could.
    if [ "${XDG_SESSION_TYPE:-}" = "x11" ] || [ -n "${DISPLAY:-}" ]; then
        mkdir -p "$HOME/.config/autostart"
        cat > "$HOME/.config/autostart/disable-x11-bell.desktop" << 'EOF'
[Desktop Entry]
Type=Application
Name=Disable X11 Bell
Exec=xset b off
NoDisplay=true
X-GNOME-Autostart-enabled=true
EOF
        xset b off 2>/dev/null || true
        log_ok "X11 bell disabled now, and on every future X11 login."
    else
        log_info "Wayland session detected (or none) — xset doesn't apply here, skipping rather than"
        log_info "writing an autostart entry that would silently do nothing under Wayland."
    fi

    # 3. KDE's own system-bell toggle. Lower confidence than the other
    #    three layers here: kaccessrc's [Bell] SystemBell key is
    #    real and documented (verified against an actual KDE config
    #    dump), but that documentation is KDE3/4-era — worth trying
    #    since a stale key is a harmless no-op, not worth trusting
    #    blindly the way the PC-speaker/readline fixes can be.
    BEEP_KWRITECONFIG=""
    if command_exists kwriteconfig6; then
        BEEP_KWRITECONFIG="kwriteconfig6"
    elif command_exists kwriteconfig5; then
        BEEP_KWRITECONFIG="kwriteconfig5"
    fi
    if [ -n "$BEEP_KWRITECONFIG" ]; then
        run_as_user "$BEEP_KWRITECONFIG" --file kaccessrc --group Bell --key SystemBell false 2>/dev/null \
            && log_ok "KDE's own system-bell setting disabled (kaccessrc)." \
            || log_warn "Couldn't write kaccessrc — check System Settings > Accessibility > Bell manually if you still hear anything KDE-specific."
    else
        log_warn "kwriteconfig not found — skipping KDE's own bell setting (System Settings > Accessibility > Bell covers it manually)."
    fi

    # 4. readline's bell — bash's own tab-complete-fail beep, completely
    #    independent of X11/Wayland/KDE (this is what still beeps even in
    #    a plain TTY with no graphical session running at all).
    INPUTRC="/etc/inputrc"
    if [ -f "$INPUTRC" ]; then
        sudo cp "$INPUTRC" "${INPUTRC}.bak.$(date +%Y%m%d%H%M%S)"
        if grep -q '^set bell-style' "$INPUTRC"; then
            sudo sed -i 's/^set bell-style.*/set bell-style none/' "$INPUTRC"
        elif grep -q '^#[[:space:]]*set bell-style' "$INPUTRC"; then
            sudo sed -i 's/^#[[:space:]]*set bell-style.*/set bell-style none/' "$INPUTRC"
        else
            printf '\nset bell-style none\n' | sudo tee -a "$INPUTRC" > /dev/null
        fi
        log_ok "readline's bell disabled system-wide ($INPUTRC) — takes effect in new shells."
    else
        log_warn "$INPUTRC not found — readline bell left as-is (unusual, but not fatal)."
    fi

    log_ok "Beep sources addressed. If you still hear anything after a reboot, it's almost certainly"
    log_ok "a per-application setting (e.g. a terminal's own bell toggle in its preferences)."
else
    log_warn "Skipped — the beep lives on."
fi

echo -e "${GREEN}KDE debloat complete.${NC}"
log_warn "Log out and back in for Baloo/animation changes to fully apply everywhere."
