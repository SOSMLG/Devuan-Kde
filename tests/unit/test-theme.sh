#!/usr/bin/env bash
# tests/unit/test-theme.sh — tier 2: scripts/lib/theme.sh unit tests.
#
# Sandbox rules: no root, no apt, no X, no network, and critically — writes go
# to a temp THEME_HOME_DIR, never the real $HOME. theme.sh's apply_palette()
# resolves the target home via `getent passwd` (correct in production, since it
# must hit the real user even when invoked under sudo) which means a naive
# test run WILL write into the developer's actual ~/.local/share. That already
# happened once during development and had to be cleaned up by hand, so
# THEME_HOME_DIR is set on every case here.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

SANDBOX="$(make_tmp devmkde-theme)"
trap 'cleanup_dirs "$SANDBOX"' EXIT

# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/common.sh"
# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/theme.sh"

# Redirect apply_palette's output home AND the state dir.
export THEME_HOME_DIR="$SANDBOX/home"
export XDG_STATE_HOME="$SANDBOX/state"
mkdir -p "$THEME_HOME_DIR" "$XDG_STATE_HOME"

# Stub the tools that talk to the RUNNING desktop.
#
# THEME_HOME_DIR redirects everything the engine writes itself, but
# plasma-apply-colorscheme and plasma-apply-lookandfeel act on the live Plasma
# session over D-Bus — they do not care where THEME_HOME_DIR points. Calling
# them from a test therefore reconfigured the developer's actual desktop, and
# because they re-sync kcminputrc from KConfig's in-memory copy (which has no
# cursorTheme key), running the suite silently wiped the live cursor theme.
#
# Fakes go first on PATH so command_exists still sees them and the real
# binaries are never reached.
FAKEBIN="$SANDBOX/bin"
mkdir -p "$FAKEBIN"
for tool in plasma-apply-colorscheme plasma-apply-lookandfeel qdbus6 qdbus; do
    printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/$tool"
    chmod +x "$FAKEBIN/$tool"
done
PATH="$FAKEBIN:$PATH"
export PATH

# Guard the guard: if the PATH prepend above is ever removed, the suite starts
# reconfiguring the real desktop again and every assertion still passes. Assert
# the shadowing directly so that regression fails loudly here instead.
for tool in plasma-apply-colorscheme plasma-apply-lookandfeel; do
    case "$(command -v "$tool" 2>/dev/null)" in
        "$FAKEBIN"/*) t_ok ;;
        *) t_fail "$tool is not shadowed by the sandbox; tests would touch the live desktop" ;;
    esac
done

# ── hex2rgb ────────────────────────────────────────────────────────────────
t_assert_eq "hex2rgb #121113"       "18,17,19" "$(hex2rgb 121113)"
t_assert_eq "hex2rgb strips #"      "18,17,19" "$(hex2rgb '#121113')"
t_assert_eq "hex2rgb white"         "255,255,255" "$(hex2rgb ffffff)"
t_assert_eq "hex2rgb black"         "0,0,0"      "$(hex2rgb 000000)"
if hex2rgb 12345 >/dev/null 2>&1; then
    t_fail "hex2rgb should reject 5-digit hex"
else
    t_ok
fi

# ── every palette in themes/palettes.sh is complete and renderable ───────────
PALETTE_COUNT=0
while IFS= read -r name; do
    [ -n "$name" ] || continue
    PALETTE_COUNT=$((PALETTE_COUNT + 1))

    if load_palette "$name" >/dev/null 2>&1; then
        t_ok
    else
        t_fail "palette '$name' failed load_palette (missing/blank vars?)"
    fi

    # RG_ twins must be derived for every C_ entry, else a template renders a
    # blank where a decimal RGB triple is expected.
    for v in "${_PALETTE_VARS[@]}"; do
        case "$v" in
            C_*)
                rg="RG_${v}"
                if [ -z "${!rg-}" ]; then
                    t_fail "palette '$name': $rg not derived from $v"
                else
                    t_ok
                fi
                ;;
        esac
    done

    # Render and assert no placeholder survives. An unexpanded @VAR@ is the
    # classic silent failure: the file is written, it just looks wrong.
    out="$SANDBOX/render-$name"
    if load_palette "$name" >/dev/null 2>&1 && \
       render_template "$THEME_TEMPLATES_DIR/plasma.colors.tpl" "$out"; then
        t_assert_not_grep "palette '$name': plasma.colors.tpl fully expanded" '@[A-Z_]*@' "$out"
        # Every group the template declares must be present, and Plasma 6
        # needs [Colors:View] (missing it was a real bug).
        t_assert_grep "palette '$name': has [Colors:View]" '^\[Colors:View\]$' "$out"
        t_assert_grep "palette '$name': has [Colors:Window]" '^\[Colors:Window\]$' "$out"
        t_assert_grep "palette '$name': has [General]" '^\[General\]$' "$out"
    else
        t_fail "palette '$name': plasma.colors.tpl failed to render"
    fi

    out2="$SANDBOX/konsole-$name"
    if render_template "$THEME_TEMPLATES_DIR/konsole.colorscheme.tpl" "$out2"; then
        t_assert_not_grep "palette '$name': konsole.tpl fully expanded" '@[A-Z_]*@' "$out2"
    else
        t_fail "palette '$name': konsole.colorscheme.tpl failed to render"
    fi
done < <(palettes_registered)

if [ "$PALETTE_COUNT" -ge 10 ]; then t_ok; else t_fail "only $PALETTE_COUNT palettes found (expected >=10)"; fi

# ── the Darkmatter palettes exist with the exact colors we promised ────────
for p in darkmatter darkmatter-orange; do
    if load_palette "$p" >/dev/null 2>&1; then
        t_ok
        t_assert_eq "$p: background" "121113" "$C_BG"
        t_assert_eq "$p: mantle"   "171618" "$C_MANTLE"
        t_assert_eq "$p: surface"  "1c1b1d" "$C_SURFACE0"
        t_assert_eq "$p: border0"  "2b2b2b" "$C_OVERLAY0"
        t_assert_eq "$p: border1"  "333333" "$C_OVERLAY1"
        t_assert_eq "$p: text"     "ffffff" "$C_TEXT"
        t_assert_eq "$p: subtext"  "c1c1c1" "$C_SUBTEXT0"
    else
        t_fail "palette '$p' missing or invalid"
    fi
done

# Red is the default accent; orange is the upstream-preserved alternative.
load_palette darkmatter >/dev/null 2>&1
t_assert_eq "darkmatter: red accent" "e75353" "$C_ACCENT"
load_palette darkmatter-orange >/dev/null 2>&1
t_assert_eq "darkmatter-orange: upstream accent" "e78a53" "$C_ACCENT"

# Accent foreground must be dark on a light-on-dark palette, or KDE draws
# unreadable labels on selected items.
load_palette darkmatter >/dev/null 2>&1
t_assert_eq "darkmatter: accent fg is dark" "121113" "$C_ACCENT_FG"

# ── end-to-end: apply_palette writes the full artifact set ─────────────────
if apply_palette darkmatter >/dev/null 2>&1; then
    t_ok
    H="$THEME_HOME_DIR"
    for f in \
        "$H/.local/share/konsole/Darkmatter.colorscheme" \
        "$H/.local/share/konsole/Darkmatter.profile" \
        "$H/.local/share/color-schemes/Darkmatter.colors" \
        "$H/.local/share/plasma/look-and-feel/DarkmatterTheme/metadata.json"
    do
        if [ -e "$f" ]; then t_ok; else t_fail "apply_palette didn't produce $f"; fi
    done

    LNF="$H/.local/share/plasma/look-and-feel/DarkmatterTheme"

    # The cursor must actually be in kcminputrc when apply_palette returns, not
    # just written and then deleted again by the Plasma tools that run later in
    # the same function. Both halves of that bug are invisible from the log: it
    # reported success while kcminputrc held no cursorTheme key at all.
    if [ -f "$H/.config/kcminputrc" ]; then
        if grep -q '^cursorTheme=' "$H/.config/kcminputrc"; then t_ok
        else t_fail "apply_palette returned without a cursorTheme in kcminputrc"; fi
    fi

    # Plasma 6 resolves every kpackage definition under contents/, so defaults
    # and colors must live there. A flat layout installs fine and is then
    # silently ignored — the theme applies zero settings.
    for f in "$LNF/contents/defaults" "$LNF/contents/colors"; do
        if [ -f "$f" ]; then t_ok; else t_fail "Global Theme is missing $f"; fi
    done

    # contents/defaults references the color scheme BY NAME, leaving the single
    # .colors in ~/.local/share/color-schemes/ as the source of truth.
    t_assert_grep "contents/defaults sets ColorScheme" \
        '^ColorScheme=Darkmatter$' "$LNF/contents/defaults"
    t_assert_grep "contents/defaults sets AccentColor" \
        '^AccentColor=#' "$LNF/contents/defaults"

    # contents/colors must be a REAL file. Plasma 6 kpackages do not support
    # symlinks -- the Plasma 5 idiom of symlinking a shared color scheme in
    # from a relative path cannot work here. readlink -e would follow a link and
    # report success, so test the link-ness explicitly rather than reachability.
    if [ -L "$LNF/contents/colors" ]; then
        t_fail "Global Theme contents/colors is a symlink (unsupported in Plasma 6)"
    elif [ -s "$LNF/contents/colors" ]; then
        t_ok
        # It must be a copy of the scheme, not a stale or empty stub.
        if cmp -s "$LNF/contents/colors" \
            "$H/.local/share/color-schemes/Darkmatter.colors"; then
            t_ok
        else
            t_fail "contents/colors does not match the generated color scheme"
        fi
    else
        t_fail "Global Theme contents/colors is empty or missing"
    fi

    # No layouts dir: shipping an empty one claims a DesktopLayout the theme
    # doesn't provide, and Plasma applies an empty panel instead of the user's.
    if [ -d "$LNF/contents/layouts" ]; then
        t_fail "Global Theme ships contents/layouts without providing a layout"
    else
        t_ok
    fi

    # metadata.json must be VALID JSON and carry a KPlugin.Id — a malformed
    # manifest makes the theme install fine and then never appear in the menu.
    META="$LNF/metadata.json"
    if command_available python3 >/dev/null 2>&1; then
        if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['KPlugin']['Id']" "$META" 2>/dev/null; then
            t_ok
        else
            t_fail "metadata.json is not valid JSON with a KPlugin.Id"
        fi
        # The load-bearing key. Without the top-level KPackageStructure,
        # Plasma 6 refuses the package outright: plasma-apply-lookandfeel logs
        # 'does not match requested format "Plasma/LookAndFeel"' and omits the
        # theme from --list and System Settings, while the accent still lands in
        # kdeglobals. Nothing errors, the desktop just never changes.
        if python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d['KPackageStructure']=='Plasma/LookAndFeel'" "$META" 2>/dev/null; then
            t_ok
        else
            t_fail "metadata.json is missing KPackageStructure=Plasma/LookAndFeel"
        fi
        # And it must NOT be the Plasma 5 metadata.desktop spelling, which
        # Plasma 6 silently ignores.
        t_assert_grep "metadata.json declares ServiceTypes Plasma/LookAndFeel" \
            '"Plasma/LookAndFeel"' "$META"
        if grep -q '"Plasma/Theme"' "$META" 2>/dev/null; then
            t_fail "metadata.json still declares the Plasma 5 ServiceTypes Plasma/Theme"
        fi
    fi
else
    t_fail "apply_palette darkmatter failed outright"
fi

# hex2rgb must REJECT non-hex, not silently coerce it. bash's printf evaluates
# an invalid hex literal as 0, so `C_BG=nothex` used to render as "0,0,14" — a
# plausible near-black that hides the typo until someone reads the .colors file.
if hex2rgb nothex >/dev/null 2>&1; then
    t_fail "hex2rgb accepted 'nothex' as a color"
else
    t_ok
fi
if hex2rgb 12345g >/dev/null 2>&1; then
    t_fail "hex2rgb accepted '12345g'"
else
    t_ok
fi

# ── apply_palette_by_short round-trips ─────────────────────────────────────
if apply_palette_by_short Darkmatter >/dev/null 2>&1; then
    t_ok
else
    t_fail "apply_palette_by_short Darkmatter failed"
fi
if apply_palette_by_short NoSuchPalette >/dev/null 2>&1; then
    t_fail "apply_palette_by_short accepted a nonexistent palette"
else
    t_ok
fi

# ── a palette with a blank required var must be rejected, not rendered ─────
# Palettes live in themes/palettes.sh as functions, so a broken palette is
# built by copying the whole file to a sandbox and mutating that function there.
# The copy is what makes this safe: load_palette() reads $PALETTES_FILE, and
# PALETTES_FILE is repointed at the sandbox, so the repo's real registry is
# never the thing under test.
BAD="$SANDBOX"
cp "$PALETTES_FILE" "$BAD/palettes.sh"
PALETTES_FILE="$BAD/palettes.sh"
export PALETTES_FILE

# One line short of the schema: no C_15.
sed -i '/^C_15=/d' "$PALETTES_FILE"
if load_palette darkmatter >/dev/null 2>&1; then
    t_fail "load_palette accepted a palette missing C_15"
else
    t_ok
fi

# A malformed hex must be rejected too.
cp "$REPO_ROOT/themes/palettes.sh" "$BAD/palettes.sh"
sed -i 's/^C_BG=121113/C_BG=nothex/' "$PALETTES_FILE"
if load_palette darkmatter >/dev/null 2>&1; then
    t_fail "load_palette accepted C_BG=nothex"
else
    t_ok
fi

# An id with no function, and a function whose PALETTE_ID disagrees with the
# name it is registered under — the copy-paste failure mode of a single file
# holding every palette.
cp "$REPO_ROOT/themes/palettes.sh" "$BAD/palettes.sh"
if load_palette nosuchpalette >/dev/null 2>&1; then
    t_fail "load_palette accepted an id with no function"
else
    t_ok
fi
sed -i 's/^PALETTE_ID="darkmatter"$/PALETTE_ID="darkmatter-orange"/' "$PALETTES_FILE"
if load_palette darkmatter >/dev/null 2>&1; then
    t_fail "load_palette accepted a palette whose PALETTE_ID names another palette"
else
    t_ok
fi

# Restore a pristine registry. PALETTES_FILE now points at a sandbox copy that
# has been mutated three times above, and it stays pointed there for the rest of
# the file -- so any later section that calls apply_palette inherits a palette
# function whose PALETTE_ID says "darkmatter-orange" and fails in a way that has
# nothing to do with what it is testing. Point it back at the repo's own
# registry, which nothing in this file mutates.
cp "$REPO_ROOT/themes/palettes.sh" "$BAD/palettes.sh"

# ── reassert_catppuccin_lnf must not cross-apply Catppuccin flavours ──────
# Two bugs lived in this function, and both produced a wrong-but-plausible
# desktop rather than an error:
#
#  1. It matched the palette id as a *family* name (`*mocha*`), so mocha-blue
#     and frappe were handed the installed Mocha RED Global Theme — a red
#     desktop under a blue palette.
#  2. Its opt-out was `[ -n "${DEVMKDE_PREFER_CATPPUCCIN:-1}" ]`. "0" is
#     non-empty, so the documented way to turn this off did nothing.
#
# Stub the three externals the function reaches for so the real Plasma and the
# real ~/.config are never touched.
_reassert_applied=""
command_exists() { return 0; }
run_as_user() {
    [ "$1" = "plasma-apply-lookandfeel" ] || return 0
    case "${2:-}" in
        --list)
            # One bare id per line, exactly as the real tool prints them.
            printf 'Catppuccin-Mocha-Red\norg.kde.breezedark.desktop\n'
            return 0
            ;;
        --apply)
            _reassert_applied="${_reassert_applied} ${3:-}"
            return 0
            ;;
    esac
    return 0
}
log_ok() { :; }
log_info() { :; }

# The palette that genuinely came from that theme still gets it.
_reassert_applied=""; PALETTE_ID="mocha-red"
reassert_catppuccin_lnf >/dev/null 2>&1
case " $_reassert_applied " in
    *" Catppuccin-Mocha-Red "*) t_ok ;;
    *) t_fail "mocha-red did not reassert Catppuccin-Mocha-Red (got:$_reassert_applied)" ;;
esac

# A sibling flavour must be left on its own theme.
for _pid in mocha-blue frappe macchiato; do
    _reassert_applied=""; PALETTE_ID="$_pid"
    reassert_catppuccin_lnf >/dev/null 2>&1
    if [ -z "$_reassert_applied" ]; then
        t_ok
    else
        t_fail "$_pid was given the Mocha Red theme (got:$_reassert_applied)"
    fi
done

# The documented opt-out has to actually opt out.
_reassert_applied=""; PALETTE_ID="mocha-red"; DEVMKDE_PREFER_CATPPUCCIN=0
reassert_catppuccin_lnf >/dev/null 2>&1
if [ -z "$_reassert_applied" ]; then
    t_ok
else
    t_fail "DEVMKDE_PREFER_CATPPUCCIN=0 did not disable reassertion"
fi
unset DEVMKDE_PREFER_CATPPUCCIN

# ── a Global Theme application must not eat kdeglobals ColorScheme ──────────
#
# Reproduces a live failure: a full `46-applyThemes.sh moe-dark` logged
# "Plasma color scheme ... persisted", applied the generated Global Theme,
# applied the Moe package, and afterwards kdeglobals [General] had AccentColor
# and ColorSchemeHash but no ColorScheme. Nothing warned — kwriteconfig6 exits 0
# either way. The next login comes up on Plasma's default scheme and every
# generated colour is gone.
#
# Re-source common.sh first: earlier sections in this file deliberately stub
# run_as_user, and ini_set_key commits through it. Left stubbed, the helper
# cannot write anything and this test would report a failure that exists only in
# the harness.
# common.sh has an include guard, so the re-source needs the guard cleared or it
# is a silent no-op and the stub survives.
unset _DEVUAN_KDE_COMMON_SH_LOADED
. "$REPO_ROOT/scripts/lib/common.sh"

SANDBOX="$(mktemp -d)"
mkdir -p "$SANDBOX/.config"
printf '[General]\nColorScheme=%s\nAccentColor=#111111\n' "OldScheme" > "$SANDBOX/.config/kdeglobals"
printf '[Desktop Entry]\nDefaultProfile=Old.profile\n' > "$SANDBOX/.config/konsolerc"

PALETTE_SHORT="MoeDark"
C_ACCENT="ff6376"
if persist_palette_keys "$SANDBOX"; then
    t_ok
else
    t_fail "persist_palette_keys reported failure on a writable kdeglobals"
fi

if grep -q '^ColorScheme=MoeDark$' "$SANDBOX/.config/kdeglobals"; then t_ok
else t_fail "persist_palette_keys did not restore [General] ColorScheme after the key was dropped"; fi

if grep -q '^AccentColor=#ff6376$' "$SANDBOX/.config/kdeglobals"; then t_ok
else t_fail "persist_palette_keys did not write AccentColor"; fi

if grep -q '^DefaultProfile=MoeDark.profile$' "$SANDBOX/.config/konsolerc"; then t_ok
else t_fail "persist_palette_keys did not write konsolerc DefaultProfile"; fi

# Idempotence: calling it repeatedly must not append a second copy of any key,
# or kdeglobals grows a duplicate line on every theme swap.
persist_palette_keys "$SANDBOX" >/dev/null 2>&1
persist_palette_keys "$SANDBOX" >/dev/null 2>&1
dups=$(grep -c '^ColorScheme=' "$SANDBOX/.config/kdeglobals")
if [ "$dups" -eq 1 ]; then t_ok
else t_fail "persist_palette_keys is not idempotent: $dups ColorScheme lines after 3 calls"; fi

# A kdeglobals the process cannot write must be REPORTED, not silently ignored.
: > "$SANDBOX/.config/kdeglobals"
chmod 000 "$SANDBOX/.config/kdeglobals"
if persist_palette_keys "$SANDBOX" >/dev/null 2>&1; then
    t_fail "persist_palette_keys claimed success on an unwritable kdeglobals"
else
    t_ok
fi
chmod 644 "$SANDBOX/.config/kdeglobals"
rm -rf "$SANDBOX"

# ── apply_palette's LAST write to kdeglobals is the one that survives ───────
#
# The unit above proves persist_palette_keys works. This proves it is called in
# the right PLACE.
#
# The mechanism is the fake plasma-apply-lookandfeel already on PATH from the top
# of this file: it is rewritten here to delete [General] ColorScheme from the
# sandbox kdeglobals on every --apply, which is what the real tool's effect on
# that key looks like in a live session. Nothing else is stubbed -- file writes
# go through the real run_as_user, which ini_set_key depends on. (An earlier
# version of this section wrapped run_as_user instead; bash resolves function
# names at call time, so the wrapper called itself and the suite died with a
# segfault rather than a test failure.)
#
# The sequence mirrors the live one: the last look-and-feel applied is the
# palette-specific package in step 6, after every other write, so nothing but the
# step-6b re-assert can put the key back.
#
# Delete that re-assert from theme.sh and this fails. Move it back up beside
# step 3, where it "worked" for years, and this fails too.
LNF_EATS_KEY_HOME="$(mktemp -d)"
mkdir -p "$LNF_EATS_KEY_HOME/.config"
printf '[General]\nColorScheme=PreExisting\n' > "$LNF_EATS_KEY_HOME/.config/kdeglobals"
printf '[Desktop Entry]\nDefaultProfile=Pre.profile\n' > "$LNF_EATS_KEY_HOME/.config/konsolerc"

cat > "$FAKEBIN/plasma-apply-lookandfeel" <<EOF
#!/bin/sh
# Stands in for the real tool's effect on [General] ColorScheme: a look-and-feel
# application rewrites kdeglobals from the package's contents/defaults, and the
# key the palette wrote beforehand does not survive it.
if [ "\${1:-}" = "--apply" ]; then
    sed -i '/^ColorScheme=/d' "$LNF_EATS_KEY_HOME/.config/kdeglobals" 2>/dev/null
fi
exit 0
EOF
chmod +x "$FAKEBIN/plasma-apply-lookandfeel"
THEME_HOME_DIR="$LNF_EATS_KEY_HOME"

if apply_palette darkmatter >/dev/null 2>&1; then
    t_ok
else
    t_fail "apply_palette failed against a sandbox kdeglobals"
fi
if grep -q '^ColorScheme=Darkmatter$' "$LNF_EATS_KEY_HOME/.config/kdeglobals"; then t_ok
else
    t_fail "a look-and-feel application erased [General] ColorScheme and nothing put it back"
fi
if grep -q '^DefaultProfile=Darkmatter.profile$' "$LNF_EATS_KEY_HOME/.config/konsolerc"; then t_ok
else t_fail "konsolerc DefaultProfile lost to a look-and-feel application"; fi
# And exactly one of them, not a second copy appended by the re-assert.
if [ "$(grep -c '^ColorScheme=' "$LNF_EATS_KEY_HOME/.config/kdeglobals")" -eq 1 ]; then t_ok
else t_fail "the re-assert appended a duplicate ColorScheme line"; fi

# The fake is left in place for any later section, so put it back.
printf '#!/bin/sh\nexit 0\n' > "$FAKEBIN/plasma-apply-lookandfeel"
chmod +x "$FAKEBIN/plasma-apply-lookandfeel"
# common.sh has an include guard, so the re-source needs the guard cleared or it
# is a silent no-op and the stub survives.
unset _DEVUAN_KDE_COMMON_SH_LOADED
. "$REPO_ROOT/scripts/lib/common.sh"
rm -rf "$LNF_EATS_KEY_HOME"

t_summary "unit/theme"
