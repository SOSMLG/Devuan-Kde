#!/usr/bin/env bash
# tests/negative-controls.sh — prove the test suite actually fails.
#
# A green suite proves nothing on its own: the easiest way to get all-green is
# to delete the assertions. So for each regression this release actually fixed,
# inject it into a scratch COPY of the repo, run the tier that is supposed to
# catch it, and require that tier to FAIL. The real repo is never modified.
#
# Read-only with respect to the repo, root, apt and the network; it writes only
# to a temp copy.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if ! command -v python3 >/dev/null 2>&1; then
    echo "negative-controls: python3 unavailable, skipping"
    exit 0
fi

TOTAL=0
CAUGHT=0
MISSED=""

# inject <name> <tier-cmd...> -- <file> <line-to-append>
#
# Copies the repo, APPENDS <line-to-append> to <file>, runs <tier-cmd> against
# the copy, and requires a non-zero exit.
#
# Appending rather than string-replacing is deliberate. The first version of
# this harness replaced old-text with new-text, and because a replace hits the
# FIRST occurrence, most injections landed inside a comment -- where the guard
# that strips comments cannot see them -- so the suite "passed" while carrying
# the injected regression. Four of seventeen controls were false greens for
# exactly that reason. An appended line is unambiguous: it is code, it is at the
# end of the file, and there is no question about what it replaced.
#
# addfile <name> <tier-cmd...> -- <path> <line>
#
# Creates a brand-new file in the copy. Necessary because several guards walk
# the tree rather than execute it: appending `touch scripts/49-x.sh` to another
# script looks like it adds a step, but nothing in the suite runs that script,
# so the file never appears and the control passes vacuously.
addfile() {
    local name="$1"; shift
    local -a cmd=()
    while [ "$1" != "--" ]; do cmd+=("$1"); shift; done
    shift
    local path="$1" line="$2"

    TOTAL=$((TOTAL + 1))
    local work
    work="$(mktemp -d /tmp/devmkde-negctl.XXXXXX)"
    ( cd "$REPO_ROOT" && tar -cf - \
        scripts run.sh install.sh tests themes assets .gitignore VERSION RELEASE.md README.md 2>/dev/null ) \
        | ( cd "$work" && tar -xf - ) 2>/dev/null
    mkdir -p "$(dirname "$work/$path")"
    printf '%s\n' "$line" >> "$work/$path"

    if ( cd "$work" && "${cmd[@]}" ) >/dev/null 2>&1; then
        echo "  [MISSED] $name — the suite still passed with the bug injected"
        MISSED="$MISSED\n    $name"
    else
        echo "  [CAUGHT] $name"
        CAUGHT=$((CAUGHT + 1))
    fi
    rm -rf "$work"
}

# rmfile <name> <tier-cmd...> -- <path>
#
# Removes a file from the copy. Needed for guards that assert a file EXISTS:
# appending to (or editing) some other file cannot make a bundled asset vanish,
# so a control built with inject would "pass" for a reason unrelated to the
# guard it is meant to prove works.
rmfile() {
    local name="$1"; shift
    local -a cmd=()
    while [ "$1" != "--" ]; do cmd+=("$1"); shift; done
    shift
    local path="$1"

    TOTAL=$((TOTAL + 1))
    local work
    work="$(mktemp -d /tmp/devmkde-negctl.XXXXXX)"
    ( cd "$REPO_ROOT" && tar -cf - \
        scripts run.sh install.sh tests themes assets .gitignore VERSION RELEASE.md README.md 2>/dev/null ) \
        | ( cd "$work" && tar -xf - ) 2>/dev/null
    rm -f "$work/$path"

    if ( cd "$work" && "${cmd[@]}" ) >/dev/null 2>&1; then
        echo "  [MISSED] $name — the suite still passed with the bug injected"
        MISSED="$MISSED\n    $name"
    else
        echo "  [CAUGHT] $name"
        CAUGHT=$((CAUGHT + 1))
    fi
    rm -rf "$work"
}

# sub <name> <tier-cmd...> -- <file> <old> <new> is kept for the cases that
# genuinely need to disable an existing check rather than add a new one.
inject() {
    local name="$1"; shift
    local -a cmd=()
    while [ "$1" != "--" ]; do cmd+=("$1"); shift; done
    shift
    local file="$1" line="$2"

    TOTAL=$((TOTAL + 1))
    local work
    work="$(mktemp -d /tmp/devmkde-negctl.XXXXXX)"
    ( cd "$REPO_ROOT" && tar -cf - \
        scripts run.sh install.sh tests themes assets .gitignore VERSION RELEASE.md README.md 2>/dev/null ) \
        | ( cd "$work" && tar -xf - ) 2>/dev/null

    if [ ! -f "$work/$file" ]; then
        echo "  [SKIP] $name — $file does not exist"
        MISSED="$MISSED\n    $name (no such file)"
        rm -rf "$work"
        return
    fi
    printf '%s\n' "$line" >> "$work/$file"

    if ( cd "$work" && "${cmd[@]}" ) >/dev/null 2>&1; then
        echo "  [MISSED] $name — the suite still passed with the bug injected"
        MISSED="$MISSED\n    $name"
    else
        echo "  [CAUGHT] $name"
        CAUGHT=$((CAUGHT + 1))
    fi
    rm -rf "$work"
}

# sub <name> <tier-cmd...> -- <file> <old> <new>
sub() {
    local name="$1"; shift
    local -a cmd=()
    while [ "$1" != "--" ]; do cmd+=("$1"); shift; done
    shift
    local file="$1" old="$2" new="$3"

    TOTAL=$((TOTAL + 1))
    local work
    work="$(mktemp -d /tmp/devmkde-negctl.XXXXXX)"
    ( cd "$REPO_ROOT" && tar -cf - \
        scripts run.sh install.sh tests themes assets .gitignore VERSION RELEASE.md README.md 2>/dev/null ) \
        | ( cd "$work" && tar -xf - ) 2>/dev/null

    if ! python3 - "$work/$file" "$old" "$new" <<'PY'
import sys, pathlib
path = pathlib.Path(sys.argv[1])
old, new = sys.argv[2], sys.argv[3]
t = path.read_text(encoding="utf-8", errors="replace")
if old not in t:
    sys.stderr.write("injection target not found\n")
    sys.exit(3)
path.write_text(t.replace(old, new, 1), encoding="utf-8")
PY
    then
        echo "  [SKIP] $name — could not inject (target text moved? update this script)"
        MISSED="$MISSED\n    $name (injection failed)"
        rm -rf "$work"
        return
    fi

    if ( cd "$work" && "${cmd[@]}" ) >/dev/null 2>&1; then
        echo "  [MISSED] $name — the suite still passed with the bug injected"
        MISSED="$MISSED\n    $name"
    else
        echo "  [CAUGHT] $name"
        CAUGHT=$((CAUGHT + 1))
    fi
    rm -rf "$work"
}

echo "negative controls — each regression injected into a scratch copy"
echo
# inject_sed <name> <tier-cmd...> -- <file> <sed-expression>
#
# Same contract as sub(), but the mutation is a sed expression instead of a
# literal string replacement, which is what makes it possible to scope an edit
# to ONE function inside themes/palettes.sh. Needed since the palettes were
# consolidated: `C_15=ffffff` appears in nine of them, so a literal
# replace-first-match would edit the wrong palette, and appending a line puts
# the assignment outside every function body where load_palette() never runs it.
inject_sed() {
    local name="$1"; shift
    local -a cmd=()
    while [ "$1" != "--" ]; do cmd+=("$1"); shift; done
    shift
    local file="$1" expr="$2"

    TOTAL=$((TOTAL + 1))
    local work
    work="$(mktemp -d /tmp/devmkde-negctl.XXXXXX)"
    ( cd "$REPO_ROOT" && tar -cf - \
        scripts run.sh install.sh tests themes assets .gitignore VERSION RELEASE.md README.md 2>/dev/null ) \
        | ( cd "$work" && tar -xf - ) 2>/dev/null

    if [ ! -f "$work/$file" ]; then
        echo "  [SKIP] $name — $file does not exist"
        MISSED="$MISSED\n    $name (no such file)"
        rm -rf "$work"
        return
    fi
    if ! sed -i "$expr" "$work/$file" 2>/dev/null; then
        echo "  [SKIP] $name — could not inject (bad sed expression?)"
        MISSED="$MISSED\n    $name (injection failed)"
        rm -rf "$work"
        return
    fi
    # A sed that matches nothing exits 0, so verify the file actually changed.
    # Without this a typo'd range silently turns the control into a no-op that
    # "passes" because the suite is green — the failure mode this control
    # already had once.
    if cmp -s "$work/$file" "$REPO_ROOT/$file"; then
        echo "  [SKIP] $name — sed matched nothing"
        MISSED="$MISSED\n    $name (injection matched nothing)"
        rm -rf "$work"
        return
    fi

    if ( cd "$work" && "${cmd[@]}" ) >/dev/null 2>&1; then
        echo "  [MISSED] $name — the suite still passed with the bug injected"
        MISSED="$MISSED\n    $name"
    else
        echo "  [CAUGHT] $name"
        CAUGHT=$((CAUGHT + 1))
    fi
    rm -rf "$work"
}


# ── 1. The bracket bug this environment actually falls for ─────────────────
# `[ -n "$x" && "$x" = y ]` prints "[: missing ]" and STILL runs the branch.
inject "unsafe single-[ && form" bash tests/lint.sh -- \
    run.sh 'if [ -n "${XDG_SESSION_TYPE:-}" && "${XDG_SESSION_TYPE:-}" = "x11" ]; then echo x11; fi'

# ── 2. A bare sudo reappearing in a step script ───────────────────────────
inject "bare sudo in a step script" bash tests/consistency.sh -- \
    scripts/47-plasmaPanel.sh 'log_info "x"; sudo systemctl restart plasma-panel'

# ── 3. Plasma 5 kwin effects creeping back in ─────────────────────────────
inject "kwineffectsrc returns" bash tests/consistency.sh -- \
    scripts/27-fancyPlasma.sh 'kwrite_user --file kwineffectsrc --group Effect-blur --key Enabled true'

# ── 4. The Plasma 5 accent key ─────────────────────────────────────────────
inject "AccentColorFromWallpaper returns" bash tests/consistency.sh -- \
    scripts/lib/theme.sh 'kwrite_user --file kdeglobals --key AccentColorFromWallpaper false'

# ── 5. khotkeysrc returns ──────────────────────────────────────────────────
inject "khotkeysrc returns" bash tests/consistency.sh -- \
    scripts/28-kdeHotkeys.sh 'echo "~/.config/khotkeysrc" >> ~/.config/khotkeysrc'

# ── 6. metadata.desktop instead of metadata.json ───────────────────────────
inject "metadata.desktop returns" bash tests/consistency.sh -- \
    scripts/lib/theme.sh 'cp "$TMPL/metadata.desktop" "$HOME/.local/share/plasma/look-and-feel/DarkmatterTheme/metadata.desktop"'

# ── 7. A package name that does not exist ──────────────────────────────────
inject "nonexistent apt package" bash tests/apt-checks.sh -- \
    scripts/48-plasmaAddons.sh 'install_pkgs ksshaskpass nonexistent-pkg-xyz'

# NOTE: the *quoted* form of this is deliberately NOT a regression — quote
# parity is exactly how the extractor tells prose from a command, so a quoted
# help string should be ignored. The real failure mode is unquoted prose being
# harvested as package names.
inject "extractor harvests unquoted prose" bash tests/apt-checks.sh -- \
    scripts/48-plasmaAddons.sh 'apt-get install -y this and that'

# ── 9. A step with invalid phase metadata ──────────────────────────────────
# sub, not inject: the guard reads the FIRST `# DEVMKDE_PHASE:` line, so a second
# one appended at the end is ignored and the step still validates.
sub "step with a bogus DEVMKDE_PHASE" bash tests/consistency.sh -- \
    scripts/47-plasmaPanel.sh '# DEVMKDE_PHASE: optional' '# DEVMKDE_PHASE: nonsense-phase'

# ── 10. A step added without a README row ──────────────────────────────────
addfile "new step with no README row" bash tests/consistency.sh -- \
    scripts/49-brandNewStep.sh '# DEVMKDE_DESC: a step nobody documented'

# ── 11. VERSION drifting from RELEASE.md ───────────────────────────────────
sub "VERSION does not match RELEASE.md" bash tests/consistency.sh -- \
    VERSION '1.0.0' '9.9.9'

# ── 12. A palette rendering near-black instead of failing ──────────────────
# The hex2rgb bug: bash printf evaluates an invalid hex literal as 0, so a typo
# used to produce a plausible "0,0,14" instead of an error.
sub "hex2rb stops validating its input" bash tests/unit/test-theme.sh -- \
    scripts/lib/theme.sh '[[ "$h" =~ ^[0-9a-fA-F]{6}$ ]] || { echo ""; return 1; }' \
                   ': # validation removed'

# ── 13. ini_set_key trusting the write instead of verifying it ─────────────
# The whole point of ini_set_key is the read-back: kwriteconfig6 returns 0 and
# writes nothing for kcminputrc's cursorTheme, so a helper that believed the
# copy succeeded would report a cursor change that never happened.
sub "ini_set_key stops verifying what it wrote" bash tests/unit/test-common.sh -- \
    scripts/lib/common.sh '    [ "$got" = "$value" ]' \
                   '    [ -n "$got" ]'

# ── 14. load_palette inheriting a previous palette's values ────────────────
sub "load_palette stops clearing prior values" bash tests/unit/test-theme.sh -- \
    scripts/lib/theme.sh 'for v in "${_PALETTE_VARS[@]}" "${_PALETTE_OPTIONAL_VARS[@]}"; do
        unset "$v"' \
                   'for v in "${_PALETTE_NOTHING[@]}" "${_PALETTE_OPTIONAL_VARS[@]}"; do
        unset "$v"'

# ── 14. A Global Theme missing its contents/defaults ─────────────────────
# Plasma 6 resolves the applied config under contents/. Dropping it leaves a
# package that installs cleanly and then applies nothing -- the desktop keeps
# its previous color scheme with no error anywhere.
# contents/defaults is written by a redirect-heredoc block, so the injection
# drops the redirect target rather than a `cat >` command line.
sub "Global Theme stops shipping contents/defaults" bash tests/unit/test-theme.sh -- \
    scripts/lib/theme.sh '} > "$lnf_dir/contents/defaults"' \
                   '} > /dev/null'

# ── 15. A palette missing a required variable ──────────────────────────────
# Guards against the inheritance bug returning via a new palette.
# The injection has to break the palette *function*, not merely append text to
# themes/palettes.sh. Appending puts the assignment outside every function body,
# where load_palette() never runs it, so the suite stayed green for the wrong
# reason. And because all palettes now share one file, the edit must be scoped
# to darkmatter's own body: a bare replace of C_15=ffffff would hit whichever of
# the nine palettes appears first.
inject_sed "palette template rendered with a blank variable" bash tests/unit/test-theme.sh -- \
    themes/palettes.sh '/^palette_darkmatter() {$/,/^}$/ s/^C_15=.*/C_15=""/'

# A function that is never registered, and an id with no function: both are now
# possible in a single shared file, and both used to be impossible-by-layout.
inject_sed "palette function missing from PALETTE_IDS" bash tests/consistency.sh -- \
    themes/palettes.sh '/^    gruvbox$/s/^    gruvbox$//'

# ── 15b. Moe: the sanitiser, and the pin ────────────────────────────────────
# Each of these removes one guarantee that produces a silently wrong desktop
# rather than an error, so each needs its own control.
sub "Moe sanitiser stops dropping upstream's absent components" bash tests/unit/test-moe.sh -- \
    scripts/lib/moe.sh "MOE_ARCHIVE_SHA_LNF=" 'MOE_ARCHIVE_SHA_LNF_DISABLED='

inject_sed "Moe sanitiser starts copying upstream defaults verbatim" bash tests/unit/test-moe.sh -- \
    scripts/lib/moe.sh 's|^    cp -f "$engine" "$out" .*$|    cp -f "$upstream" "$out"|'

inject_sed "Moe sanitiser starts rebuilding defaults from scratch" bash tests/unit/test-moe.sh -- \
    scripts/lib/moe.sh 's|^    cp -f "$engine" "$out" .*$|    : > "$out"|'

sub "Moe stops verifying the download" bash tests/unit/test-moe.sh -- \
    scripts/lib/moe.sh 'sha256_verify "$out.part" "$want"' 'true # unverified'

# The palette keys must be written AFTER the last look-and-feel application:
# every --apply rewrites kdeglobals from the package's contents/defaults, and the
# key written before it does not survive. Deleting the re-assert is the simplest
# way to model that, and test-theme.sh's "LAST write survives" section fails --
# which is the whole point of that test existing.
sub "palette keys stop being re-asserted after the last Global Theme" bash tests/unit/test-theme.sh -- \
    scripts/lib/theme.sh '    persist_palette_keys "$home_dir" \
        || log_warn "palette keys still did not stick after the last Global Theme — check kdeglobals by hand."' \
    '    : # re-assert deleted'

# There is deliberately no "Moe stops stripping contents/layouts" control: the
# strip line was dead code (nothing copied upstream's contents in), so deleting
# it changed nothing and a control against it could only ever pass. The real
# guard is test-moe.sh's assertion that no layouts directory exists after an
# install, which is what fires if someone starts copying upstream contents.

sub "Moe stops clearing the path global before use" bash tests/unit/test-moe.sh -- \
    scripts/lib/moe.sh '    MOE_FETCHED=""' '    : # leaked from the previous call'

sub "Moe palette no longer registered" bash tests/consistency.sh -- \
    themes/palettes.sh '    moe-dark' ''

# ── 16. run.sh --list going out of numeric order ───────────────────────────
sub "steps sorted lexicographically" bash tests/unit/test-runner.sh -- \
    run.sh "find \"\$SCRIPTS_DIR\" -maxdepth 1 -type f -name '[0-9]*.sh' | sort" \
              "find \"\$SCRIPTS_DIR\" -maxdepth 1 -type f -name '[0-9]*.sh' | sort -r" 

# ── 17. Utilities leaking into the runnable list ───────────────────────────
# Break the standalone filter so a 5x utility appears in --list.
sub "5x utility leaks into --list" bash tests/unit/test-runner.sh -- \
    run.sh 'is_runnable_phase "${STEP_PHASE[$idx]}" || continue' ': # filter removed'

# ── 18. The default palette drifting between the two applying steps ─────────
sub "default palette drift between 14 and 46" bash tests/consistency.sh -- \
    scripts/46-applyThemes.sh 'DEVMKDE_DEFAULT_PALETTE:-darkmatter' \
                             'DEVMKDE_DEFAULT_PALETTE:-mocha-red'

# ── 19. A Global Theme manifest without KPackageStructure ─────────────────
# The one key whose absence is completely silent: the package still writes
# AccentColor into kdeglobals, still installs, and Plasma 6 just refuses to
# register it. AccentColor changes, colors never do, nothing complains.
sub "Global Theme metadata.json drops KPackageStructure" bash tests/unit/test-theme.sh -- \
    scripts/lib/theme.sh '    "KPackageStructure": "Plasma/LookAndFeel",' \
                             '    "KPackageStructureRenamed": "Plasma/LookAndFeel",'

# --- bundled fastfetch configs + the ButterBash pin ------------------------
rmfile "a bundled fastfetch config disappears" bash tests/consistency.sh -- \
    assets/fastfetch/devuan.jsonc

sub "ButterBash pin loosened to a branch name" bash tests/consistency.sh -- \
    scripts/22-terminalButterbash.sh \
    'BUTTERBASH_REF="${BUTTERBASH_REF:-ae194a92923c922e1baaede280940a5a256da99f}"' \
    'BUTTERBASH_REF="${BUTTERBASH_REF:-master}"'

sub "ButterBash archive checksum removed" bash tests/consistency.sh -- \
    scripts/22-terminalButterbash.sh \
    'BUTTERBASH_SHA256="${BUTTERBASH_SHA256:-0989771ec63756fa90469a7d14546b490de829c1c15cf58ac5362d40c50906c9}"' \
    'BUTTERBASH_SHA256=""'

sub "fastfetch step goes back to downloading its configs" bash tests/consistency.sh -- \
    scripts/23-fastfetchConfig.sh \
    'install_configs() {' \
    'curl -sL https://example.invalid/presets.json -o "$FF_DIR/config.jsonc"; install_configs() {'

# --- the panel --------------------------------------------------------------
# The spacer plugin id is the one that fails SILENTLY: addWidget swallows an
# unknown id, so the bar simply loses its margins and the floating layout stops
# working, with no error anywhere.
sub "panel spacer id regressed to org.kde.plasma.spacer" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'panel.addWidget("org.kde.plasma.panelspacer")' \
    'panel.addWidget("org.kde.plasma.spacer")'

sub "panel spacers made expanding again" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'sp.writeConfig("expanding", false)' \
    'sp.writeConfig("expanding", true)'

sub "panel location no longer set (both bars would land on the top edge)" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'app.location = "bottom";' \
    ''

# writeConfig targets the CONTAINMENT group while PanelView reads
# [PlasmaViews][Panel <id>]. This pair is the exact bug that shipped: the panel
# said floating, the config file said floating, and every test here passed while
# the bar stayed full width with a 633px tray.
sub "panel floating reverted to writeConfig (writes a group nothing reads)" bash tests/consistency.sh -- \
    scripts/47-plasmaPanel.sh \
    'app.floating = true;                // -> [PlasmaViews][Panel <id>] floating' \
    'app.writeConfig("floating", true);'

sub "panel alignment reverted to writeConfig" bash tests/consistency.sh -- \
    scripts/47-plasmaPanel.sh \
    'app.alignment = "center";           // -> alignment' \
    'app.writeConfig("alignment", "center");'

# No opacity line exists to write anymore: the setter accepts no value at all,
# so any assignment is a silent no-op and the log would claim translucency.
sub "panel opacity assigned again (the setter ignores every value)" bash tests/consistency.sh -- \
    scripts/47-plasmaPanel.sh \
    '// No opacity line: unreachable from the scripting API, and Adaptive is' \
    'app.opacity = "translucent";'

# One-file backup: desktop-appletsrc only. --restore then puts the layout back
# while the geometry that file never described — floating, lengths, visibility
# in plasmashellrc — stays as the script left it.
sub "panel backup no longer covers plasmashellrc" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'cp -a "$SHELLRC" "$SHELLRC_BACKUP"' \
    ':'

# Unquoting the heredoc is invisible: the payload still applies, a backticked
# word in a comment just runs as a command and lands in stderr.
sub "panel payload heredoc left unquoted" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    "cat << 'JS'" \
    'cat << JS'

# sed's delimiter colliding with PIN_JOINED's "||" aborts the substitution, so
# the pinned-app list stays literal and the bar gets no launchers.
sub "panel sed delimiter collides with the URL separator" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    's@URLS=\"\$urls\"@URLS=\"$PIN_JOINED\"@g' \
    's|URLS=\"\$urls\"|URLS=\"$PIN_JOINED\"|g'

# The length bounds are read at layout time, so setting them before the applets
# exist lets the content-driven relayout win: the tray measured 633px.
sub "panel tray length bounds moved back above the widgets" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    '    tray.addWidget("org.kde.plasma.systemtray");

    var clockB' \
    '    tray.minimumLength = 340;        // moved up, on purpose
    tray.maximumLength = 340;        // moved up, on purpose

    tray.addWidget("org.kde.plasma.systemtray");

    var clockB'

# The layout is one bar on purpose: two bars meant the tray/clock lived in the
# opposite corner from the apps. Both defaults are decisions, so both are
# asserted in unit/panel — otherwise a "harmless" TRAY_PANEL flip puts the two
# bars back with the suite still green.
sub "panel default flipped back to two bars" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'TRAY_PANEL=0' \
    'TRAY_PANEL=1'

sub "panel extras re-enabled by default" bash tests/unit/test-panel.sh -- \
    scripts/47-plasmaPanel.sh \
    'PANEL_EXTRAS=0' \
    'PANEL_EXTRAS=1'

# --- Otto -------------------------------------------------------------------
# The layouts/widgets strip is the whole reason the recoloured theme is safe to
# apply: with them in place, applying it replaces the panel.
sub "Otto Global Theme keeps Otto's layouts" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    'run_as_user rm -rf "$dst/contents/layouts" "$dst/contents/widgets"' \
    ':'

sub "Otto recolours the window background to the text colour" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    "Background)         printf 'C_BG' ;;" \
    "Background)         printf 'C_TEXT' ;;"

# The palette registry is one file now, so "deleting a palette" means deleting
# its function — the whole-file case is covered by check 5's registration
# mismatch, which is exactly what this control used to guard.
sub "Otto palette deleted" bash tests/consistency.sh -- \
    themes/palettes.sh 'palette_otto() {' 'palette_otto_disabled() {'


# Discovery must skip this toolkit's own output. The LNF loop and the Kvantum
# loop are separate passes, so each gets its own control: removing one skip
# leaves the other intact, and a suite that only exercised one would stay green.
sub "Otto LNF discovery stops skipping generated themes" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    '            otto_is_generated "$d" && continue
            otto_is_otto' \
    '            otto_is_otto'

sub "Otto Kvantum discovery stops skipping generated copies" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    '            otto_is_generated "$d" && continue
            case "$(basename "$d")" in' \
    '            case "$(basename "$d")" in'

# The contrast curve and the rotation both produce a valid PNG of a plausible
# size, so no file-existence check can see them. The injected text goes on a
# code line inside the existing command, which is what the comment-stripped
# guards actually read.
sub "Otto contents/colors reverted to a symlink" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    'run_as_user cp -f "$colors_file" "$dst/contents/colors"' \
    'run_as_user ln -sf "$colors_file" "$dst/contents/colors"'

sub "Otto wallpaper regains ImageMagick's polynomial contrast curve" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    'gradient:#${C_BG}-#${C_MANTLE}" \' \
    'gradient:#${C_BG}-#${C_MANTLE}" -function polynomial "6,-5,1" \'

sub "Otto wallpaper rotated to portrait again" bash tests/unit/test-otto.sh -- \
    scripts/lib/otto.sh \
    'gradient:#${C_BG}-#${C_MANTLE}" \' \
    'gradient:#${C_BG}-#${C_MANTLE}" -rotate 90 \'

sub "theme.sh stops sourcing the Otto library" bash tests/consistency.sh -- \
    scripts/lib/theme.sh '. "$(dirname "${BASH_SOURCE[0]}")/otto.sh"' ':'

# NOTE: there is deliberately no control for scripts/verifySetup.sh. It is a
# runtime audit that prints PASS/WARN/FAIL against the live machine, not a gated
# tier — release-preflight runs it with `|| true` precisely because its output
# legitimately differs on any given box. A control here would have to assert on
# a human-readable label rather than on a behaviour, which is the kind of test
# that stays green while the thing it names stops working. (An earlier draft of
# this file had exactly that: it grepped for the string "Baloo folder
# exclusions", which still prints fine after the check underneath it is
# replaced with the wrong key.)
#
echo
echo "── negative controls: $CAUGHT/$TOTAL caught ──"
if [ -n "$MISSED" ]; then
    echo "not caught:$MISSED"
    exit 1
fi
echo "every injected regression was detected"
exit 0