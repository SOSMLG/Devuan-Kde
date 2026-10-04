#!/usr/bin/env bash
# tests/unit/test-otto.sh — tier 2: scripts/lib/otto.sh unit tests.
#
# Every fixture here is SYNTHETIC and lives in the sandbox: a fake Otto
# Global Theme, a fake Kvantum theme, a fake color scheme and a fake Konsole
# scheme, all shaped like the real store.kde.org packages but containing no
# artwork and none of Otto's code. That is deliberate — the real packages can
# only be installed through the KDE GUI (store.kde.org is behind an Anubis
# proof-of-work gate), so the discovery and recolouring code has to be
# testable without them.
#
# The important properties under test, in order of how much damage getting
# them wrong would do:
#   - a recoloured Global Theme must NOT contain contents/layouts or
#     contents/widgets, because applying it would otherwise replace the panel
#     built by 47-plasmaPanel.sh;
#   - the decoration block replacement must not eat the section header that
#     follows it;
#   - pristine Otto files must never be written to;
#   - unknown keys must survive untouched (guessing a value is worse than
#     leaving one);
#   - with nothing installed at all, applying must be a clean no-op.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

SANDBOX="$(make_tmp devmkde-otto)"
trap 'cleanup_dirs "$SANDBOX"' EXIT

# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/theme.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/otto.sh"

export THEME_HOME_DIR="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
mkdir -p "$THEME_HOME_DIR" "$XDG_STATE_HOME"

# Fake the live-desktop tools: otto.sh calls plasma-apply-lookandfeel and
# apply_wallpaper_image talks to plasmashell over D-Bus. Neither may touch the
# developer's real session from a test.
FAKEBIN="$SANDBOX/bin"
mkdir -p "$FAKEBIN"
for tool in plasma-apply-lookandfeel plasma-apply-colorscheme plasma-apply-wallpaperimage qdbus6 qdbus; do
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/$tool"
    chmod +x "$FAKEBIN/$tool"
done
PATH="$FAKEBIN:$PATH"
export PATH

# --- 0. The palette itself ---------------------------------------------------
load_palette otto >/dev/null 2>&1
t_assert "otto palette loads with every required var set" \
    bash -c "cd '$REPO_ROOT' && source scripts/lib/common.sh && source scripts/lib/theme.sh && load_palette otto"

t_assert_eq "otto palette short name"  "OttoRed" "$PALETTE_SHORT"
t_assert_eq "otto palette id"          "otto"    "$PALETTE_ID"
t_assert_eq "otto accent is red"       "e5484d"  "$C_ACCENT"
t_assert_eq "otto accent RGB"          "229,72,77" "$RG_C_ACCENT"

# Every C_* must be a real 6-digit hex: a typo here renders as a near-black
# instead of failing (see hex2rgb's own note in theme.sh).
_bad=0
for v in "${_PALETTE_VARS[@]}"; do
    case "$v" in C_*) [[ "${!v-}" =~ ^[0-9a-fA-F]{6}$ ]] || { _bad=1; echo "  bad hex: $v=${!v-}"; } ;; esac
done
t_assert_eq "every otto C_* is a valid 6-digit hex" "0" "$_bad"

# The ANSI ramp must be 16 distinct values: a duplicated entry means two ANSI
# colours render identically, which is exactly the "muted palette" failure
# mode this palette exists to avoid.
_dupes="$(for i in $(seq 0 15); do v="C_$i"; printf '%s\n' "${!v-}"; done | sort | uniq -d | tr '\n' ' ')"
t_assert_eq "otto ANSI 0-15 are all distinct" "" "$_dupes"

# ---------------------------------------------------------------------------
# 1. otto_recolor_colors
# ---------------------------------------------------------------------------
FIX="$SANDBOX/fixtures"
mkdir -p "$FIX"
cat > "$FIX/Otto.colors" <<'COLORS'
[ColorEffects:Disabled]
Color=96,96,96

[Colors:View]
Background=17,14,14
Foreground=255,255,255
Color1=229,72,77
Color2=111,156,134
Color7=196,196,202
SomeKeyWeDoNotKnow=1,2,3

[Colors:Window]
BackgroundNormal=20,18,18
DecorationFocus=200,50,50
DecorationFocusText=255,255,255

[Colors:Selection]
SelectionBackground=229,72,77
SelectionForeground=255,255,255
COLORS

OUT="$SANDBOX/out/Otto-recolored.colors"
if otto_recolor_colors "$FIX/Otto.colors" "$OUT"; then
    t_ok
else
    t_fail "otto_recolor_colors returned 1 on a real color scheme"
fi

t_assert_grep "colors: Background maps to palette bg"       "^Background=$(hex2rgb "$C_BG"),?$"       "$OUT"
t_assert_grep "colors: Foreground maps to palette text"     "^Foreground=$(hex2rgb "$C_TEXT"),?$"    "$OUT"
t_assert_grep "colors: Color1 maps to ANSI red"             "^Color1=$(hex2rgb "$C_1"),?$"            "$OUT"
t_assert_grep "colors: Color7 maps to ANSI 7"               "^Color7=$(hex2rgb "$C_7"),?$"            "$OUT"
t_assert_grep "colors: DecorationFocus maps to accent"      "^DecorationFocus=$(hex2rgb "$C_ACCENT"),?$" "$OUT"
t_assert_grep "colors: DecorationFocusText maps to accent fg" "^DecorationFocusText=$(hex2rgb "$C_ACCENT_FG"),?$" "$OUT"
t_assert_grep "colors: unknown key left untouched"          '^SomeKeyWeDoNotKnow=1,2,3$'           "$OUT"
t_assert_grep "colors: unknown nested key left untouched"   '^Color=96,96,96$'                     "$OUT"
t_assert_grep "colors: group headers preserved"             '^\[Colors:Window\]$'                   "$OUT"
t_assert_not_grep "colors: no leftover temp file referenced" 'otto\.tmp'                            "$OUT"

# A file with no mappable keys must NOT be written out as a "recoloured" copy.
echo "not a colors file" > "$FIX/plain.txt"
t_assert_eq "otto_recolor_colors returns 1 for a non-scheme file" "1" \
    "$(otto_recolor_colors "$FIX/plain.txt" "$SANDBOX/out/should-not-exist.colors"; echo $?)"
t_assert "otto_recolor_colors wrote no output for a non-scheme" \
    test ! -e "$SANDBOX/out/should-not-exist.colors"

# A destination in a directory that does not exist yet must still work: the
# helper creates it before opening its temp file.
t_assert "otto_recolor_colors creates a missing destination directory" \
    otto_recolor_colors "$FIX/Otto.colors" "$SANDBOX/brand/new/dir/Otto.colors"
t_assert "  ... and actually wrote the file" \
    test -f "$SANDBOX/brand/new/dir/Otto.colors"

# ---------------------------------------------------------------------------
# 2. Konsole scheme recolouring
# ---------------------------------------------------------------------------
KON_IN="$SANDBOX/home/.local/share/konsole"
mkdir -p "$KON_IN"
cat > "$KON_IN/Otto.colorscheme" <<'KONSOLE'
[Background]
Color=20,18,18

[BackgroundFaint]
Color=30,28,28

[Color0]
Color=20,20,23

[Color0Faint]
Color=53,53,59

[Color1]
Color=229,72,77

[Color1Light]
Color=242,100,105

[Color7]
Color=196,196,202

[Color7Faint]
Color=53,53,59

[Foreground]
Color=196,196,202

[ForegroundFaint]
Color=53,53,59

[General]
Color=234,234,234
Name=Otto
Opacity=1,1

[GeneralIntense]
Color=139,139,146
KONSOLE

KON_OUT="$SANDBOX/out/OttoRed-Otto.colorscheme"
if otto_recolor_konsole "$THEME_HOME_DIR" "$KON_OUT"; then
    t_ok
else
    t_fail "otto_recolor_konsole returned 1 with a scheme present"
fi

t_assert_grep "konsole: [Background] -> ANSI 0"    "^$(hex2rgb "$C_0")$"    "$KON_OUT"
t_assert_grep "konsole: [Color1] -> ANSI 1"        "^$(hex2rgb "$C_1")$"    "$KON_OUT"
t_assert_grep "konsole: [Color7Faint] -> bright black" "^$(hex2rgb "$C_8")$" "$KON_OUT"
t_assert_grep "konsole: [Color1Light] -> bright red"   "^$(hex2rgb "$C_9")$" "$KON_OUT"
t_assert_grep "konsole: [Foreground] -> ANSI 7"     "^$(hex2rgb "$C_7")$"    "$KON_OUT"
t_assert_grep "konsole: [General] -> text"          "^$(hex2rgb "$C_TEXT")$" "$KON_OUT"
t_assert_grep "konsole: [General] renamed"          '^Name=OttoRed-Otto$'    "$KON_OUT"
t_assert_grep "konsole: [General] keeps Opacity"    '^Opacity=1,1$'          "$KON_OUT"
t_assert_grep "konsole: [GeneralIntense] -> subtext1" "^$(hex2rgb "$C_SUBTEXT1")$" "$KON_OUT"
t_assert_eq "konsole: section count preserved" \
    "$(grep -c '^\[' "$KON_IN/Otto.colorscheme")" "$(grep -c '^\[' "$KON_OUT")"
t_assert_grep "konsole: source scheme untouched" '^Name=Otto$' "$KON_IN/Otto.colorscheme"

# A rerun must not mistake its own previous output for the source.
cp "$KON_OUT" "$KON_IN/OttoRed-Otto.colorscheme"
t_assert_eq "konsole: skips its own previous output" "1" \
    "$(mv "$KON_IN/Otto.colorscheme" "$SANDBOX/otto.colorscheme.bak" && otto_recolor_konsole "$THEME_HOME_DIR" "$SANDBOX/out/second.colorscheme" >/dev/null 2>&1; echo $?)"
mv "$SANDBOX/otto.colorscheme.bak" "$KON_IN/Otto.colorscheme"

# ---------------------------------------------------------------------------
# 3. Discovery
# ---------------------------------------------------------------------------
LNF_ROOT="$THEME_HOME_DIR/.local/share/plasma/look-and-feel"
OTTO_LNF="$LNF_ROOT/org.kde.otto.desktop"
mkdir -p "$OTTO_LNF/contents/layouts" "$OTTO_LNF/contents/widgets" "$OTTO_LNF/contents/wallpapers"
cat > "$OTTO_LNF/metadata.json" <<'META'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [
            {
                "Email": "otto@example.invalid",
                "Name": "Otto Author",
                "Roles": [ "Author" ]
            }
        ],
        "Category": "Global Themes (Plasma 6)",
        "Description": "Otto, a red/black Plasma theme",
        "Icon": "preferences-desktop-theme",
        "Id": "org.kde.otto.desktop",
        "License": "CC-BY-4.0",
        "Name": "Otto",
        "ServiceTypes": [ "Plasma/LookAndFeel" ],
        "Version": "1.0"
    }
}
META
cat > "$OTTO_LNF/contents/defaults" <<'DEFAULTS'
[kdeglobals][General]
ColorScheme=Otto

[plasmarc][Theme]
name=otto

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.otto
theme=otto
BorderSize=2

[org.kde.plasma.desktop-applet]
SomethingAfterTheDecorationBlock=keepme
DEFAULTS
printf 'panel layout that must never reach our copy\n' > "$OTTO_LNF/contents/layouts/panel.js"
printf 'widget default that must never reach our copy\n' > "$OTTO_LNF/contents/widgets/clock.js"
printf 'otto artwork placeholder\n' > "$OTTO_LNF/contents/wallpapers/otto.png"

# A decoy: a different theme that merely has "otto" somewhere in its path.
DECOY="$LNF_ROOT/OttoTheme-NIGHTLY"
mkdir -p "$DECOY"
cat > "$DECOY/metadata.json" <<'META'
{ "KPackageStructure": "Plasma/LookAndFeel",
  "KPlugin": { "Id": "com.example.nightly", "Name": "Nightly",
               "Description": "A dark theme unrelated to Otto" } }
META

t_assert_eq "otto_find_lnf locates the installed Otto" "$OTTO_LNF" "$(otto_find_lnf "$THEME_HOME_DIR")"

DECOR="$THEME_HOME_DIR/.local/share/kwin/decorations/org.kde.otto.decoration"
mkdir -p "$DECOR"
cat > "$DECOR/metadata.json" <<'META'
{ "KPackageStructure": "org.kde.kwin.decoration",
  "KPlugin": { "Id": "Otto", "Name": "Otto Decoration",
               "Description": "Otto window decoration" } }
META
t_assert_eq "otto_find_decor locates the decoration" "$DECOR" "$(otto_find_decor "$THEME_HOME_DIR")"

KV="$THEME_HOME_DIR/.config/Kvantum/Otto-Dark"
mkdir -p "$KV/KvAnt/general"
cat > "$KV/KvAnt/general/general colours.conf" <<'KVCONF'
[General]
general.color=20,18,18
general.base=14,14,17
general.text=234,234,234
window.color=14,14,17
window.hilight.color=229,72,77
unknown.key=1,2,3
KVCONF
printf 'ok' > "$KV/KvAnt/test.svg"
printf 'cache' > "$KV/KvAnt/general/otto.svgcache"

t_assert_eq "otto_find_kvantum locates the Kvantum theme" "$KV" "$(otto_find_kvantum "$THEME_HOME_DIR")"

# ---------------------------------------------------------------------------
# 4. Global Theme copy: layouts stripped, defaults patched, metadata renamed
# ---------------------------------------------------------------------------
# Render the palette's own .colors first: otto_make_lnf symlinks to it.
apply_palette otto >/dev/null 2>&1
t_assert "palette apply wrote the generated color scheme" \
    test -f "$THEME_HOME_DIR/.local/share/color-schemes/OttoRed.colors"

# otto_apply_theme runs the same pass; the LNF it produces must be safe to apply.
if otto_apply_theme "$THEME_HOME_DIR" >/dev/null 2>&1; then
    t_ok
else
    t_fail "otto_apply_theme failed with all components present"
fi

OUR_LNF="$LNF_ROOT/OttoRed"
t_assert "otto_make_lnf created our own LNF id" test -d "$OUR_LNF"
t_assert "our LNF has no contents/layouts (would replace the panel)"  test ! -d "$OUR_LNF/contents/layouts"
t_assert "our LNF has no contents/widgets"                            test ! -d "$OUR_LNF/contents/widgets"
t_assert "our LNF kept the wallpaper assets" test -f "$OUR_LNF/contents/wallpapers/otto.png"

t_assert_grep "our LNF metadata id is the palette-derived one" '"Id": "OttoRed"'        "$OUR_LNF/metadata.json"
t_assert_grep "our LNF metadata name says which palette it is for" 'Otto \(Otto Red\)'   "$OUR_LNF/metadata.json"
t_assert_grep "our LNF keeps Otto's author verbatim"              '"Name": "Otto Author"' "$OUR_LNF/metadata.json"
t_assert_grep "our LNF keeps Otto's licence verbatim"              '"License": "CC-BY-4.0"' "$OUR_LNF/metadata.json"
t_assert_not_grep "our LNF does NOT claim Otto's original id" \
    '"Id": "org\.kde\.otto\.desktop"' "$OUR_LNF/metadata.json"

# A real copy, not a symlink — the rule apply_global_theme follows and states
# outright ("contents/colors  A REAL copy of the .colors file. NOT a symlink"),
# because Plasma 6 kpackages do not support a symlink here. Otto shipped with a
# symlink, which is what every upstream theme does and therefore what looked
# correct; a symlink here is a documented no-no one directory away.
t_assert "contents/colors is a real file, not a symlink" \
    bash -c '[ -f "$1/contents/colors" ] && [ ! -L "$1/contents/colors" ]' _ "$OUR_LNF"
t_assert "contents/colors is byte-identical to the palette's scheme" \
    cmp -s "$OUR_LNF/contents/colors" \
          "$THEME_HOME_DIR/.local/share/color-schemes/OttoRed.colors"

# The decoration block: Otto's own is replaced by ours (pointing at Otto's
# decoration, since it is installed), and the section that FOLLOWS it survives.
t_assert_grep "decoration block rewritten to the installed Otto decoration" \
    '^theme=Otto$' "$OUR_LNF/contents/defaults"
t_assert_grep "decoration library follows the package structure" \
    '^library=org\.kde\.kwin\.decoration$' "$OUR_LNF/contents/defaults"
t_assert_eq "decoration block appears exactly once" "1" \
    "$(grep -c '^\[kwinrc\]\[org\.kde\.kdecoration2\]$' "$OUR_LNF/contents/defaults")"
t_assert_grep "the section AFTER the decoration block survived (sed range would eat it)" \
    '^\[org\.kde\.plasma\.desktop-applet\]$' "$OUR_LNF/contents/defaults"
t_assert_grep "keys after the decoration block survived" \
    '^SomethingAfterTheDecorationBlock=keepme$' "$OUR_LNF/contents/defaults"
t_assert_grep "Otto's own ColorScheme line kept in defaults" \
    '^ColorScheme=Otto$' "$OUR_LNF/contents/defaults"

# The pristine installation must be byte-for-byte untouched.
t_assert_grep "pristine Otto defaults untouched (decoration still Otto's own)" \
    '^library=org\.kde\.kwin\.otto$' "$OTTO_LNF/contents/defaults"
t_assert_grep "pristine Otto layouts still there" 'panel layout' "$OTTO_LNF/contents/layouts/panel.js"

# A rerun must find the ORIGINAL, not our own copy (which is also an "otto"
# package by name) — otherwise the second apply would recolour its own output
# and drift.
t_assert_eq "otto_find_lnf still finds the pristine package, not our copy" \
    "$OTTO_LNF" "$(otto_find_lnf "$THEME_HOME_DIR")"

# ---------------------------------------------------------------------------
# 5. Kvantum
# ---------------------------------------------------------------------------
OUR_KV="$THEME_HOME_DIR/.config/Kvantum/Otto-Dark-OttoRed"
t_assert "kvantum copy created under a palette-suffixed id" test -d "$OUR_KV"
t_assert_grep "kvantum general.color recoloured" "^general.color=$(hex2rgb "$C_MANTLE")$" "$OUR_KV/KvAnt/general/general colours.conf"
t_assert_grep "kvantum window.hilight.color recoloured to the accent" \
    "^window.hilight.color=$(hex2rgb "$C_ACCENT")$" "$OUR_KV/KvAnt/general/general colours.conf"
t_assert_grep "kvantum unknown key preserved" '^unknown\.key=1,2,3$' "$OUR_KV/KvAnt/general/general colours.conf"
t_assert "kvantum SVG copied untouched" test -f "$OUR_KV/KvAnt/test.svg"
t_assert "stale svgcache removed so Kvantum rebuilds it" test ! -e "$OUR_KV/KvAnt/general/otto.svgcache"
t_assert_grep "pristine Kvantum conf untouched" '^general.color=20,18,18$' "$KV/KvAnt/general/general colours.conf"

# ---------------------------------------------------------------------------
# 5b. The generated wallpaper must be built the way script 14 builds it.
#
# A first version of otto.sh added "-function polynomial 6,-5,1" (a contrast
# curve that maps 0->1 and 1->2) and "-rotate 90". On a dark palette the curve
# lifts the image into the highlights -- 74% mean brightness instead of 5.5% --
# and the rotate turns a 1920x1080 desktop wallpaper portrait. Both produce a
# perfectly valid PNG, so nothing failed and the defect was invisible to every
# test that only checked the file exists.
# ---------------------------------------------------------------------------
# Only whole-line comments are dropped here. The usual sed filter
# ("s/[[:space:]]*#.*$//") is wrong for this file: the guarded line contains
# "gradient:#${C_BG}", so it truncates at the '#' and the operator on that same
# line becomes invisible -- green with the bug present, which a negative control
# duly proved.
if grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/lib/otto.sh" \
     | grep -qF -- '-function polynomial'; then
    t_fail "otto.sh applies ImageMagick's polynomial contrast curve to a dark gradient"
else
    t_ok
fi
if grep -v '^[[:space:]]*#' "$REPO_ROOT/scripts/lib/otto.sh" \
     | grep -qF -- '-rotate 90'; then
    t_fail "otto.sh rotates the generated wallpaper to portrait"
else
    t_ok
fi
t_assert_grep "gradient is built from the palette's own two darkest tones" \
    'gradient:#\${C_BG}-#\${C_MANTLE}' "$REPO_ROOT/scripts/lib/otto.sh"

# ---------------------------------------------------------------------------
# 6. The no-Otto case: applying must be a clean, reported no-op
# ---------------------------------------------------------------------------
BARE="$SANDBOX/bare-home"
mkdir -p "$BARE"
if otto_apply_theme "$BARE" >"$SANDBOX/bare.log" 2>&1; then
    t_ok
else
    t_fail "otto_apply_theme must succeed when nothing is installed"
fi
t_assert_grep "no-Otto run explains what is missing" "Otto's Global Theme not installed" "$SANDBOX/bare.log"
t_assert_grep "no-Otto run states the palette stands alone" "is complete on its own" "$SANDBOX/bare.log"
t_assert "no LNF invented when Otto is absent" test ! -d "$BARE/.local/share/plasma/look-and-feel/OttoRed"

# ---------------------------------------------------------------------------
# 7. Rerun safety: discovery must never mistake our own output for an install
#
# The regression this guards against was invisible in every direction that
# mattered. otto_is_otto matches any declared field whose VALUE mentions Otto,
# and the wrapper theme generated for this palette declares Name "Otto Red" and
# an "Otto-inspired" Description. A second run therefore found its OWN OUTPUT,
# logged "Otto Global Theme applied" against a machine with no Otto installed,
# and copied the wrapper over itself. The Kvantum case was unbounded: the
# output id is derived from the source name plus the palette, so each run
# rediscovered the previous run's directory and derived another name from it —
# Otto-Dark-OttoRed, Otto-Dark-OttoRed-OttoRed, and no warning at any point.
# ---------------------------------------------------------------------------
t_assert "generated LNF carries the provenance marker" \
    test -f "$LNF_ROOT/OttoRed/$OTTO_GENERATED_MARKER"
t_assert "generated wrapper theme carries the provenance marker" \
    test -f "$LNF_ROOT/OttoRedTheme/$OTTO_GENERATED_MARKER"
t_assert "recoloured Kvantum copy carries the provenance marker" \
    test -f "$OUR_KV/$OTTO_GENERATED_MARKER"
t_assert "otto_is_generated rejects the LNF id we write under" otto_is_generated "$LNF_ROOT/OttoRed"
t_assert "otto_is_generated rejects the palette's wrapper theme" otto_is_generated "$LNF_ROOT/OttoRedTheme"
t_assert "otto_is_generated rejects the suffixed Kvantum copy" otto_is_generated "$OUR_KV"
t_assert "otto_is_generated accepts a real upstream Otto directory" \
    bash -c "! otto_is_generated '$OTTO_LNF'"
t_assert "otto_is_generated accepts a similarly named unrelated theme" \
    bash -c "! otto_is_generated '$DECOY'"

# With generated siblings present in the same directories, discovery must still
# return the REAL upstream Otto. Without the skip this returns OttoRedTheme,
# because it sorts before org.kde.otto.desktop.
t_assert_eq "otto_find_lnf still finds upstream Otto, not the generated wrapper" \
    "$OTTO_LNF" "$(otto_find_lnf "$THEME_HOME_DIR")"

# Home with ONLY generated output: discovery must report nothing found.
ONLY_GEN="$SANDBOX/generated-only"
mkdir -p "$ONLY_GEN/.local/share/plasma/look-and-feel" "$ONLY_GEN/.config/Kvantum"
cp -a "$LNF_ROOT/OttoRedTheme" "$ONLY_GEN/.local/share/plasma/look-and-feel/"
cp -a "$OUR_KV" "$ONLY_GEN/.config/Kvantum/"
t_assert "no LNF is 'found' in a home holding only our own output" \
    test -z "$(otto_find_lnf "$ONLY_GEN")"
t_assert "no Kvantum theme is 'found' in a home holding only our own output" \
    test -z "$(otto_find_kvantum "$ONLY_GEN")"

# Pre-marker output: same shapes, no marker file. The name fallback has to cover
# these too, or upgrading leaves exactly the self-consuming directories that
# caused the bug.
LEGACY="$SANDBOX/legacy-output"
mkdir -p "$LEGACY/.local/share/plasma/look-and-feel/OttoRedTheme/contents" \
         "$LEGACY/.config/Kvantum/Otto-Dark-OttoRed/KvAnt"
cp "$LNF_ROOT/OttoRedTheme/metadata.json" "$LEGACY/.local/share/plasma/look-and-feel/OttoRedTheme/"
printf 'legacy\n' > "$LEGACY/.config/Kvantum/Otto-Dark-OttoRed/KvAnt/general.conf"
t_assert "unmarked legacy wrapper is still excluded by name" \
    test -z "$(otto_find_lnf "$LEGACY")"
t_assert "unmarked legacy Kvantum copy is still excluded by name" \
    test -z "$(otto_find_kvantum "$LEGACY")"

# The compounding symptom itself: applying twice must not grow the id.
TWICE="$SANDBOX/twice"
mkdir -p "$TWICE"
cp -a "$KV" "$TWICE/.config-Kvantum-src" 2>/dev/null || true
mkdir -p "$TWICE/.config/Kvantum" "$TWICE/.local/share/plasma/look-and-feel"
cp -a "$KV" "$TWICE/.config/Kvantum/Otto-Dark"
cp -a "$OTTO_LNF" "$TWICE/.local/share/plasma/look-and-feel/org.kde.otto.desktop"
otto_apply_kvantum "$TWICE" >/dev/null 2>&1
otto_apply_kvantum "$TWICE" >/dev/null 2>&1
t_assert_eq "applying the Kvantum copy twice yields exactly one suffixed id" \
    "Otto-Dark-OttoRed" "$(find "$TWICE/.config/Kvantum" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | grep -- '-OttoRed' | head -1)"

t_summary "unit/otto"
