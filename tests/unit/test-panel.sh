#!/usr/bin/env bash
# tests/unit/test-panel.sh — tier 2: 47-plasmaPanel.sh payload tests.
#
# The panel is built by a generated JavaScript string that runs inside a live
# plasmashell, so none of it can be exercised here directly. What CAN be
# checked, and is checked, is that the payload says the right things — because
# every wrong value in it fails SILENTLY:
#
#   - an unknown applet id (addWidget("...spacer")) raises nothing and adds
#     nothing, so the panel is simply missing a widget;
#   - a misspelled config key (writeConfig("filling", false) instead of
#     "expanding") persists a key nothing reads, and the spacer keeps its
#     default of true and stretches the "floating" bar across the screen;
#   - a property value the setter silently ignores (hiding = "windowsgobelow",
#     opacity = anything at all) leaves the panel at its default and reports
#     nothing;
#   - an undefined identifier (panel.currentConfigGroup) throws a ReferenceError
#     that aborts the whole payload on the first statement.
#
# The values below were read out of the Plasma 6.3.6 sources rather than
# remembered (shell/panelview.cpp for what is stored, shell/panelview.h for the
# enum ordinals) and then PROBED against the running plasmashell, because the
# source and the scripting API disagree in a way neither documents: the setter
# accepts only a subset of the enum names.
#
#   Persisting a panel property is the property ASSIGNMENT, not writeConfig.
#   PanelView::config() is [PlasmaViews][Panel <id>][Horizontal <w>], and the
#   setters write into config().parent() — while the scripting wrapper's
#   writeConfig targets the CONTAINMENT group, [Containments][<id>]. So
#   app.writeConfig("floating", true) persists nothing at all, and the payload
#   used to lead with exactly that line while a comment insisted the opposite.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

SANDBOX="$(make_tmp devmkde-panel)"
trap 'cleanup_dirs "$SANDBOX"' EXIT

PANEL="$REPO_ROOT/scripts/47-plasmaPanel.sh"

# --- 1. --dry-run must be read-only and must print a payload ---------------
OUT="$SANDBOX/dryrun.js"
bash "$PANEL" --dry-run > "$OUT" 2>"$SANDBOX/dryrun.err"

# Same payload with its full-line JS comments removed. The heredoc is quoted
# now, so the comments reach the generated file verbatim — which is correct for
# plasmashell and means any "this must not appear" assertion has to look at
# code only, or it trips over the header explaining the very mistake.
OUT_CODE="$SANDBOX/dryrun.code.js"
grep -v '^[[:space:]]*//' "$OUT" > "$OUT_CODE"

t_assert_grep "dry-run announces itself" "DRY RUN" "$OUT"
t_assert_grep "dry-run says nothing was changed" "Nothing was changed" "$OUT"
t_assert_grep "dry-run shows where the backup would go" "pre-plasmaPanel" "$OUT"

# --- 2. Applets: only plugin ids that exist on this box ---------------------
t_assert_grep "app bar adds Kickoff"        'addWidget\("org\.kde\.plasma\.kickoff"\)'      "$OUT"
t_assert_grep "app bar adds the task manager" 'addWidget\("org\.kde\.plasma\.icontasks"\)'   "$OUT"
t_assert_grep "app bar adds the pager"      'addWidget\("org\.kde\.plasma\.pager"\)'       "$OUT"
t_assert_grep "app bar adds the system tray" 'addWidget\("org\.kde\.plasma\.systemtray"\)' "$OUT"
t_assert_grep "a digital clock is added"    'addWidget\("org\.kde\.plasma\.digitalclock"\)' "$OUT"
# Clipboard history and the activity bar are OFF by default: the addWidget lines
# still exist in the payload, guarded by the PANEL_EXTRAS branch, so the
# meaningful assertions are the two below — that the guard is false by default
# and true under --extras (section 7). Asserting the addWidget line alone would
# have passed just as happily while the default layout kept adding both.
t_assert_grep "clipboard history exists behind the extras guard" \
    'addWidget\("org\.kde\.plasma\.clipboard"\)' "$OUT"
t_assert_grep "activity bar exists behind the extras guard" \
    'addWidget\("org\.kde\.plasma\.activitybar"\)' "$OUT"

# The spacer plugin id. "org.kde.plasma.spacer" does not exist: addWidget
# swallows the unknown id and the widget silently never appears.
t_assert_grep "spacer uses the real panelspacer plugin id" \
    'addWidget\("org\.kde\.plasma\.panelspacer"\)' "$OUT"
t_assert_not_grep "no invented org.kde.plasma.spacer id" \
    'addWidget\("org\.kde\.plasma\.spacer"\)' "$OUT"

# Every applet id in the payload must be one that is installed, so a typo can
# never reach a live session. Checked against the system's own plasmoids dir
# when it is readable, and skipped otherwise (a build container has none).
PLASMOIDS="/usr/share/plasma/plasmoids"
if [ -d "$PLASMOIDS" ]; then
    unknown=""
    for id in $(grep -o 'addWidget("org\.kde\.plasma\.[a-z0-9]*"' "$OUT" | sed 's/addWidget("//;s/"//'); do
        [ -d "$PLASMOIDS/$id" ] || unknown="$unknown $id"
    done
    t_assert_eq "every applet id in the payload is installed" "" "$unknown"
else
    t_ok; t_ok
fi

# --- 3. Spacers must be non-expanding (or the bar is not floating) ---------
t_assert_grep "spacers set expanding=false" 'sp\.writeConfig\("expanding", false\)' "$OUT"
t_assert_grep "spacers use the real length key" 'sp\.writeConfig\("length", len\)' "$OUT"
t_assert_not_grep "no invented 'filling' key"  'writeConfig\("filling"'  "$OUT"
t_assert_not_grep "no invented spacer 'thickness' key" 'sp\.writeConfig\("thickness"' "$OUT"
# Both panels get a leading AND a trailing spacer, so the widgets are centred
# in the floating bar instead of pinned to its start.
t_assert_eq "spacer is added on both ends of the app bar" "2" \
    "$(grep -c '^[[:space:]]*addSpacer(app, ' "$OUT")"
t_assert_grep "tray bar has its own spacer" '^[[:space:]]*addSpacer\(tray, ' "$OUT"

# --- 4. Panel properties: values that actually exist -----------------------
t_assert_grep "app bar is at the bottom"  'app\.location = "bottom"' "$OUT"
t_assert_grep "app bar is floating"       'app\.floating = true'     "$OUT"
t_assert_grep "app bar is centred"       'app\.alignment = "center"' "$OUT"
t_assert_grep "app bar is fit-to-content" 'app\.lengthMode = "fit"'   "$OUT"
# No opacity assertion: the setter accepts no value at all. Every string and
# every integer was probed and ignored, so the payload must not pretend.
t_assert_not_grep "no unreachable opacity assignment" '\.opacity = ' "$OUT_CODE"
t_assert_grep "app bar has a 40px height" 'app\.height = 40'         "$OUT"
# Persisted form of floating/alignment: in the ROOT config group, not [General].
# These two are the ones that were wrong on the live machine. writeConfig puts
# floating/alignment in [Containments][<id>]; PanelView reads
# [PlasmaViews][Panel <id>]. The assignment is the persist.
t_assert_not_grep "floating is not writeConfig'd into the containment group" \
    'app\.writeConfig\("floating"' "$OUT_CODE"
t_assert_not_grep "alignment is not writeConfig'd into the containment group" \
    'app\.writeConfig\("alignment"' "$OUT_CODE"
t_assert_not_grep "floating is NOT written into [General]" \
    'app\.currentConfigGroup = \["General"\]' "$OUT"

t_assert_grep "tray bar is at the top"      'tray\.location = "top"'    "$OUT"
t_assert_grep "tray bar is right-aligned"   'tray\.alignment = "right"' "$OUT"
t_assert_grep "tray bar uses a custom length" 'tray\.lengthMode = "custom"' "$OUT"
t_assert_grep "tray bar pins its min length"  'tray\.minimumLength = 340' "$OUT"
t_assert_grep "tray bar pins its max length"  'tray\.maximumLength = 340' "$OUT"
t_assert_grep "tray bar auto-hides"          'tray\.hiding = "autohide"'  "$OUT"
t_assert_not_grep "no unreachable opacity assignment on the tray" 'tray\.opacity = ' "$OUT_CODE"
# Order matters: with the bounds set before the applets are added, the
# content-driven relayout put the length back and the bar measured 633px.
# FIRST bounds assignment against the LAST widget: a duplicated pair, one copy
# moved up above the widgets, is exactly how this regresses in practice, and
# looking only at the last occurrence would not see it.
_bounds_line="$(grep -n 'tray\.maximumLength = ' "$OUT" | head -1 | cut -d: -f1)"
_tray_widgets_line="$(grep -n 'tray\.addWidget' "$OUT" | tail -1 | cut -d: -f1)"
if [ -n "$_bounds_line" ] && [ -n "$_tray_widgets_line" ] \
   && [ "$_bounds_line" -gt "$_tray_widgets_line" ]; then t_ok
else t_fail "tray length bounds must be set after every tray widget (bounds line=$_bounds_line, last tray widget line=$_tray_widgets_line)"; fi
t_assert_grep "tray bar is slim"             'tray\.height = 32'          "$OUT"

# Only values Plasma 6.3.6 accepts. A misspelling here is a no-op, not an error.
t_assert_not_grep "no invalid hiding value"      'hiding = "normal"' "$OUT"
t_assert_not_grep "no invalid opacity value"     'opacity = "adaptive"' "$OUT"
t_assert_not_grep "no invalid lengthMode value"  'lengthMode = "fill"' "$OUT"
t_assert_not_grep "no invalid alignment value"   'alignment = "middle"' "$OUT"
t_assert_not_grep "no invalid location value"    'location = "desktop"' "$OUT"

# Setter-accepted values, from probing the live plasmashell. An unaccepted
# value is worse than a wrong one: the property reads back as its default and
# nothing is logged, so "hiding = windowsgobelow" looked like it worked.
t_assert_not_grep "hiding is not writeConfig'd"  'writeConfig\("hiding"' "$OUT_CODE"
t_assert_not_grep "lengthMode is not writeConfig'd" 'writeConfig\("lengthMode"' "$OUT_CODE"
# The setter takes lowercased enum names; "WindowsGoBelow" with capitals and
# the "Panel"-suffixed spellings are what it does not take.
t_assert_not_grep "hiding uses the lowercased enum name" 'hiding = "WindowsGoBelow"' "$OUT_CODE"
t_assert_grep "app bar hiding is a value the setter accepts" \
    'app\.hiding = "(none|dodgewindows|windowsgobelow)"' "$OUT"

# --- 4b. Where panel state is stored, and what --restore has to cover -------
# Panel geometry goes to plasmashellrc ([PlasmaViews][Panel <id>][Horizontal
# <w>]) — PanelView::panelConfig() — while desktop-appletsrc keeps only
# [Containments] and [Applets]. Backing up the appletsrc alone produced a
# backup that could not be restored in full: the layout came back, the floating
# and length settings did not.
t_assert_grep "shell geometry file is identified" \
    'SHELLRC=".*\.config/plasmashellrc"' "$PANEL"
t_assert_grep "shell geometry file is backed up" \
    'cp -a "\$SHELLRC" "\$SHELLRC_BACKUP"' "$PANEL"
t_assert_grep "shell geometry file is restored" \
    'cp -a "\$SHELLRC_BACKUP" "\$SHELLRC"' "$PANEL"
# A restore that only warns about the missing geometry backup is better than one
# that claims success while leaving the bars floating.
t_assert_grep "a restore without the geometry backup says so" \
    'log_warn "No \$SHELLRC_BACKUP' "$PANEL"

# --- 4c. The payload must reach plasmashell unexpanded ---------------------
# The heredoc was unquoted, so the shell processed the JS body first: a
# backticked word in a comment ran as a command substitution ("length: command
# not found"), comments were silently emptied, and the payload still applied.
# The symptom is stderr from a successful run.
t_assert_grep "the payload heredoc is quoted" "<< 'JS'" "$PANEL"
t_assert_not_grep "the payload heredoc is not left unquoted" '<< JS$' "$PANEL"
# PIN_JOINED joins the pinned-app URLs with "||", so a sed delimiter of '|'
# aborts the substitution and the bar ships with no launchers at all.
t_assert_grep "URL list substitution avoids the | delimiter" \
    's@URLS=' "$PANEL"
# Assert the OUTCOME rather than the quoting: the payload must carry the real
# URL list. Escaping the substitution correctly needs the quotes escaped for
# the shell as well, and getting that wrong leaves a literal $urls in the
# payload — which pins nothing and reports no error.
t_assert_grep "pinned app URLs are substituted into the payload" \
    'URLS="applications:' "$OUT"
t_assert_not_grep "no unsubstituted \$urls left in the payload" \
    'URLS="\$urls' "$OUT"
t_assert_grep "the URL separator is the one the payload splits on" \
    'u\.split\("\\|\\|"\)' "$OUT"

# --- 5. Task manager config: only keys that exist in Plasma 6.3 -------------
# minimumSize / showLauncherOnContextClick were Plasma 5 spellings and are NOT
# in Plasma 6.3's taskmanager config: writing them persists keys nothing reads.
t_assert_grep "task manager limited to real keys" \
    'tasks\.writeConfig\("showOnlyCurrentScreen", false\)' "$OUT"
t_assert_not_grep "no Plasma 5 minimumSize key"      'tasks\.writeConfig\("minimumSize"' "$OUT"
t_assert_not_grep "no Plasma 5 context-click key"    'tasks\.writeConfig\("showLauncherOnContextClick"' "$OUT"

# --- 5b. Kickoff popup: a grid, from a key that exists ---------------------
# Plasma 6.3's kickoff has NO iconSize key, so "make the launcher icon bigger"
# is not something the applet can do at all. That is asserted against the
# applet's own shipped main.xml instead of being remembered, because writing an
# invented key persists it where nothing reads it and the panel looks identical
# after the next login — the failure this repo keeps paying for elsewhere.
t_assert_grep "kickoff popup uses a grid of favourites" \
    'kickoff\.writeConfig\("favoritesDisplay", 0\)' "$OUT"
KICKOFF_XML="/usr/share/plasma/plasmoids/org.kde.plasma.kickoff/contents/config/main.xml"
if [ -f "$KICKOFF_XML" ]; then
    t_assert_grep "favoritesDisplay is a real kickoff key" \
        'name="favoritesDisplay"' "$KICKOFF_XML"
    t_assert_not_grep "no invented iconSize key (kickoff has none)" \
        'name="iconSize"' "$KICKOFF_XML"
else
    t_ok; t_ok
fi

# --- 6. Teardown must not abort halfway through ---------------------------
# A single widget that refuses to be removed used to throw out of forEach and
# leave a half-emptied panel with the fresh one never built.
t_assert_grep "widget removal is guarded"   'try \{ w\.remove\(\); \} catch' "$OUT"
t_assert_grep "panel removal is guarded"     'try \{ p\.remove\(\); \} catch' "$OUT"

# --- 7. Flags ---------------------------------------------------------------
# The default is ONE floating bar with everything on it. That is a decision, so
# it is asserted: TRAY_ON_APP=true is what puts the tray and clock on the app
# bar, and PANEL_EXTRAS=false is what keeps the clipboard and activity bar off.
t_assert_grep "by default the tray and clock are on the app bar" "TRAY_ON_APP=true" "$OUT"
t_assert_grep "by default the clock uses the short date"        "CLOCK_ON_APP=true" "$OUT"
t_assert_grep "by default the extras are off"                   "PANEL_EXTRAS=false" "$OUT"

OUT2="$SANDBOX/dryrun-tray-panel.js"
bash "$PANEL" --dry-run --tray-panel > "$OUT2" 2>&1
t_assert_grep "--tray-panel moves the tray off the app bar" "TRAY_ON_APP=false" "$OUT2"
t_assert_grep "--tray-panel moves the clock off the app bar" "CLOCK_ON_APP=false" "$OUT2"
t_assert_grep "--tray-panel does not bring the extras back" "PANEL_EXTRAS=false" "$OUT2"

# --no-tray-panel used to BE the single-panel layout. It is now the default, so
# the flag is a no-op kept so old scripts and docs do not start erroring — this
# pins that it still parses and still means "one bar".
OUT2B="$SANDBOX/dryrun-no-tray-flag.js"
bash "$PANEL" --dry-run --no-tray-panel > "$OUT2B" 2>&1
t_assert_grep "--no-tray-panel still means one bar" "TRAY_ON_APP=true" "$OUT2B"

OUT2C="$SANDBOX/dryrun-extras.js"
bash "$PANEL" --dry-run --extras > "$OUT2C" 2>&1
t_assert_grep "--extras turns the extras on"  "PANEL_EXTRAS=true" "$OUT2C"
t_assert_grep "--extras keeps the single bar" "TRAY_ON_APP=true" "$OUT2C"

OUT3="$SANDBOX/dryrun-dodge.js"
bash "$PANEL" --dry-run --dodge-windows > "$OUT3" 2>&1
t_assert_grep "--dodge-windows makes the app bar dodge" 'app\.hiding = "dodgewindows"' "$OUT3"
t_assert_grep "--dodge-windows leaves the tray bar auto-hiding" 'tray\.hiding = "autohide"' "$OUT3"

# Default: the app bar stays put and only the tray bar hides.
# "windowsgobelow" (panelVisibility=3) is correct and persists. It reads back
# as "none" through the scripting getter, which cannot tell 0 from 3 — an
# earlier revision of both the script and this test "fixed" that by switching
# to "none", i.e. always visible AND space reserved, the opposite of the
# intent. Verified in plasmashellrc, where the value lands as panelVisibility=3.
t_assert_grep "by default the app bar stays on screen" 'app\.hiding = "windowsgobelow"' "$OUT"
t_assert_grep "by default the tray bar auto-hides"    'tray\.hiding = "autohide"'      "$OUT"

# Every interpolated value must be a literal by the time it reaches plasmashell:
# an unexpanded $VAR there is a syntax error at the best and a silently wrong
# panel at the worst.
t_assert_not_grep "no shell variables left unexpanded" '\$[A-Za-z_]' "$OUT"

# --- 8. The payload must be syntactically valid JS -------------------------
# No node in this environment, so balance the brackets with the strings and
# comments stripped first: that is what catches a heredoc edit that loses a
# closing brace.
if command -v node >/dev/null 2>&1; then
    sed -n '/^var old = panels();/,/^}$/p' "$OUT" > "$SANDBOX/payload.js"
    t_assert "payload parses as JS under node" node --check "$SANDBOX/payload.js"
else
    sed -n '/^var old = panels();/,/^}$/p' "$OUT" > "$SANDBOX/payload.js"
    t_assert_braces_balanced() {
        python3 - "$SANDBOX/payload.js" <<'PY'
import re, sys
src = open(sys.argv[1]).read()
s = re.sub(r'/\*.*?\*/', '', src, flags=re.S)
s = re.sub(r'//[^\n]*', '', s)
s = re.sub(r'"(\\.|[^"\\])*"', '""', s)
pairs = {')': '(', ']': '[', '}': '{'}
stack = []
for ch in s:
    if ch in '([{':
        stack.append(ch)
    elif ch in ')]}':
        if not stack or stack[-1] != pairs[ch]:
            sys.exit(1)
        stack.pop()
sys.exit(0 if not stack else 1)
PY
    }
    t_assert "payload brackets are balanced" t_assert_braces_balanced
fi

# --- 9. Options and docs ---------------------------------------------------
t_assert_grep "--restore is documented in the header" '\-\-restore' "$PANEL"
t_assert_grep "the header explains the property/config-key split" \
    'panelVisibility' "$PANEL"
t_assert "an unknown option is rejected" \
    bash -c "! bash '$PANEL' --not-a-real-option >/dev/null 2>&1"
# A dry run must not touch the real panel config, and in particular must not
# rotate its backup. Compared by mtime rather than by existence: a real run
# during development leaves a backup behind, and asserting the file is absent
# would then fail for a reason that has nothing to do with the dry run.
HOME_CFG="$(getent passwd "$(id -un)" | cut -d: -f6)/.config"
BACKUP="$HOME_CFG/plasma-org.kde.plasma.desktop-appletsrc.pre-plasmaPanel"
before=""
[ -e "$BACKUP" ] && before="$(stat -c '%Y:%s' "$BACKUP")"
bash "$PANEL" --dry-run >/dev/null 2>&1
after=""
[ -e "$BACKUP" ] && after="$(stat -c '%Y:%s' "$BACKUP")"
t_assert_eq "a dry run leaves the panel backup untouched" "$before" "$after"

# And --help must describe the real options rather than failing.
HELP="$SANDBOX/help.txt"
bash "$PANEL" --help > "$HELP" 2>&1
t_assert_grep "--help lists --dry-run"    '\-\-dry-run'   "$HELP"
t_assert_grep "--help lists --restore"    '\-\-restore'   "$HELP"
t_assert_grep "--help lists --tray-panel" '\-\-tray-panel' "$HELP"
t_assert_grep "--help lists --extras"     '\-\-extras'    "$HELP"
t_assert_grep "--help lists --dodge-windows" '\-\-dodge-windows' "$HELP"

t_summary "unit/panel"
