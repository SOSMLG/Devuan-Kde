#!/usr/bin/env bash
# DEVMKDE_DESC: Rebuild panel - floating centered or Windows-style anchored (configurable)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: optional
# =======================================================
# Plasma Panel — one floating bar, and nothing you don't use
# -------------------------------------------------------
# The default is a SINGLE floating panel at the bottom: centred,
# fit-to-content, holding a breathing spacer, Kickoff, your
# pinned apps (Konsole, Dolphin, Firefox ESR, VLC — only the
# ones actually installed), an icon-only task manager, the
# workspace pager, the system tray, a compact clock and
# show-desktop.
#
# One bar beats two because the tray bar was the awkward half of
# the old layout: it lived at the top RIGHT while everything else
# lived at the bottom LEFT, so two bars meant looking in two
# corners for two pieces of information. Tray and clock are both
# on the app bar now, and there is nothing left to auto-hide --
# a floating bar reserves no screen space anyway, so hiding it
# only cost you a hover.
#
# Two flags get the rest back, both off by default:
#
#   --tray-panel   restore the second, auto-hiding tray/clock
#                  bar at the top right (the old two-panel layout)
#   --extras       put the clipboard-history and activity-bar
#                  applets back on the app bar
#
# The spacers are NON-expanding on purpose: an expanding spacer
# swallows all free width and stretches the bar back across the
# whole screen, which is the opposite of floating.
#
# Builds and tears down the panel entirely through the SAME supported
# Plasmashell scripting API that KDE's own migration scripts use
# (desktops()/panels()/new Panel()/addWidget()/writeConfig()/remove())
# -- no hand-editing of plasma-org.kde.plasma.desktop-appletsrc.
#
# Every panel property used here was verified against the Plasma 6.3.6
# sources (shell/scripting/panel.cpp for the accepted strings,
# shell/panelview.cpp for what actually persists), because the
# alternative is a panel that looks right until the next login:
#
#   location     top | bottom | left | right
#   alignment    left | center | right
#   lengthMode   fit | custom        (+ length/minimumLength/maximumLength)
#   hiding       autohide | dodgewindows | windowsgobelow
#   opacity      adaptive | opaque | translucent
#   height       -> persisted as "thickness"
#
# and these are persisted by assigning the PROPERTY, not by
# writeConfig():
#
#   floating   -> [Containments][N] floating          (int)
#   opacity    -> [Containments][N] panelOpacity      (int)
#   hiding     -> [Containments][N] panelVisibility   (int)
#   lengthMode -> [Containments][N] panelLengthMode   (int)
#
# The property names and the config keys are NOT the same, and the
# stored values are integers while the scripting API takes strings
# ("translucent", not 1). Writing writeConfig("opacity", "translucent")
# would persist a key nothing reads -- the translucency would survive
# exactly until the next login and then quietly revert.
#
# The applet keys are verified the same way, against the shipped
# main.xml of each applet on this box, so the "beauty" settings
# below cannot persist a key nothing reads either.
#
# Safe/reversible by design:
#   - the current config is backed up BEFORE anything runs
#     (restore = scripts/47-plasmaPanel.sh --restore, or swap the file
#     back by hand and restart plasmashell);
#   - every change applies live via D-Bus, so nothing needs root and
#     nothing takes effect until the script runs;
#   - pinned apps are resolved against what's installed, so a missing
#     VSCodium/etc. is skipped cleanly instead of leaving a dead icon.
#
# Usage: scripts/47-plasmaPanel.sh [--dry-run] [--restore]
#                                 [--tray-panel] [--extras] [--dodge-windows]
#                                 [--windows-style] [--style windows|plasma]
#                                 [--non-floating] [--floating] [--thickness N]
#                                 [--alignment left|center|right] [--task-style icons|textbesideicons|text]
#                                 [--no-grouping]
#   --dry-run         print the JS payload and where the backup goes
#   --restore         put the pre-run panel config back
#   --tray-panel      two panels again: adds the slim auto-hiding
#                     tray/clock bar at the top right
#   --extras          keep the clipboard-history and activity-bar
#                     applets (both dropped by default)
#   --dodge-windows   the bar dodges maximised windows instead of
#                     staying on screen
#   --windows-style   use Windows-like defaults (non-floating, left-aligned,
#                     thickness 48, tasks show text beside icons, expanding spacer)
#   --style windows|plasma  choose panel style
#   --non-floating    make panel docked/anchored (not floating)
#   --floating        make panel floating
#   --thickness N     panel thickness in pixels (default 40, windows-style 48)
#   --alignment a     left|center|right (default center/plasma, windows left)
#   --task-style s    icons|textbesideicons|text for task manager
#   --no-grouping     disable task grouping
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

DRY_RUN=0
RESTORE=0
# Single bottom bar is the default; --tray-panel gets the second bar back and
# --extras the two applets the default leaves off. Both flags only flip these,
# they never add a second code path: the JS branches on the same two values.
TRAY_PANEL=0
PANEL_EXTRAS=0
DODGE=0
WINDOWS_STYLE=0
PANEL_FLOATING=""
PANEL_THICKNESS=""
PANEL_ALIGNMENT=""
PANEL_TASK_STYLE="icons"
PANEL_NO_GROUPING=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=1 ;;
        --restore) RESTORE=1 ;;
        --tray-panel) TRAY_PANEL=1 ;;
        # Kept working on purpose: single-panel used to be this flag's job, so
        # anything scripted or documented against it must not start erroring.
        --no-tray-panel) : ;;
        --extras) PANEL_EXTRAS=1 ;;
        --dodge-windows) DODGE=1 ;;
        --windows-style|--win-style) WINDOWS_STYLE=1 ;;
        --style)
            shift
            case "${1:-}" in
                windows|win) WINDOWS_STYLE=1 ;;
                plasma) WINDOWS_STYLE=0 ;;
                *) log_err "Unknown --style value: ${1:-}"; exit 1 ;;
            esac
            ;;
        --non-floating) PANEL_FLOATING=false ;;
        --floating) PANEL_FLOATING=true ;;
        --thickness)
            shift
            PANEL_THICKNESS="${1:-}"
            ;;
        --alignment)
            shift
            PANEL_ALIGNMENT="${1:-}"
            ;;
        --task-style)
            shift
            PANEL_TASK_STYLE="${1:-}"
            ;;
        --no-grouping) PANEL_NO_GROUPING=1 ;;
        -h|--help)
            # Print the whole header comment, not a fixed line range: the usage
            # block lives at the END of it, and a range that once covered it
            # stopped covering it the moment the explanation above grew.
            awk 'NR == 1 { next } /^set / { exit } { sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
            exit 0
            ;;
        *)
            log_err "Unknown option: $arg"
            exit 1
            ;;
    esac
done

# Apply Windows-style defaults if requested
if [ "$WINDOWS_STYLE" = 1 ]; then
    [ -z "$PANEL_FLOATING" ] && PANEL_FLOATING=false
    [ -z "$PANEL_THICKNESS" ] && PANEL_THICKNESS=48
    [ -z "$PANEL_ALIGNMENT" ] && PANEL_ALIGNMENT=left
    [ -z "$PANEL_TASK_STYLE" ] && PANEL_TASK_STYLE=textbesideicons
else
    [ -z "$PANEL_FLOATING" ] && PANEL_FLOATING=true
    [ -z "$PANEL_THICKNESS" ] && PANEL_THICKNESS=40
    [ -z "$PANEL_ALIGNMENT" ] && PANEL_ALIGNMENT=center
    [ -z "$PANEL_TASK_STYLE" ] && PANEL_TASK_STYLE=icons
fi

ACTIVE_USER_HOME="$(getent passwd "$ACTUAL_USER" | cut -d: -f6)"
# Panel state lives in TWO files, and a backup of only the obvious one leaves
# --restore half-done:
#
#   plasma-org.kde.plasma.desktop-appletsrc  [Containments][<id>] and
#       [Containments][<id>][Applets][<n>] — WHICH panels exist, at which
#       edge, and what is on them.
#   plasmashellrc                             [PlasmaViews][Panel <id>] —
#       floating, alignment, panelVisibility, panelLengthMode, thickness,
#       offset and the min/max length. This is PanelView::config()
#       (shell/panelview.cpp, panelConfig()), and it is the file the property
#       setters write to.
#
# Verified by reading both files after a live apply: the geometry keys are in
# plasmashellrc and appear nowhere in desktop-appletsrc.
APPSLETSRC="$ACTIVE_USER_HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
SHELLRC="$ACTIVE_USER_HOME/.config/plasmashellrc"
BACKUP_PATH="$APPSLETSRC.pre-plasmaPanel"
SHELLRC_BACKUP="$SHELLRC.pre-plasmaPanel"

PLASMA_VERSION="$(run_as_user plasmashell --version 2>/dev/null | awk '{print $2}')"
if [ -z "$PLASMA_VERSION" ]; then
    log_warn "plasmashell not reachable (off-session?) — Dry-run only."
    DRY_RUN=1
fi
log_info "Detected: Plasma $PLASMA_VERSION"

# Wayland vs X11 changes exactly one thing (the show-desktop applet is a
# KWin action; if it ever turns out to be inert on your session, the
# fallback is printed at the end rather than silently swallowed).
SESSION_TYPE="${XDG_SESSION_TYPE:-unknown}"
if [ "$SESSION_TYPE" = "unknown" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ]; then SESSION_TYPE="wayland"; else SESSION_TYPE="x11"; fi
fi
log_info "Session: $SESSION_TYPE"

DBUS=$(command -v qdbus6 || command -v qdbus)
if [ -z "$DBUS" ]; then
    log_err "Neither qdbus6 nor qdbus found — can't reach plasmashell."
    exit 1
fi

# --- 0. Restore --------------------------------------------------------------
if [ "$RESTORE" = 1 ]; then
    if [ ! -f "$BACKUP_PATH" ]; then
        log_err "No backup at $BACKUP_PATH — nothing to restore."
        exit 1
    fi
    cp -a "$BACKUP_PATH" "$APPSLETSRC" || { log_err "Restore copy failed."; exit 1; }
    log_ok "Panel layout restored from $BACKUP_PATH"
    # Optional: backups taken before this script learned about plasmashellrc
    # have no geometry backup, and restoring only the layout would leave the
    # bars floating/pinned in ways the layout file does not describe.
    if [ -f "$SHELLRC_BACKUP" ]; then
        cp -a "$SHELLRC_BACKUP" "$SHELLRC" || { log_err "plasmashellrc restore failed."; exit 1; }
        log_ok "Panel geometry restored from $SHELLRC_BACKUP"
    else
        log_warn "No $SHELLRC_BACKUP — panel geometry (floating, lengths, visibility) NOT restored."
    fi
    if pgrep -x plasmashell >/dev/null 2>&1; then
        log_info "Restarting plasmashell to pick it up ..."
        run_as_user kquitapp6 plasmashell >/dev/null 2>&1 || true
        sleep 2
        run_as_user setsid plasmashell >/dev/null 2>&1 &
        sleep 3
        log_ok "plasmashell restarted."
    else
        log_warn "plasmashell is not running — log out and back in to see the restored panel."
    fi
    exit 0
fi

# --- 1. Pinned apps ----------------------------------------------------------
# Each candidate is added only when its .desktop file is present on the
# system, so a machine without (say) VSCodium simply omits it.
# Four is the number that still reads as one gesture on a centred bar; add
# org.kde.okular back here if you want the PDF reader one click away.
PIN_IDS=(org.kde.konsole org.kde.dolphin firefox-esr vlc)
PIN_URLS=()
for PID in "${PIN_IDS[@]}"; do
    if [ -f "/usr/share/applications/$PID.desktop" ] || [ -f "$ACTIVE_USER_HOME/.local/share/applications/$PID.desktop" ]; then
        PIN_URLS+=("applications:$PID.desktop")
    else
        log_warn "Skipping pin \"$PID\" — its .desktop file isn't installed."
    fi
done
if [ "${#PIN_URLS[@]}" -eq 0 ]; then
    log_warn "No pinned apps resolved — the panel will be Kickoff + tasks + pager only."
fi

# --- 3. Build the JS payload -------------------------------------------------
# Mirrors the stock defaultPanel layout template's use of the scripting
# API. Old panels are emptied (widget.remove()) then removed; fresh
# panels are created floating. All config writes use the documented
# writeConfig()/readConfig() interface, EXCEPT the panel properties
# listed in the header, which persist through their setters.
# The delimiter is QUOTED ('JS'). Unquoted, the shell expands the body before
# plasmashell ever sees it, and the JS is full of things an unquoted heredoc
# treats as commands: `length` in a comment became "length: command not
# found", and a backticked example line ran as a command substitution. Both
# happened silently — the payload still applied, just with mangled comments
# and a nonzero-looking stderr nobody reads. Every value the body needs is
# substituted afterwards by build_payload's sed, which is where it belongs.
build_js() {
    local urls="$1"
    cat << 'JS'
// ---- generated by plasmaPanel.sh ----
var old = panels();
old.forEach(function (p) {
    // Empty first; widget.remove() is the shipped/verified operation. Guard
    // it as well as p.remove(): a single widget that refuses to go (an
    // immutable applet, say) would otherwise throw out of the forEach and
    // abort the whole teardown, leaving a half-emptied panel behind and
    // never reaching the fresh-panel construction below.
    p.widgets().forEach(function (w) {
        try { w.remove(); } catch (e) {}
    });
    try { p.remove(); } catch (e) {}
});

// HOW A PANEL PROPERTY PERSISTS — verified against a live session
//
// Every wrong value here fails silently, so none of this is taken from the
// docs or from memory. It was established by applying this payload and then
// reading the two config files Plasma actually wrote:
//
//   1. ASSIGN THE PROPERTY. writeConfig() is inert for panel geometry.
//      PanelView::setFloating()/setAlignment()/setMaximumLength() write into
//      PanelView::config(), and the scripting wrapper's writeConfig targets
//      the CONTAINMENT group. Different group, different file:
//        [Containments][195] minimumLength=340   <- what writeConfig produced
//        [PlasmaViews][Panel 235][Horizontal1829] maxLength=340  <- what took
//      An earlier version of this payload led with app.writeConfig("floating",
//      true) under a comment claiming the opposite, and every test passed
//      while the bar stayed full width.
//
//   2. THE GEOMETRY LANDS IN plasmashellrc, NOT in
//      plasma-org.kde.plasma.desktop-appletsrc. PanelView::panelConfig()
//      (shell/panelview.cpp) opens [PlasmaViews][Panel <id>][Horizontal <w>]
//      on the corona's applicationConfig. desktop-appletsrc keeps
//      [Containments] and [Applets] — which panels exist and what is on them.
//      Both files are backed up for exactly this reason; see APPSLETSRC and
//      SHELLRC above.
//
//   3. THE hiding GETTER IS LOSSY, THE SETTER IS NOT. Assigning
//      "windowsgobelow" persists panelVisibility=3, but reading .hiding back
//      answers "none" — the getter cannot distinguish 0 from 3. An earlier
//      revision of this comment called the value "unreachable" on the strength
//      of that read and switched the app bar to "none", which is
//      panelVisibility=0: always visible AND space reserved, the opposite of
//      the intent. Verify this property in plasmashellrc, never through D-Bus.
//
//   4. OPACITY CANNOT BE SET FROM HERE. Every string ("Translucent",
//      "translucent", "opaque", "adaptive") and every integer was assigned on a
//      live panel and no panelOpacity key was ever written to plasmashellrc,
//      while the property always read back "adaptive". Adaptive is
//      PanelView::defaultOpacityMode() — translucent normally, opaque behind a
//      maximized window — which is what a floating bar wants, so the payload
//      sets nothing rather than pretending. Forcing 2 means hand-writing
//      panelOpacity=2 into [PlasmaViews][Panel <id>] and restarting
//      plasmashell: not worth the fragility.
//
//   5. `length` IS NOT THE PANEL WIDTH. PanelView::length() returns
//      m_contentLength — the natural width of the applets — and nothing
//      clamps it. The tray reads 633 whatever minLength/maxLength say, and
//      that is not evidence the bounds were ignored: they are persisted
//      (panelLengthMode=2 with minLength/maxLength=340) and it is the layout
//      pass that clamps to them. Reading `length` as "the bounds did not
//      apply" sent this payload looking for a bug that was not there.
//
// The enum ordinals, for the record (shell/panelview.h, v6.3.6). The three
// keys are read with readEntry<int>, so a string written by hand here would
// land as 0:
//
//   panelVisibility: 0 NormalPanel  1 AutoHide  2 DodgeWindows  3 WindowsGoBelow
//   panelOpacity:    0 Adaptive     1 Opaque    2 Translucent
//   panelLengthMode: 0 FillAvailable 1 FitContent 2 Custom
//
// Name handling is asymmetric between setter and getter, which is the trap in
// (3): the setter takes the lowercased enum name ("autohide", "dodgewindows",
// "windowsgobelow"), the getter returns "none" for 0 and for 3.

// Breathing room on the left. Two things were wrong here before, and both
// failed silently:
//
//   1. The plugin id is "panelspacer", NOT "spacer". addWidget() with an
//      unknown id raises nothing and logs nothing — the widget just never
//      appears, and it is missing from the saved applet order.
//   2. The config keys are "expanding" and "length" (see
//      plasmoids/org.kde.plasma.panelspacer/contents/config/main.xml), NOT
//      "filling"/"thickness". Writing invented keys persists them where
//      nothing reads them, and "expanding" then keeps its DEFAULT of true —
//      so the spacer swallowed all free space and stretched the "floating"
//      bar across the full 1920px anyway.
function addSpacer(panel, len, expanding) {
    var sp = panel.addWidget("org.kde.plasma.panelspacer");
    sp.currentConfigGroup = ["General"];
    sp.writeConfig("expanding", expanding === true);
    sp.writeConfig("length", len);
    return sp;
}

// ===== Panel 1: the app bar ==================================================
var app = new Panel();
app.currentConfigGroup = [];
// new Panel() lands on the TOP edge, and two panels on the same edge overlap
// instead of coexisting — so location has to be set explicitly for each one.
app.location = "bottom";
app.height = $PANEL_THICKNESS;      // -> thickness
// Property assignment is what persists; see the header. The writeConfig pair
// that used to sit here wrote floating/alignment into [Containments][<id>],
// a group PanelView never reads.
app.floating = $PANEL_FLOATING;      // -> [PlasmaViews][Panel <id>] floating
app.alignment = "$PANEL_ALIGNMENT"; // -> alignment
// Use fill mode for Windows-style (left-aligned with expanding spacer) to feel anchored
if ($WINDOWS_STYLE) {
    app.lengthMode = "fill";         // -> panelLengthMode = 0 (FillAvailable)
} else {
    app.lengthMode = "fit";          // -> panelLengthMode = 1 (FitContent)
}
app.hiding = "$APP_HIDING";         // -> panelVisibility
app.offset = 0;
// No opacity line: unreachable from the scripting API, and Adaptive is
// Plasma's own default. See note (4) in the header.

addSpacer(app, 6, false);

// Kickoff, with a GRID of favourites in the popup instead of the default dense
// list -- four large icons scan faster than four dense rows.
// favoritesDisplay is [General] favoritesDisplay in the applet's shipped
// main.xml: 0 = Grid, 1 = List. Note what is NOT there: Plasma 6.3's kickoff
// has no iconSize key, so the launcher icon cannot be enlarged from the applet
// at all. Writing one would persist a key nothing reads, which is the exact
// failure this script is written to avoid.
var kickoff = app.addWidget("org.kde.plasma.kickoff");
kickoff.currentConfigGroup = ["General"];
kickoff.writeConfig("favoritesDisplay", 0);

// pinned launchers (resolved to installed apps only)
URLS="$urls"   // substituted by build_payload; see the note above build_js
function mkUrlList(u) { return u.split("||"); }
var urls = mkUrlList(URLS);
for (var i = 0; i < urls.length; i++) {
    if (urls[i] === "") continue;
    var icon = app.addWidget("org.kde.plasma.icon");
    icon.writeConfig("launcherUrl", urls[i]);
    icon.writeConfig("launcherUrlOnlyWhenInstalled", true);
}

// task manager for running apps
var tasks = app.addWidget("org.kde.plasma.icontasks");
// Only these three keys exist in Plasma 6.3's taskmanager config. The
// familiar Plasma 5 spellings (minimumSize, showLauncherOnContextClick) are
// NOT in it any more — writing them persists keys nothing reads, and the
// applet keeps its default while the file claims otherwise.
tasks.writeConfig("showOnlyCurrentScreen", false);
tasks.writeConfig("showOnlyCurrentActivity", false);
tasks.writeConfig("showOnlyMinimized", false);
// Try to set task style/grouping if requested (Plasma 6.3 varies; be defensive)
try { if ($WINDOWS_STYLE) { tasks.writeConfig("showText", "true"); tasks.writeConfig("textPosition", "besideIcon"); tasks.writeConfig("groupingStrategy", "0"); } else { tasks.writeConfig("showText", "false"); tasks.writeConfig("textPosition", "bottom"); } } catch (e) {}

// Add expanding spacer in Windows-style to push right side to edge
if ($WINDOWS_STYLE) {
    addSpacer(app, 6, true);
}

// workspace pager, then the two applets the default layout leaves off
var pager = app.addWidget("org.kde.plasma.pager");
pager.currentConfigGroup = ["General"];
pager.writeConfig("showOnlyCurrentScreen", false);
pager.writeConfig("showWindowIcons", false);

// Clipboard history and the activity bar. Both are one more button to read past
// on a bar this short, and neither is something you reach for daily, so
// --extras is what puts them back.
//
// Clipboard history in particular needs no klipper daemon: in Plasma 6 klipper
// was merged INTO plasmashell (no /usr/bin/klipper, no autostart entry, no
// org.kde.klipper DBus service -- only libklipper6 + this applet ship in
// plasma-workspace). The applet talks to plasmashell directly, so adding the
// widget is all that is needed; do NOT add a klipper autostart alongside it.
// Its only config key is "barcodeType" (default QRCode), so nothing to write.
PANEL_EXTRAS=$PANEL_EXTRAS

if (PANEL_EXTRAS) {
    app.addWidget("org.kde.plasma.clipboard");
    app.addWidget("org.kde.plasma.activitybar");
}

// trailing spacer - non-expanding by default (keeps centered/floating behavior)
// In Windows-style we already added an expanding spacer before this; keep trailing small
if (!$WINDOWS_STYLE) {
    addSpacer(app, 6, false);
}

CLOCK_ON_APP=$CLOCK_ON_APP
TRAY_ON_APP=$TRAY_ON_APP
SHOW_DESKTOP=$SHOW_DESKTOP

if (TRAY_ON_APP) {
    // Single bar (the default): the tray and clock ride along on the app bar,
    // and the trailing spacer above them becomes the gap between the apps and
    // the status area, which is what keeps the bar from reading as one long
    // undifferentiated row of icons.
    app.addWidget("org.kde.plasma.systemtray");

    var clockA = app.addWidget("org.kde.plasma.digitalclock");
    clockA.currentConfigGroup = ["Appearance"];
    try { clockA.writeConfig("dateFormat", "shortDate"); } catch (e) {}
}

// ===== Panel 2: the slim auto-hiding tray bar ================================
var tray = null;
if (!TRAY_ON_APP) {
    tray = new Panel();
    tray.currentConfigGroup = [];
    tray.location = "top";
    tray.height = 32;
    tray.floating = true;            // -> floating
    tray.alignment = "right";        // -> alignment
    tray.lengthMode = "custom";      // -> panelLengthMode = 2 (Custom)
    tray.hiding = "autohide";        // -> panelVisibility = 1
    tray.offset = 0;

    // Push the tray and clock to the right-hand end of the 340px strip. This
    // spacer is deliberately NOT expanding: with alignment=right and a fixed
    // length, an expanding one would simply eat the whole strip and leave
    // them pushed off the end of it.
    addSpacer(tray, 250, false);

    tray.addWidget("org.kde.plasma.systemtray");

    var clockB = tray.addWidget("org.kde.plasma.digitalclock");
    clockB.currentConfigGroup = ["Appearance"];
    try { clockB.writeConfig("dateFormat", "shortDate"); } catch (e) {}

    // The length bounds go on LAST, after every applet exists. PanelView
    // re-derives the panel length from its content whenever the contents
    // change, and that pass overwrites the bounds, so setting them first and
    // adding applets afterwards leaves the bar at its natural width: it
    // measured 633px instead of 340px, with no error anywhere. Because
    // maxLength == minLength the result is a fixed-width bar.
    tray.minimumLength = 340;        // -> minLength
    tray.maximumLength = 340;        // -> maxLength
}

if (SHOW_DESKTOP) {
    // Show desktop is a KWin action rather than a plain applet: on X11 it
    // minimises, on Wayland it asks KWin to reveal the desktop. Both work,
    // and it is added to whichever bar currently owns the app widgets.
    (TRAY_ON_APP ? app : tray).addWidget("org.kde.plasma.showdesktop");
}
JS
}

PIN_JOINED=""
first_pin=1
for u in "${PIN_URLS[@]}"; do
    if [ "$first_pin" = 1 ]; then
        PIN_JOINED="$u"
        first_pin=0
    else
        PIN_JOINED="$PIN_JOINED||$u"
    fi
done

# Shell-level values the JS above interpolates. Kept out of the heredoc body
# on purpose: they are decisions, not layout.
if [ "$DODGE" = 1 ]; then
    APP_HIDING="dodgewindows"
else
    # The app bar itself stays put. Auto-hiding BOTH bars is a desktop where
    # the clock and the tray are two edge-peeks away from each other.
    #
    # WindowsGoBelow (panelVisibility=3) — always visible, reserves no space —
    # is the right mode for a floating bar.
    #
    # It was briefly replaced with "none" here, on the reading that the setter
    # ignored it: probing the property after assigning "windowsgobelow" reports
    # hiding=none. The setter does NOT ignore it. The WRITE works and persists
    # panelVisibility=3 to plasmashellrc; it is the READ that is lossy — the
    # getter answers "none" for both 0 and 3, so the property cannot tell the
    # two apart. Confirmed on disk:
    #
    #   [PlasmaViews][Panel 182]
    #   floating=1
    #   panelLengthMode=1
    #   panelVisibility=3
    #
    # Consequence for anything verifying this script: check the config file,
    # not the property. `hiding` reads "none" whether it is 0 or 3.
    APP_HIDING="windowsgobelow"
fi
if [ "$TRAY_PANEL" = 1 ]; then
    CLOCK_ON_APP=false
    TRAY_ON_APP=false
    SHOW_DESKTOP=true
else
    CLOCK_ON_APP=true
    TRAY_ON_APP=true
    SHOW_DESKTOP=true
fi
if [ "$PANEL_EXTRAS" = 1 ]; then
    PANEL_EXTRAS_JS=true
else
    PANEL_EXTRAS_JS=false
fi

TASK_SHOW_TEXT_VAL=false; TASK_TEXT_POS_VAL=bottom; TASK_GROUPING_VAL=0
if [ "$WINDOWS_STYLE" = 1 ]; then
    TASK_SHOW_TEXT_VAL=true; TASK_TEXT_POS_VAL=besideIcon; TASK_GROUPING_VAL=0
fi
[ "$PANEL_TASK_STYLE" = "icons" ] && TASK_SHOW_TEXT_VAL=false && TASK_TEXT_POS_VAL=bottom
[ "$PANEL_TASK_STYLE" = "textbesideicons" ] && TASK_SHOW_TEXT_VAL=true && TASK_TEXT_POS_VAL=besideIcon
[ "$PANEL_TASK_STYLE" = "text" ] && TASK_SHOW_TEXT_VAL=true && TASK_TEXT_POS_VAL=bottom
[ "$PANEL_NO_GROUPING" = 1 ] && TASK_GROUPING_VAL=1

build_payload() {
    # Quoting in this line is load-bearing twice over. The heredoc is quoted
    # ('JS'), so \"$urls\" is literal text in the payload and sed has to
    # replace it; the quotes must therefore be escaped for the SHELL as well
    # (\"), or the shell consumes them and sed searches for a bare $urls that
    # the body never contains. And the delimiter is @, not |, because
    # PIN_JOINED joins the URLs with "||" — with '|' the substitution dies with
    # "unknown option to `s'" and the payload ships with an unexpanded $urls,
    # which then pins zero apps.
    build_js "$PIN_JOINED" \
        | sed -e "s@URLS=\"\$urls\"@URLS=\"$PIN_JOINED\"@g" \
              -e "s|\$APP_HIDING|$APP_HIDING|g" \
              -e "s|CLOCK_ON_APP=\$CLOCK_ON_APP|CLOCK_ON_APP=$CLOCK_ON_APP|g" \
              -e "s|TRAY_ON_APP=\$TRAY_ON_APP|TRAY_ON_APP=$TRAY_ON_APP|g" \
              -e "s|SHOW_DESKTOP=\$SHOW_DESKTOP|SHOW_DESKTOP=$SHOW_DESKTOP|g" \
              -e "s|PANEL_EXTRAS=\$PANEL_EXTRAS|PANEL_EXTRAS=$PANEL_EXTRAS_JS|g" \
              -e "s|app.floating = true|app.floating = $PANEL_FLOATING|g" \
              -e "s|app.floating = false|app.floating = $PANEL_FLOATING|g" \
              -e "s|app.height = 40|app.height = $PANEL_THICKNESS|g" \
              -e "s|app.alignment = \"center\"|app.alignment = \"$PANEL_ALIGNMENT\"|g" \
              -e "s|\$PANEL_THICKNESS|$PANEL_THICKNESS|g" \
              -e "s|\$PANEL_FLOATING|$PANEL_FLOATING|g" \
              -e "s|\$PANEL_ALIGNMENT|$PANEL_ALIGNMENT|g" \
              -e "s|\$WINDOWS_STYLE|$WINDOWS_STYLE|g" \
              -e "s|\$TASK_SHOW_TEXT|$TASK_SHOW_TEXT_VAL|g" \
              -e "s|\$TASK_TEXT_POS|$TASK_TEXT_POS_VAL|g" \
              -e "s|\$TASK_GROUPING|$TASK_GROUPING_VAL|g"

}

if [ "$DRY_RUN" = 1 ]; then
    echo -e "${CYAN}--- DRY RUN: payload that WOULD be sent to plasmashell ---${NC}"
    build_payload
    echo -e "${CYAN}--- backups would go to: ${NC}$BACKUP_PATH"
    echo -e "${CYAN}                                ${NC}$SHELLRC_BACKUP"
    echo -e "${YELLOW}Nothing was changed.${NC}"
    exit 0
fi

# --- 2. Backup before touching anything --------------------------------------
if [ ! -f "$APPSLETSRC" ]; then
    log_warn "No existing panel config at $APPSLETSRC — treating as a clean slate."
else
    if [ -e "$BACKUP_PATH" ]; then
        log_info "Existing backup at $BACKUP_PATH — rotating it in place (one backup kept)."
        rm -f "$BACKUP_PATH.bak"
        mv "$BACKUP_PATH" "$BACKUP_PATH.bak"
    fi
    if cp -a "$APPSLETSRC" "$BACKUP_PATH"; then
        log_ok "Panel layout backed up to $BACKUP_PATH"
    else
        log_err "Could not back up $APPSLETSRC — aborting."
        exit 1
    fi
fi

# The geometry file is backed up separately and its absence is NOT fatal: a
# session that has never had a panel configured may not have the file yet, and
# there is nothing in it to lose.
if [ -f "$SHELLRC" ]; then
    if [ -e "$SHELLRC_BACKUP" ]; then
        rm -f "$SHELLRC_BACKUP.bak"
        mv "$SHELLRC_BACKUP" "$SHELLRC_BACKUP.bak"
    fi
    if cp -a "$SHELLRC" "$SHELLRC_BACKUP"; then
        log_ok "Panel geometry backed up to $SHELLRC_BACKUP"
    else
        log_err "Could not back up $SHELLRC — aborting."
        exit 1
    fi
else
    log_warn "No $SHELLRC yet — nothing to back up there."
fi

# The theme step (46-applyThemes.sh) restarts plasmashell by applying the
# color scheme and Global Theme, and run.sh orders steps by filename, so we
# routinely arrive here while plasmashell is still coming back up. Calling
# evaluateScript in that window makes qdbus report
#   Cannot find 'org.kde.PlasmaShell.evaluateScript' in object /PlasmaShell
# which reads like a missing API but is really an unregistered object — the
# step then exits 1 with the panel untouched. Wait for a real scripting
# round-trip before touching the layout.
if ! wait_for_plasmashell 30; then
    log_err "plasmashell did not come up within 30s — not touching the panel."
    log_err "Is a Plasma session actually running? Try: pgrep -a plasmashell"
    exit 1
fi

APPLY_OUT="$ACTIVE_USER_HOME/.config/plasmaPanel-apply.log"
# Both streams are captured. qdbus prints "Error: org.freedesktop.DBus.Error.Failed"
# and the JS exception on STDOUT, not stderr, so sending stdout to /dev/null
# produced a failure with a completely empty log file — the step reported
# "evaluateScript failed" and showed nothing, which is exactly how the
# ReferenceError above went unnoticed until it was run against a live session.
if ! run_as_user "$DBUS" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript \
    >"$APPLY_OUT" 2>&1 "$(build_payload)"; then
    log_err "evaluateScript failed ($APPLY_OUT):"
    # The last line is often a backtrace; the line above it is the actual
    # message ("SyntaxError: ...", "ReferenceError: ... at line N").
    if [ -s "$APPLY_OUT" ]; then
        tail -n 2 "$APPLY_OUT" | while IFS= read -r l; do log_err "  $l"; done
    else
        log_err "  (no output captured from qdbus)"
    fi
    log_err "To restore:  bash scripts/47-plasmaPanel.sh --restore"
    exit 1
fi

PIN_COUNT=""
[ -n "$PIN_JOINED" ] && PIN_COUNT=" with ${#PIN_URLS[@]} pinned apps"
if [ "$TRAY_PANEL" = 1 ]; then
    log_ok "Panel rebuilt: floating app bar$PIN_COUNT, icon-tasks, pager,$([ "$PANEL_EXTRAS" = 1 ] && echo " activity bar, clipboard,")"
    log_ok "Plus a slim auto-hiding tray/clock bar at the top right (340px)."
else
    log_ok "Panel rebuilt: one floating bar$PIN_COUNT — Kickoff, icon-tasks, pager, tray, compact clock, show-desktop."
    [ "$PANEL_EXTRAS" = 1 ] && log_ok "Extras kept: clipboard history, activity bar."
    log_ok "Want either back? --tray-panel (second bar) / --extras (those applets)."
fi

# Not configurable from here, and worth saying rather than leaving the user to
# wonder why the bar has square corners: rounded panel corners and force-blur
# of arbitrary windows are Plasma 6.4+/6.5+ features (the Better Blur DX KWin
# effect refuses to build against 6.3), so they are listed as a manual
# checklist instead of being written speculatively.
cat << EOF

$(log_info "Not scriptable on Plasma $PLASMA_VERSION — manual, if you want them:")
$(log_info "  rounded panel corners      Plasma 6.4+ only (System Settings > Desktop > Panels)")
$(log_info "  blur behind the bars       System Settings > Desktop Effects > Blur")
$(log_info "  minimise-all shortcut       System Settings > Shortcuts > KWin > Minimize all windows")
$(log_info "  (used if the Show Desktop button is ever inert on your session)")

$(log_warn "A plasmashell restart makes everything fully settle (skip if it already looks right):")
EOF

# There is no kstart6 on Debian 13 — kde-cli-tools ships kquitapp6 but not the
# matching kstart6, so the old hint here named a command that cannot run and
# left people with no desktop. Fall back to launching plasmashell directly,
# detached so it survives the shell that started it.
if command_exists kstart6; then
    log_warn "  kquitapp6 plasmashell && sleep 2 && kstart6 plasmashell &"
elif command_exists kquitapp6; then
    log_warn "  kquitapp6 plasmashell && sleep 2 && setsid plasmashell >/dev/null 2>&1 &"
else
    log_warn "  plasmashell is already running — just log out and back in."
fi
log_warn "Undo: bash scripts/47-plasmaPanel.sh --restore"
