#!/usr/bin/env bash
# tests/unit/test-moe.sh — tier 2: scripts/lib/moe.sh unit tests.
#
# No network in this tier. The archives are pinned and SHA256-verified at apply
# time, so what needs testing here is everything downstream of the fetch:
# whether a tampered archive is rejected, and above all whether the SANITISER
# produces a Global Theme that does not name a component this machine does not
# have.
#
# The properties under test, in order of damage:
#   - an upstream key that names an absent component (Colloid icons, WhiteSur
#     cursors, the Aurorae Moe SVG, the Moe color scheme, Moe-DarkSouls) must
#     NOT reach contents/defaults. Applying a Global Theme WRITES those keys, so
#     each one that survives silently resets that part of the desktop to the
#     previous theme — the theme claims Moe while wearing Breeze;
#   - contents/layouts must never be installed: it replaces the panel;
#   - the engine's own ColorScheme/AccentColor must SURVIVE sanitising. Rebuilding
#     defaults from upstream's safe keys alone produces a theme that applies
#     cleanly and paints nothing;
#   - a wrong SHA256 must be refused, and the bad bytes deleted so the next run
#     does not re-fail against its own cache;
#   - no network must be a warning, not an error: the palette still applies.
#
# The upstream archive contents used here are the real ones (metadata.json,
# defaults, a layout) with the artwork and preview images omitted — they are
# several megabytes of JPEG that no assertion here looks at.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

SANDBOX="$(make_tmp devmkde-moe)"
trap 'cleanup_dirs "$SANDBOX"' EXIT

# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/theme.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/moe.sh"

export THEME_HOME_DIR="$SANDBOX/home"
export XDG_CACHE_HOME="$SANDBOX/cache"
export XDG_STATE_HOME="$SANDBOX/state"
mkdir -p "$THEME_HOME_DIR" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"

FAKEBIN="$SANDBOX/bin"
mkdir -p "$FAKEBIN"
for tool in plasma-apply-lookandfeel plasma-apply-colorscheme plasma-apply-wallpaperimage qdbus6 qdbus; do
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/$tool"
    chmod +x "$FAKEBIN/$tool"
done

# A fake curl so the fetch path is testable offline and DETERMINISTICALLY: it
# copies whatever file CURL_FAKE_SRC points at, which is how a "correct pin
# passes" and a "wrong pin is rejected" can both be tested without a network.
# Without this, moe_fetch's happy path is only reachable with internet access and
# the bad-SHA case passes for the wrong reason (the download fails, so it looks
# like the pin rejected the bytes).
printf '%s\n' \
    '#!/bin/sh' \
    'out=""' \
    'while [ $# -gt 0 ]; do' \
    '    case "$1" in -o) out="$2"; shift 2 ;; *) shift ;; esac' \
    'done' \
    '[ -n "${CURL_FAKE_SRC:-}" ] && [ -f "$CURL_FAKE_SRC" ] || exit 6' \
    'cp "$CURL_FAKE_SRC" "$out"' > "$FAKEBIN/curl"
chmod +x "$FAKEBIN/curl"
PATH="$FAKEBIN:$PATH"
export PATH

# ---------------------------------------------------------------------------
# A synthetic Moe package, shaped exactly like the real Moe.tar.gz
# ---------------------------------------------------------------------------
FIXTURE="$SANDBOX/fixture/Moe"
mkdir -p "$FIXTURE/contents/layouts" "$FIXTURE/contents/previews"
cat > "$FIXTURE/metadata.json" <<'JSON'
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [{ "Name": "jomada" }],
        "Name": "Moe",
        "Id": "Moe",
        "Version": "2.6"
    }
}
JSON
# Verbatim upstream contents/defaults. Every one of the six component names in
# it is absent from the archive, which is the whole reason this file is
# sanitised.
cat > "$FIXTURE/contents/defaults" <<'DEFAULTS'
[kcminputrc][Mouse]
cursorTheme=WhiteSur-cursors

[kdeglobals][General]
ColorScheme=Moe

[kdeglobals][KDE]
widgetStyle=kvantum

[kdeglobals][Icons]
Theme=Colloid

[kwinrc][DesktopSwitcher]
LayoutName=org.kde.breeze.desktop

[kwinrc][WindowSwitcher]
LayoutName=org.kde.breeze.desktop

[kwinrc][org.kde.kdecoration2]
library=org.kde.kwin.aurorae
theme=__aurorae__svg__Moe

[plasmarc][Theme]
name=Moe

[Wallpaper]
Image=Moe-DarkSouls
DEFAULTS
printf '// upstream layout that would replace the panel\n' > "$FIXTURE/contents/layouts/org.kde.plasma.desktop-layout.js"
: > "$FIXTURE/contents/previews/preview.png"

tar -czf "$SANDBOX/fixture/Moe.tar.gz" -C "$SANDBOX/fixture" Moe
GOOD_SHA="$(sha256sum "$SANDBOX/fixture/Moe.tar.gz" | cut -d' ' -f1)"

# tar for the colors cross-check
mkdir -p "$SANDBOX/colors-src/MoeDark"
cat > "$SANDBOX/colors-src/MoeDark/MoeDark.colors" <<'COLORS'
[Colors:Window]
BackgroundNormal=38,41,46

[Colors:View]
BackgroundNormal=38,41,46
ForegroundNormal=252,252,252

[Colors:Selection]
BackgroundNormal=255,99,118
COLORS
tar -czf "$SANDBOX/colors.tar.gz" -C "$SANDBOX/colors-src" MoeDark

# ---------------------------------------------------------------------------
# 1. moe_fetch: pins, verification, and poisoned bytes
# ---------------------------------------------------------------------------
export CURL_FAKE_SRC="$SANDBOX/fixture/Moe.tar.gz"
if moe_fetch "Moe.tar.gz" "$GOOD_SHA"; then
    t_ok
    t_assert_eq "moe_fetch sets MOE_FETCHED to the archive" "$SANDBOX/cache/devuan-kde-setup/moe/Moe.tar.gz" "$MOE_FETCHED"
else
    t_fail "moe_fetch rejected an archive whose SHA256 is correct"
fi

# Wrong pin, with a real download behind it: the bytes arrive and the pin is
# what rejects them. The .part file must be gone afterwards, or the next run
# re-verifies its own rejected cache entry and reports a permanent failure.
if moe_fetch "Bad.tar.gz" "0000000000000000000000000000000000000000000000000000000000000000"; then
    t_fail "moe_fetch accepted an archive that fails its SHA256"
else
    t_ok
    t_assert "rejected download leaves no .part behind" \
        test ! -f "$SANDBOX/cache/devuan-kde-setup/moe/Bad.tar.gz.part"
    t_assert "rejected archive is not promoted into the cache" \
        test ! -f "$SANDBOX/cache/devuan-kde-setup/moe/Bad.tar.gz"
fi

# A cached file whose bytes no longer match the pin must be replaced, not
# returned. This is the cache-poisoning case: a truncated download from a
# previous run would otherwise be served forever.
printf 'truncated\n' > "$SANDBOX/cache/devuan-kde-setup/moe/Moe.tar.gz"
if moe_fetch "Moe.tar.gz" "$GOOD_SHA" && [ "$MOE_FETCHED" = "$SANDBOX/cache/devuan-kde-setup/moe/Moe.tar.gz" ]; then
    t_ok
else
    t_fail "moe_fetch did not replace a cached archive that fails its pin"
fi

# An empty pin is a programming error, not a verification pass.
if moe_fetch "Moe.tar.gz" ""; then
    t_fail "moe_fetch accepted an empty SHA256 as a pin"
else
    t_ok
fi

# MOE_FETCHED must be cleared at the START of every call. Without that, a failed
# fetch leaves the PREVIOUS call's path in the global and the caller extracts
# the previous archive — the theme silently stops updating when the mirror's
# content changes, with no error anywhere. This is the test that makes the
# clearing load-bearing rather than decorative.
moe_fetch "Moe.tar.gz" "$GOOD_SHA" >/dev/null 2>&1
stale="$MOE_FETCHED"
if [ -z "$stale" ]; then
    t_fail "precondition failed: MOE_FETCHED was not set by the successful fetch"
else
    CURL_FAKE_SRC=/nonexistent moe_fetch "Gone.tar.gz" "$GOOD_SHA" >/dev/null 2>&1
    if [ -z "$MOE_FETCHED" ]; then t_ok
    else t_fail "a failed moe_fetch left a stale MOE_FETCHED=$MOE_FETCHED"; fi
fi

# The cache path must follow XDG_CACHE_HOME, and only at call time: this tier
# exports it AFTER lib/common.sh was sourced, so a source-time constant would
# have written to the developer's real ~/.cache.
if [ "$(moe_cache_dir)" = "$XDG_CACHE_HOME/devuan-kde-setup/moe" ]; then t_ok
else t_fail "moe_cache_dir does not follow XDG_CACHE_HOME: $(moe_cache_dir)"; fi

# ---------------------------------------------------------------------------
# 2. moe_extract: refuses an unexpected layout instead of guessing
# ---------------------------------------------------------------------------
if moe_extract "$SANDBOX/fixture/Moe.tar.gz" "Moe" "$SANDBOX/extracted"; then
    t_ok
    t_assert_eq "moe_extract sets MOE_EXTRACTED" "$SANDBOX/extracted/Moe" "$MOE_EXTRACTED"
    t_assert_grep "extracted defaults are present" "cursorTheme=WhiteSur-cursors" \
        "$MOE_EXTRACTED/contents/defaults"
else
    t_fail "moe_extract failed on a well-formed archive"
fi
# Second call must take the cached path and still succeed.
if moe_extract "$SANDBOX/fixture/Moe.tar.gz" "Moe" "$SANDBOX/extracted"; then
    t_ok
else
    t_fail "moe_extract failed on an already-extracted archive"
fi
# Wrong expected top dir: refuse rather than copy whatever is at the root.
if moe_extract "$SANDBOX/fixture/Moe.tar.gz" "NotMoe" "$SANDBOX/extracted2"; then
    t_fail "moe_extract accepted an archive without the expected top directory"
else
    t_ok
fi

# ---------------------------------------------------------------------------
# 3. The sanitiser — the reason this file exists
# ---------------------------------------------------------------------------
load_palette moe-dark >/dev/null 2>&1
t_assert_eq "moe-dark palette loads" "moe-dark" "${PALETTE_ID:-}"

ENGINE_DEFAULTS="$SANDBOX/engine-defaults"
cat > "$ENGINE_DEFAULTS" <<'DEFAULTS'
[kdeglobals][General]
ColorScheme=MoeDark
AccentColor=#ff6376

[plasmarc][Theme]
name=default

[kwinrc][org.kde.kdecoration2]
library=org.kde.breeze
theme=Breeze
BorderSize=None
BorderSizeAuto=false
DEFAULTS

OUT="$SANDBOX/sanitized-defaults"
if moe_sanitize_defaults "$ENGINE_DEFAULTS" "$FIXTURE/contents/defaults" "$OUT"; then
    t_ok
else
    t_fail "moe_sanitize_defaults refused a valid pair of defaults files"
fi

# The six absent components must not survive.
t_assert_not_grep "sanitised defaults name no absent cursor"    "WhiteSur-cursors"   "$OUT"
t_assert_not_grep "sanitised defaults name no absent icons"     "Colloid"             "$OUT"
t_assert_not_grep "sanitised defaults name no absent Aurorae"   "__aurorae__svg__Moe" "$OUT"
t_assert_not_grep "sanitised defaults name no absent scheme"    "ColorScheme=Moe$"   "$OUT"
t_assert_not_grep "sanitised defaults name no absent wallpaper" "Moe-DarkSouls"       "$OUT"
t_assert_not_grep "sanitised defaults do not force kvantum"     "widgetStyle=kvantum" "$OUT"

# The two safe upstream sections must survive.
t_assert_grep "sanitised defaults keep DesktopSwitcher"  "^\[kwinrc\]\[DesktopSwitcher\]$" "$OUT"
t_assert_grep "sanitised defaults keep WindowSwitcher"   "^\[kwinrc\]\[WindowSwitcher\]$"  "$OUT"

# And the engine's own keys must survive — this is the regression that makes a
# sanitised theme apply cleanly and paint nothing.
t_assert_grep "sanitised defaults keep the palette's ColorScheme" "^ColorScheme=MoeDark$" "$OUT"
t_assert_grep "sanitised defaults keep the palette's accent"      "^AccentColor=#ff6376$" "$OUT"
t_assert_grep "sanitised defaults keep the Breeze decoration"     "^library=org.kde.breeze$" "$OUT"

# A base file with no ColorScheme must be refused, not installed as a theme
# that cannot set its own colors.
printf '[plasmarc][Theme]\nname=default\n' > "$SANDBOX/no-scheme-defaults"
if moe_sanitize_defaults "$SANDBOX/no-scheme-defaults" "$FIXTURE/contents/defaults" "$SANDBOX/out2"; then
    t_fail "moe_sanitize_defaults accepted a base file with no ColorScheme"
else
    t_ok
fi

# ---------------------------------------------------------------------------
# 4. The palette really is upstream's Moe Dark
# ---------------------------------------------------------------------------
t_assert_eq "moe-dark accent" "ff6376" "${C_ACCENT:-}"
t_assert_eq "moe-dark background" "26292e" "${C_BG:-}"
t_assert_eq "moe-dark text" "fcfcfc" "${C_TEXT:-}"
t_assert_eq "moe-dark ANSI 2 (cyan)" "2bb1af" "${C_2:-}"

# Render the scheme through the real template and cross-check the rendered file
# against a stand-in upstream MoeDark.colors.
mkdir -p "$THEME_HOME_DIR/.local/share/color-schemes"
render_template "$THEME_TEMPLATES_DIR/plasma.colors.tpl" \
    "$THEME_HOME_DIR/.local/share/color-schemes/MoeDark.colors" >/dev/null 2>&1
t_assert_grep "rendered scheme has the Moe window background" \
    "^BackgroundNormal=38,41,46$" "$THEME_HOME_DIR/.local/share/color-schemes/MoeDark.colors"

# Point the cross-check at the local tarball instead of the network.
moe_fetch() {
    MOE_FETCHED="$SANDBOX/colors.tar.gz"
    return 0
}
if moe_verify_palette "$THEME_HOME_DIR/.local/share/color-schemes/MoeDark.colors"; then
    t_ok
else
    t_fail "moe_verify_palette rejected a scheme that matches upstream"
fi

# A palette that is NOT upstream Moe must be reported, not waved through. The
# mutation is applied to a COPY of the registry, scoped to palette_moe_dark's
# body, so the repo's palettes.sh is never edited by a test.
mkdir -p "$SANDBOX/wrongpal/themes"
sed '/^palette_moe_dark() {/,/^}$/ s/^C_ACCENT=ff6376$/C_ACCENT=00ff00/' \
    "$PALETTES_FILE" > "$SANDBOX/wrongpal/themes/palettes.sh"
PALETTES_FILE="$SANDBOX/wrongpal/themes/palettes.sh"
load_palette moe-dark >/dev/null 2>&1
render_template "$THEME_TEMPLATES_DIR/plasma.colors.tpl" \
    "$SANDBOX/wrong-palette.colors" >/dev/null 2>&1
if moe_verify_palette "$SANDBOX/wrong-palette.colors"; then
    t_fail "moe_verify_palette accepted a palette that differs from upstream"
else
    t_ok
fi
# Restore, and prove the restore worked rather than assuming it.
PALETTES_FILE="$REPO_ROOT/themes/palettes.sh"
load_palette moe-dark >/dev/null 2>&1
t_assert_eq "PALETTES_FILE restored" "$REPO_ROOT/themes/palettes.sh" "$PALETTES_FILE"

# ---------------------------------------------------------------------------
# 5. Identity
# ---------------------------------------------------------------------------
META="$SANDBOX/metadata.json"
moe_write_metadata "$META" "MoeDarkTheme"
t_assert_grep "metadata declares the Plasma 6 KPackage structure" \
    '"KPackageStructure": "Plasma/LookAndFeel"' "$META"
t_assert_grep "metadata registers the sanitised id" '"Id": "MoeDarkTheme"' "$META"
t_assert_grep "metadata keeps upstream's author" '"Name": "jomada"' "$META"
t_assert_grep "metadata keeps upstream's version" '"Version": "2.6"' "$META"
# The upstream package's own id must NOT be claimed, or a real Discover install
# of Moe and this sanitised copy become indistinguishable.
t_assert_not_grep "metadata does not claim the upstream id" '"Id": "Moe"' "$META"
# X-KPackage-Dependencies lists seven packages that are not installed here.
t_assert_not_grep "metadata drops unfulfilled package dependencies" \
    "X-KPackage-Dependencies" "$META"
python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$META" 2>/dev/null \
    && t_ok || t_fail "generated metadata.json is not valid JSON"

# ---------------------------------------------------------------------------
# 6. End to end, with the fetch stubbed to the local archive
# ---------------------------------------------------------------------------
# moe_apply_theme ADDS to the package the engine wrote, so run the engine
# first. Without this the LAF has no contents/defaults to extend and Moe has
# nothing to sanitise — which is the correct failure, not a broken test.
apply_global_theme "$THEME_HOME_DIR" >/dev/null 2>&1
t_assert_grep "engine wrote the MoeDarkTheme LAF before Moe ran" \
    "^ColorScheme=MoeDark$" \
    "$THEME_HOME_DIR/.local/share/plasma/look-and-feel/MoeDarkTheme/contents/defaults"

moe_fetch() {
    case "$1" in
        Moe.tar.gz) MOE_FETCHED="$SANDBOX/fixture/Moe.tar.gz"; return 0 ;;
        *) return 1 ;;
    esac
}
if moe_apply_theme "$THEME_HOME_DIR"; then
    t_ok
else
    t_fail "moe_apply_theme failed with a fetchable archive"
fi
LAF="$THEME_HOME_DIR/.local/share/plasma/look-and-feel/MoeDarkTheme"
t_assert_grep "installed theme declares Moe's manifest" '"Name": "jomada"' "$LAF/metadata.json"
t_assert_not_grep "installed theme's defaults name no absent icons"  "Colloid"           "$LAF/contents/defaults"
t_assert_not_grep "installed theme's defaults name no absent cursor" "WhiteSur-cursors"  "$LAF/contents/defaults"
t_assert_not_grep "installed theme's defaults name no absent scheme" "ColorScheme=Moe$"  "$LAF/contents/defaults"
t_assert "installed theme ships no layouts directory" test ! -e "$LAF/contents/layouts"
t_assert "installed theme ships no widgets directory" test ! -e "$LAF/contents/widgets"
t_assert_grep "installed theme keeps the palette's ColorScheme" "^ColorScheme=MoeDark$" \
    "$LAF/contents/defaults"
t_assert "installed theme carries the provenance marker" \
    test -f "$LAF/.devmkde-generated"

# Kvantum is opt-in and must stay that way without the env var.
moe_apply_kvantum "$THEME_HOME_DIR" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' \
    | t_assert_grep "Kvantum stays opt-in" "opt-in" -
t_assert "no Kvantum dir created without opt-in" \
    test ! -d "$THEME_HOME_DIR/.config/Kvantum/MoeDark"

# A failing fetch must be a warning, and must not leave a half-written theme.
moe_fetch() { return 1; }
if moe_apply_theme "$THEME_HOME_DIR"; then
    t_ok
else
    t_fail "moe_apply_theme returned non-zero when the download failed"
fi

t_summary "unit/moe"