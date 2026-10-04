#!/usr/bin/env bash
# =======================================================
# theme.sh — the palette theme engine (sourced by scripts)
# -------------------------------------------------------
# Turns the plain hex palettes in themes/palettes.sh into a
# coherent KDE Plasma color story in one call:
#
#   ~/.local/share/konsole/<Short>.colorscheme   Konsole terminal ANSI palette
#   ~/.local/share/konsole/<Short>.profile       a Konsole profile pointing at it
#   ~/.local/share/color-schemes/<Short>.colors  KDE Plasma color scheme
#   konsolerc (DefaultProfile) + kdeglobals (ColorScheme + AccentColor)
#   lookandfeeltool metadata.json + a Global Theme (Plasma 6 look-and-feel
#     package) so System Settings > Appearance offers the palette as a
#     one-click theme instead of a color scheme you have to pick by hand
#
# Two palettes additionally source a companion library:
#
#   `otto`     lib/otto.sh finds an installed Otto Plasma theme and recolours
#              copies of it to the palette's values (see the top of that file
#              for why Otto itself is not bundled here).
#   `moe-dark` lib/moe.sh fetches the pinned upstream Moe v2.6 Global Theme and
#              sanitises it: its contents/defaults names six components it does
#              not ship, and its contents/layouts would replace the panel.
#              Moe ships pinned tarballs on a mirror, so it is fetched rather
#              than discovered — hence fetch+verify, not recolour.
#
# Both are sourced (not required) so a palette that never touches them carries
# none of it, and a syntax error in one cannot stop an unrelated palette from
# applying.
#
# Every palette_<id>() in themes/palettes.sh defines the same set of
# variables (see palette_darkmatter or any sibling); the templates in
# themes/_base/tpl/ reference them as @VAR@ (hex) or @RG_VAR@ (decimal
# "R,G,B") and are expanded with sed — no runtime per-color hardcoding,
# so adding a palette is adding one id in PALETTE_IDS plus one function,
# nothing else.
#
# Reloads what can be reloaded live (plasma-apply-colorscheme + KWin
# reconfigure); the rest settles at next login. Requires lib/common.sh to
# have been sourced first (kwrite_user, run_as_user, log_*, ACTUAL_USER).
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVUAN_KDE_THEME_SH_LOADED:-}" ] && return 0
_DEVUAN_KDE_THEME_SH_LOADED=1

# Repository themes dir (lib/ is one level under scripts/, themes sits at repo root).
THEMES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../themes" && pwd)"
THEME_TEMPLATES_DIR="$THEMES_DIR/_base/tpl"
# Every palette lives in this one file, as palette_<id>() functions.
PALETTES_FILE="$THEMES_DIR/palettes.sh"

# Companion libraries for the two palettes that have real upstream themes.
# shellcheck source=otto.sh
if [ -f "$(dirname "${BASH_SOURCE[0]}")/otto.sh" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/otto.sh"
fi
# shellcheck source=moe.sh
if [ -f "$(dirname "${BASH_SOURCE[0]}")/moe.sh" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/moe.sh"
fi

# Version stamped into every generated metadata.json.
THEME_VERSION="1.0"

# Where the active palette is recorded.
#
# theme_state_dir — a FUNCTION, not a variable computed at source time. A
# top-level STATE_DIR binds ${XDG_STATE_HOME:-$HOME} the moment this file is
# sourced, which is before a test can export XDG_STATE_HOME — so a sandboxed
# run writes "current-theme" into the developer's REAL ~/.local/state and
# silently renames their desktop. It did exactly that while this was being
# written: a sandboxed apply_palette otto overwrote a live Darkmatter marker
# with "otto", and the desktop still looked Darkmatter because only the marker
# had moved. Resolving it at call time makes the redirect work.
theme_state_dir() {
    printf '%s/devuan-kde-setup' "${XDG_STATE_HOME:-$HOME/.local/state}"
}
STATE_DIR=""
CURRENT_THEME_FILE=""

# Every variable a palette may define (and thus every @VAR@ a template may
# reference). RG_* twins are derived from the C_* entries at load time.
_PALETTE_VARS=(PALETTE_ID PALETTE_NAME PALETTE_SHORT PALETTE_DESC
    C_BG C_MANTLE C_CRUST C_SURFACE0 C_SURFACE1 C_OVERLAY0 C_OVERLAY1
    C_TEXT C_SUBTEXT0 C_SUBTEXT1
    C_ACCENT C_ACCENT_FG C_ACCENT_DIM
    C_0 C_1 C_2 C_3 C_4 C_5 C_6 C_7 C_8 C_9 C_10 C_11 C_12 C_13 C_14 C_15)

# Cleared on every load like _PALETTE_VARS, but NOT required to be non-empty:
# an empty value means "this palette does not claim that component". A cursor id
# must stay optional — see resolve_cursor_theme for why an unset one must not be
# papered over with a default.
_PALETTE_OPTIONAL_VARS=(CURSOR_THEME)

# hex2rgb <hex> — 6-hex digit color → decimal "R,G,B". Returns the string
# on stdout; empty and status 1 for bad input.
#
# The explicit ^[0-9a-fA-F]{6}$ check is load-bearing, not paranoia: bash's
# printf evaluates an invalid hex literal as 0 and carries on, so
# `printf '%d' 0xno` yields 0, not an error. Without the guard a typo like
# C_BG=nothex renders as the decimal triple "0,0,14" — a plausible-looking
# near-black instead of a loud failure, which is exactly the sort of thing
# that gets "fixed" by staring at the .colors file.
hex2rgb() {
    local h="${1#\#}"
    [[ "$h" =~ ^[0-9a-fA-F]{6}$ ]] || { echo ""; return 1; }
    printf "%d,%d,%d" "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# palettes_registered - echo the ids in themes/palettes.sh, in picker order.
#
# Sourced rather than parsed: PALETTE_IDS is the single source of truth for
# "which palettes exist". Grepping the file for palette_<id>() would also work
# but would happily accept a function nobody registered, leaving the picker and
# load_palette() disagreeing about the palette list.
palettes_registered() {
    [ -f "$PALETTES_FILE" ] || { log_err "themes/palettes.sh missing at $PALETTES_FILE"; return 1; }
    # shellcheck source=/dev/null
    source "$PALETTES_FILE"
    printf '%s\n' "${PALETTE_IDS[@]}"
}

# palette_fn <id> - the function that defines palette <id>.
#
# Ids contain hyphens ("darkmatter-orange"); bash function names may not, or at
# least not usefully: bash accepts `foo-bar() { ...; }` and even reports it with
# `declare -F`, but `foo-bar` then parses as the command `foo` with the argument
# `-bar`, so the definition can never be invoked. The mapping is therefore done
# here, once, instead of by hand in four places.
palette_fn() { printf 'palette_%s' "${1//-/_}"; }

# palette_field <id> <var>... - print one palette's variables, one per line.
#
# The palette function runs in a subshell so it cannot touch the caller's
# environment. This is the cheap way to read a palette's metadata without
# loading it for real, and it is why list_palettes() stopped shelling out
# twice per palette: both variables now come out of one subshell.
palette_field() {
    local id="$1"; shift
    [ -f "$PALETTES_FILE" ] || return 1
    # shellcheck source=/dev/null
    source "$PALETTES_FILE"
    local fn; fn="$(palette_fn "$id")"
    if ! declare -F "$fn" >/dev/null 2>&1; then
        echo "palette_field: no such palette: $id" >&2
        return 1
    fi
    ( "$fn"; local v; for v in "$@"; do printf '%s\n' "${!v-}"; done )
}

# list_palettes - one line per palette: "id|Short|Name".
list_palettes() {
    local id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        printf '%s|%s\n' "$id" \
            "$(palette_field "$id" PALETTE_SHORT PALETTE_NAME 2>/dev/null | paste -sd'|' -)"
    done < <(palettes_registered)
}

# load_palette <id> - runs palette_<id>() from themes/palettes.sh and checks it;
# aborts when required vars are missing so templates never render blanks.
load_palette() {
    local id="$1"
    [ -f "$PALETTES_FILE" ] || { log_err "themes/palettes.sh missing at $PALETTES_FILE"; return 1; }
    # shellcheck source=/dev/null
    source "$PALETTES_FILE"
    local fn; fn="$(palette_fn "$id")"
    if ! declare -F "$fn" >/dev/null 2>&1; then
        log_err "No such palette: '$id'. Known ids: ${PALETTE_IDS[*]}"
        return 1
    fi
    case " ${PALETTE_IDS[*]} " in
        *" $id "*) ;;
        *) log_err "$fn exists but '$id' is not in PALETTE_IDS - it would never be listed."; return 1 ;;
    esac

    # Clear every palette variable BEFORE sourcing. Sourcing merges into the
    # current environment rather than replacing it, so without this a second
    # load silently inherits the first palette's values for anything the new
    # palette omits — and load_palette's own completeness check then passes on
    # stale data, which is how a palette ships a wrong color nobody notices.
    local v
    for v in "${_PALETTE_VARS[@]}" "${_PALETTE_OPTIONAL_VARS[@]}"; do
        unset "$v"
        case "$v" in
            C_*) unset "RG_${v}" ;;
        esac
    done

    "$fn"

    # The id the function sets must be the id that was asked for. Otherwise a
    # copied block (darkmatter-orange copied from darkmatter, left saying
    # PALETTE_ID=darkmatter) loads "successfully" and every generated file gets
    # labelled with the wrong palette name.
    if [ "${PALETTE_ID:-}" != "$id" ]; then
        log_err "$fn sets PALETTE_ID='${PALETTE_ID:-}' - copy-paste error?"
        return 1
    fi

    local missing=() v
    for v in "${_PALETTE_VARS[@]}"; do
        [ -n "${!v-}" ] || missing+=("$v")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_err "$fn missing required vars: ${missing[*]}"
        return 1
    fi

    # Derive decimal RGB twins (RG_*) so templates can use @RG_C_BG@ etc.
    for v in "${_PALETTE_VARS[@]}"; do
        case "$v" in
            C_*)
                local rgb
                rgb="$(hex2rgb "${!v}")"
                [ -n "$rgb" ] || { log_err "$v='${!v}' is not a valid 6-digit hex color."; return 1; }
                printf -v "RG_${v}" '%s' "$rgb"
                ;;
        esac
    done
    return 0
}

# render_template <tpl-file> <out-file> — expands every @VAR@ placeholder
# for the palette currently loaded in this shell.
render_template() {
    local tpl="$1" out="$2"
    [ -f "$tpl" ] || { log_err "Template not found: $tpl"; return 1; }
    local args=() v rg
    for v in "${_PALETTE_VARS[@]}"; do
        args+=(-e "s|@${v}@|${!v}|g")
        case "$v" in
            C_*)
                rg="RG_${v}"
                args+=(-e "s|@${rg}@|${!rg}|g")
                ;;
        esac
    done
    sed "${args[@]}" "$tpl" > "$out"
}

# apply_palette <name> — apply one palette end-to-end (Konsole scheme +
# profile, Plasma color scheme, kdeglobals accent, defaults + reload).
# persist_palette_keys <home_dir> — put the palette's persistent keys in
# kdeglobals/konsolerc, VERIFIED, and report which ones refused to stick.
#
# WHY NOT kwrite_user: kwriteconfig6 exits 0 and writes nothing for some keys.
# That is documented in lib/common.sh against cursorTheme, and it is exactly
# what happens to [General] ColorScheme once a Global Theme is involved. Live
# session, verified: a full `46-applyThemes.sh moe-dark` run logged
# "Default Konsole profile + Plasma color scheme + accent persisted" and left
# kdeglobals with AccentColor and ColorSchemeHash but NO ColorScheme at all. On
# the next login Plasma picks its own default scheme, the accent and every
# generated colour silently revert, and nothing logged an error — the exit code
# was 0 the whole time.
#
# So these three keys go through ini_set_key (edit + read back) rather than
# through kwriteconfig's word. AccentColor is included because it lives in the
# same group and has the same failure mode: a scheme that applies without it
# just looks like the accent was ignored.
#
# Returns 0 only if every key verified. Prints a warning naming the key that
# did not stick, because a caller that swallows this turns a silent revert into
# a silent revert.
persist_palette_keys() {
    local home_dir="$1" kg kc rc=0
    kg="$home_dir/.config/kdeglobals"
    kc="$home_dir/.config/konsolerc"
    ini_set_key "$kc" "Desktop Entry" "DefaultProfile" "${PALETTE_SHORT}.profile" \
        || { log_warn "konsolerc DefaultProfile did not stick"; rc=1; }
    # NOTE: case matters. Plasma 6 capitalised these; the Plasma 5 spellings
    # (accentColor) are accepted as an unknown key and ignored, which is the
    # single most common "why isn't my theme applying?" bug.
    ini_set_key "$kg" "General" "ColorScheme" "$PALETTE_SHORT" \
        || { log_warn "kdeglobals ColorScheme did not stick — next login reverts to Plasma's default scheme"; rc=1; }
    ini_set_key "$kg" "General" "AccentColor" "#${C_ACCENT}" \
        || { log_warn "kdeglobals AccentColor did not stick"; rc=1; }
    # AccentColorFromWallpaper is deliberately NOT written: Plasma 5 key, gone in
    # Plasma 6. Harmless-looking, permanently ignored.
    return "$rc"
}

apply_palette() {
    local name="$1"
    load_palette "$name" || return 1
    local home_dir

    if [ -n "${THEME_HOME_DIR:-}" ]; then
        home_dir="$THEME_HOME_DIR"
    else
        home_dir="$(getent passwd "$ACTUAL_USER" 2>/dev/null | cut -d: -f6)"
    fi
    [ -n "$home_dir" ] || home_dir="$HOME"

    # ---- 1. Konsole colorscheme + profile -------------------------------
    local KONSOLE_DIR="$home_dir/.local/share/konsole"
    run_as_user mkdir -p "$KONSOLE_DIR"

    if render_template "$THEME_TEMPLATES_DIR/konsole.colorscheme.tpl" "$KONSOLE_DIR/$PALETTE_SHORT.colorscheme.tmp" \
        && run_as_user mv "$KONSOLE_DIR/$PALETTE_SHORT.colorscheme.tmp" "$KONSOLE_DIR/$PALETTE_SHORT.colorscheme"; then
        log_ok "Konsole colorscheme written: $PALETTE_SHORT.colorscheme"
    else
        return 1
    fi

    if render_template "$THEME_TEMPLATES_DIR/konsole.profile.tpl" "$KONSOLE_DIR/$PALETTE_SHORT.profile.tmp" \
        && run_as_user mv "$KONSOLE_DIR/$PALETTE_SHORT.profile.tmp" "$KONSOLE_DIR/$PALETTE_SHORT.profile"; then
        log_ok "Konsole profile written: $PALETTE_SHORT.profile"
    else
        return 1
    fi

    # ---- 2. Plasma color scheme + accent --------------------------------
    local SCHEMES_DIR="$home_dir/.local/share/color-schemes"
    run_as_user mkdir -p "$SCHEMES_DIR"
    if render_template "$THEME_TEMPLATES_DIR/plasma.colors.tpl" "$SCHEMES_DIR/$PALETTE_SHORT.colors.tmp" \
        && run_as_user mv "$SCHEMES_DIR/$PALETTE_SHORT.colors.tmp" "$SCHEMES_DIR/$PALETTE_SHORT.colors"; then
        log_ok "Plasma color scheme written: $PALETTE_SHORT.colors"
    else
        return 1
    fi

        # ---- 3. Persist defaults (konsolerc, kdeglobals) --------------------
    # NOTE: these keys are CASE-SENSITIVE and Plasma 6 capitalised them.
    # Writing `accentColor` (the Plasma 5 spelling) silently does nothing, so
    # the accent reverts to blue on every login -- the single most common
    # "why isn't my theme applying?" bug. See tests/ for the guard.
    if [ -n "$KWRITECONFIG" ] || [ -n "${THEME_HOME_DIR:-}" ]; then
        if persist_palette_keys "$home_dir"; then
            log_ok "Default Konsole profile + Plasma color scheme + accent (#${C_ACCENT}) persisted."
        fi
    else
        log_warn "kwriteconfig not found — konsolerc/kdeglobals untouched; your next Konsole run still sees the new .colorscheme file."
    fi

    # ---- 4. Live reload (best effort) ------------------------------------
    if command_exists plasma-apply-colorscheme; then
        run_as_user plasma-apply-colorscheme "$PALETTE_SHORT" >/dev/null 2>&1 \
            && log_ok "Color scheme applied live (plasma-apply-colorscheme)." \
            || log_warn "plasma-apply-colorscheme did not apply cleanly — next login picks the scheme up."
    fi
    run_as_user qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
        || run_as_user qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1

    # ---- 5. Global Theme (look-and-feel wrapper) -------------------------
    # Best effort: a palette that applies but has no Global Theme is still a
    # working desktop, so a failure here must not abort the step.
    apply_global_theme "$home_dir" || log_warn "Global Theme not built — the color scheme is applied regardless."

    # ---- 5b. Catppuccin back on top --------------------------------------
    # Generated last so the shipped look survives every later palette swap.
    # Always succeeds; a no-op when Catppuccin isn't installed.
reassert_catppuccin_lnf

    # ---- 5b. GTK3/GTK4 — before the cursor block, which is deliberately last
    apply_gtk_theme "$home_dir" || true

    # ---- 5c. Cursor theme — LAST, and verified -----------------------------
    # The cursor is applied live as well as through the Global Theme, so swapping
    # a palette fixes the cursor even when the look-and-feel package is not
    # rebuilt (or on a headless box with no Plasma to reload).
    #
    # It has to run after every Plasma tool above. Each of them
    # (plasma-apply-colorscheme, plasma-apply-lookandfeel) syncs kcminputrc from
    # its own in-memory copy, and that copy never contains this key — so a cursor
    # written before them is silently deleted again a second later. Writing it
    # first "worked": the log said OK and kcminputrc had no cursorTheme in it.
    local cursor_theme
    if cursor_theme="$(resolve_cursor_theme "$home_dir")"; then
        if write_cursor_theme "$home_dir" "$cursor_theme"; then
            log_ok "Cursor theme applied: $cursor_theme"
        else
            log_warn "Could not set cursorTheme=$cursor_theme in kcminputrc — cursor unchanged."
        fi
    else
        log_warn "Cursor theme '${CURSOR_THEME:-<unset>}' is not installed — cursor left alone (see resolve_cursor_theme)."
    fi
    # Ask KWin to pick the new cursor up without waiting for a re-login. Best
    # effort: it may still be deferred to next login, which is not an error.
    run_as_user qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 \
        || run_as_user qdbus org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

    # ---- 6. Palette-specific extras --------------------------------------
    # The Otto palette additionally picks up an installed Otto Plasma theme
    # (Global Theme, Kvantum, window decoration) and recolours copies of it, so
    # the whole desktop agrees on one red. Runs after every Plasma tool above,
    # because it re-applies a Global Theme of its own and would otherwise be
    # undone by the engine's own plasma-apply-lookandfeel call.
    #
    # Best effort by construction: otto_apply_theme reports what it did and what
    # it skipped and returns 0 even with nothing installed, because a palette
    # apply that works without Otto is not a failure.
    if [ "${PALETTE_ID:-}" = "otto" ] && declare -F otto_apply_theme >/dev/null 2>&1; then
        otto_apply_theme "$home_dir" || log_warn "Otto integration incomplete — the palette itself is fully applied."
    fi

    # The moe-dark palette installs the real Moe v2.6 Global Theme from a pinned
    # mirror and rewrites the package the engine just built, so the theme
    # registered in plasmarc is the sanitised Moe one rather than the generic
    # wrapper. Same best-effort contract as Otto: a failed download leaves a
    # fully applied palette behind.
    if [ "${PALETTE_ID:-}" = "moe-dark" ] && declare -F moe_apply_theme >/dev/null 2>&1; then
        moe_apply_theme "$home_dir" || log_warn "Moe integration incomplete — the palette itself is fully applied."
    fi

    # ---- 6b. Re-assert the palette keys ----------------------------------
    # LAST, and deliberately after step 6 rather than next to step 3. Every
    # look-and-feel application rewrites kdeglobals from the package's
    # contents/defaults, so a ColorScheme written earlier does not survive it —
    # and step 6 applies one more Global Theme of its own (Otto, Moe).
    #
    # Observed live: `46-applyThemes.sh moe-dark` logged "Plasma color scheme
    # ... persisted", applied the wrapper, applied the Moe package, and left
    # kdeglobals [General] holding AccentColor and ColorSchemeHash but no
    # ColorScheme. Nothing warned; kwriteconfig6 exits 0 either way. Next login
    # comes up on Plasma's default scheme and every generated colour reverts.
    #
    # This is the same shape as the cursorTheme note in step 5c, for the same
    # reason: the fix is not "write it earlier", it is "write it last".
    # ini_set_key replaces in place, so calling it again is idempotent and does
    # not append a duplicate.
    persist_palette_keys "$home_dir" \
        || log_warn "palette keys still did not stick after the last Global Theme — check kdeglobals by hand."

    # ---- 7. State marker -------------------------------------------------
    STATE_DIR="$(theme_state_dir)"
    CURRENT_THEME_FILE="$STATE_DIR/current-theme"
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$name" > "$CURRENT_THEME_FILE"
    log_ok "Palette '$name' is now the active theme (recorded in $CURRENT_THEME_FILE)."
    return 0
}

# install_wallpaper_package <home_dir> <src_dir> <pkg_id> <display_name> [license]
#
# Wrap a directory of the user's OWN images into a Plasma 6 wallpaper KPackage
# at ~/.config/wallpapers/<pkg_id>/, so they show up in System Settings >
# Desktop > Wallpaper alongside the shipped ones.
#
# WHY THIS EXISTS: Plasma 6 will only list a wallpaper directory as a
# selectable entry if it has a metadata.json declaring the KPackage. A bare
# folder of images in ~/.local/share/backgrounds is invisible there, and the
# only way to reach it is by typing a path. (14-plasmaTheme.sh can already
# generate a gradient wallpaper from the palette, but a generated gradient is
# not a choice — this is for image sets you already like.)
#
# NO IMAGE IS COPIED INTO THE REPO. The source directory is supplied by the
# user at run time and the images are copied into the user's own ~/.config.
# That is deliberate: the repo's consistency checks forbid bundled binaries,
# and shipping someone else's wallpapers would also mean shipping their
# licence terms.
#
# The "license" argument is written only when given. Guessing CC0 for images
# of unknown provenance would be a licence claim nobody verified, and the
# field is optional in the KPlugin schema.
install_wallpaper_package() {
    local home_dir="$1" src_dir="$2" pkg_id="$3" display_name="$4" license="${5:-}"
    # Both are written into metadata.json and used as a path segment. An empty
    # value here produced .config/wallpapers/ (double slash), a package with a
    # blank Name, and a silent success.
    if [ -z "$pkg_id" ] || [ -z "$display_name" ]; then
        log_warn "install_wallpaper_package needs a non-empty package id and display name." >&2
        return 1
    fi

    local dest="$home_dir/.config/wallpapers/$pkg_id"

    if [ ! -d "$src_dir" ]; then
        log_warn "Wallpaper source directory not found: $src_dir" >&2
        return 1
    fi

    # Only real image files, and only ones that actually exist as regular files.
    local imgs=() f base
    for f in "$src_dir"/*; do
        [ -f "$f" ] || continue
        base="$(basename "$f")"
        case "${base,,}" in
            *.png|*.jpg|*.jpeg) imgs+=("$base") ;;
        esac
    done
    if [ "${#imgs[@]}" -eq 0 ]; then
        log_warn "No .png/.jpg/.jpeg images in $src_dir — nothing to install." >&2
        return 1
    fi

    run_as_user rm -rf "$dest"
    run_as_user mkdir -p "$dest/contents/images" || return 1
    local src
    for src in "${imgs[@]}"; do
        run_as_user cp -f "$src_dir/$src" "$dest/contents/images/$src" || return 1
    done

    {
        printf '{\n'
        printf '    "KPlugin": {\n'
        printf '        "Category": "Wallpapers",\n'
        printf '        "Id": "%s",\n' "$pkg_id"
        [ -n "$license" ] && printf '        "License": "%s",\n' "$license"
        printf '        "Name": "%s",\n' "$display_name"
        printf '        "Version": "1.0"\n'
        printf '    }\n'
        printf '}\n'
    } > "$dest/metadata.json"

    log_ok "Wallpaper package '$display_name' installed: ${#imgs[@]} image(s) in $dest" >&2
    printf '%s' "$dest"
    return 0
}

# apply_wallpaper_image <home_dir> <image_path> — set one image on every
# desktop, via the supported plasmashell DBus API rather than editing
# plasma-org.kde.plasma.desktop-appletsrc by hand.
#
# FillMode 4 is Zoom, which is what a 1920x1080 panel-laid desktop wants: it
# fills the screen without distorting the image. The API takes the path bare
# (no file:// scheme); passing a scheme makes Plasma store it and then fail to
# load it, which looks exactly like "the wallpaper silently didn't apply".
apply_wallpaper_image() {
    local home_dir="$1" img="$2"
    local fill="${3:-4}"

    if [ ! -f "$img" ]; then
        log_warn "Wallpaper image not found: $img"
        return 1
    fi

    local script
    script="var d = desktops();
for (var i = 0; i < d.length; i++) {
    d[i].wallpaperPlugin = 'org.kde.image';
    d[i].currentConfigGroup = ['Wallpaper', 'org.kde.image', 'General'];
    d[i].writeConfig('Image', '$img');
    d[i].writeConfig('FillMode', '$fill');
}
d.length;"

    if pgrep -x plasmashell >/dev/null 2>&1 \
       && run_as_user qdbus6 org.kde.plasmashell /PlasmaShell \
            org.kde.PlasmaShell.evaluateScript "$script" >/dev/null 2>&1; then
        log_ok "Wallpaper applied to all desktops: $(basename "$img") (FillMode=$fill)"
        return 0
    fi

    if command_exists plasma-apply-wallpaperimage; then
        run_as_user plasma-apply-wallpaperimage "$img" >/dev/null 2>&1 \
            && { log_ok "Wallpaper applied via plasma-apply-wallpaperimage."; return 0; }
    fi
    log_warn "Could not set the wallpaper live — pick it in System Settings > Desktop > Wallpaper."
    return 1
}

# kde_value <group> <key> — read one key out of ~/.config/kdeglobals.
# Used so the GTK side is derived from the KDE side rather than hardcoded,
# which is what keeps the two toolkits from drifting apart.
kde_value() {
    local home_dir="$1" group="$2" key="$3"
    awk -v g="[$2]" -v k="$3" '
        function trim(s) { sub(/^[ \t]+|[ \t\r]+$/, "", s); return s }
        /^\[/ { ingrp = (trim($0) == g); next }
        ingrp && $0 ~ ("^[ \t]*" k "[ \t]*=") {
            sub(/^[^=]*=[ \t]*/, "", $0); sub(/[ \t\r]+$/, "", $0); print; exit
        }
    ' "$home_dir/.config/kdeglobals" 2>/dev/null
}

# gtk_font_string <kde_font> — turn kdeglobals' Pango-ish
# "Family,Size,-1,Weight,..." into the "Family Size" form gtk-font-name takes.
# Only the first two fields are used; the rest (hinting, weight, embedding) have
# no GTK equivalent and are dropped rather than guessed at.
gtk_font_string() {
    local f="$1" family size
    family="$(cut -d, -f1 <<<"$f")"
    size="$(cut -d, -f2 <<<"$f")"
    family="$(sed 's/^[[:space:]]*//; s/[[:space:]]*$//' <<<"$family")"
    if [ -n "$size" ]; then printf '%s %s' "$family" "$size"; else printf '%s' "$family"; fi
}

# apply_gtk_theme <home_dir> — make GTK3/GTK4 apps follow the KDE desktop.
#
# WHY: this box keeps XFCE, so plenty of apps (GtkTerm, xfce4 apps, GTK
# Electron/Tauri apps) never touch Plasma's theming at all. Without this they
# render light GTK-default while KDE is Darkmatter — the classic split desktop.
#
# Values are READ FROM kdeglobals (icon theme, font) rather than restated, so
# there is exactly one place to change them and no way for the two to disagree.
# Only coherence keys are written; anything else already in settings.ini (image
# menus, decoration layout, warp-slider, DPI) is left untouched, because this
# function's job is to match KDE, not to restyle the user's app preferences.
apply_gtk_theme() {
    local home_dir="$1"
    local gtk_theme="${GTK_THEME:-Darkmatter}"
    local kde_icons kde_font gtk_font cursor_theme rc=0

    if [ ! -d "/usr/share/themes/$gtk_theme" ] && [ ! -d "$home_dir/.themes/$gtk_theme" ]; then
        log_warn "GTK theme '$gtk_theme' is not installed — GTK apps left alone."
        return 1
    fi

    kde_icons="$(kde_value "$home_dir" "Icons" "Theme")"
    [ -n "$kde_icons" ] || kde_icons="Papirus-Dark"

    kde_font="$(kde_value "$home_dir" "General" "font")"
    gtk_font="$(gtk_font_string "$kde_font")"

    cursor_theme="$(resolve_cursor_theme "$home_dir" || true)"

    local v
    for v in gtk-3.0 gtk-4.0; do
        local f="$home_dir/.config/$v/settings.ini"
        ini_set_key "$f" "Settings" "gtk-theme-name" "$gtk_theme" || rc=1
        ini_set_key "$f" "Settings" "gtk-icon-theme-name" "$kde_icons" || rc=1
        ini_set_key "$f" "Settings" "gtk-application-prefer-dark-theme" "true" || rc=1
        [ -n "$gtk_font" ] && { ini_set_key "$f" "Settings" "gtk-font-name" "$gtk_font" || rc=1; }
        # Only advertise a cursor that exists: a missing name renders as no
        # cursor in GTK apps rather than falling back.
        [ -n "$cursor_theme" ] && { ini_set_key "$f" "Settings" "gtk-cursor-theme-name" "$cursor_theme" || rc=1; }
    done

    if [ "$rc" -eq 0 ]; then
        log_ok "GTK3/GTK4 follow KDE: theme=$gtk_theme icons=$kde_icons${gtk_font:+ font=$gtk_font}${cursor_theme:+ cursor=$cursor_theme}"
    else
        log_warn "Could not fully write GTK settings.ini — GTK apps may not match KDE."
    fi
    return "$rc"
}

# apply_global_theme <home_dir> — build and register a Plasma 6 Global Theme
# (look-and-feel package) for the currently-loaded palette, so the palette shows
# up in System Settings > Appearance > Global Theme as a single clickable entry
# instead of a color scheme buried in a dropdown.
#
# The layout is Plasma 6's KPackage structure, matching what KDE's own
# breezedark.desktop and upstream Catppuccin ship:
#
#   metadata.json          REQUIRED manifest. The top-level
#                          "KPackageStructure": "Plasma/LookAndFeel" is what
#                          Plasma 6 matches against; without it the package
#                          installs cleanly and is then REFUSED by
#                          plasma-apply-lookandfeel, which logs
#                          'KPackageStructure ... does not match requested
#                          format "Plasma/LookAndFeel"' and omits the theme from
#                          --list and from System Settings. The symptom is
#                          silent: kdeglobals gets AccentColor, the desktop still
#                          shows BreezeLight, and nothing errored.
#   contents/defaults      The config to write when the theme is applied. This is
#                          where ColorScheme is referenced BY NAME; the .colors
#                          file stays in ~/.local/share/color-schemes/ and is
#                          shared with the palette engine rather than duplicated.
#   contents/colors        A REAL copy of the .colors file. NOT a symlink.
#                          Plasma 6 kpackages do not support symlinks, so the
#                          older Plasma 5 idiom of symlinking a shared color
#                          scheme in from a relative path cannot work here.
#
# Deliberately omitted: `contents/layouts/` and `contents/widgets/`. Shipping an
# empty layouts dir would claim a DesktopLayout the theme does not actually
# provide, and Plasma would apply an empty panel instead of the user's.
# resolve_cursor_theme — print the cursor theme id this palette declares, but
# only when that theme actually exists on disk.
#
# A palette may set CURSOR_THEME (e.g. "Bibata-Modern-Ice"). Pointing Plasma at a
# cursor id that is not installed is worse than not setting one: kcmininputrc
# resolves the name to a directory of Xcursor files, and a missing one yields no
# cursor rather than falling back. So the existence check is load-bearing, not
# defensive. Returns 1 when the palette declares nothing or it is missing.
resolve_cursor_theme() {
    local want="${CURSOR_THEME:-}"
    [ -n "$want" ] || return 1
    local home_dir="${1:-}"
    [ -n "$home_dir" ] || home_dir="$HOME"
    local d
    for d in "$home_dir/.local/share/icons/$want" \
             "/usr/share/icons/$want" \
             "$home_dir/.icons/$want"; do
        [ -d "$d" ] && { printf '%s' "$want"; return 0; }
    done
    return 1
}

apply_global_theme() {
    local home_dir="$1"
    local lnf_id="${PALETTE_SHORT}Theme"
    local lnf_root="$home_dir/.local/share/plasma/look-and-feel"
    local lnf_dir="$lnf_root/$lnf_id"
    local colors_file="$home_dir/.local/share/color-schemes/$PALETTE_SHORT.colors"

    if [ ! -f "$colors_file" ]; then
        log_warn "No color scheme at $colors_file — skipping Global Theme."
        return 1
    fi

    run_as_user rm -rf "$lnf_dir"
    run_as_user mkdir -p "$lnf_dir/contents"
    # Provenance marker. The wrapper's Name/Description come from the palette,
    # and for otto they literally contain the word "Otto" — so otto.sh's
    # discovery would otherwise recognise this generated wrapper as an
    # installed Otto Global Theme and recolour it as its own source. Marking it
    # makes "is this upstream or ours?" a fact rather than a guess.
    run_as_user touch "$lnf_dir/$DEVMKDE_GENERATED_MARKER" 2>/dev/null || true

    # metadata.json — hand-written so it stays readable and greppable; the
    # template engine only expands hex/RGB, and JSON needs quotes and braces.
    cat > "$lnf_dir/metadata.json" <<EOF
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [
            {
                "Name": "Devuan KDE Setup"
            }
        ],
        "Category": "Global Themes (Plasma 6)",
        "Description": "$PALETTE_DESC",
        "Icon": "preferences-desktop-theme",
        "Id": "$lnf_id",
        "License": "GPL-2.0-or-later",
        "Name": "$PALETTE_NAME",
        "ServiceTypes": [
            "Plasma/LookAndFeel"
        ],
        "Version": "$THEME_VERSION",
        "Website": "https://github.com/devuan-kde/Devuan-Kde"
    }
}
EOF

    # contents/defaults — THIS is how a Plasma 6 LookAndFeel applies. Verified
    # against the two themes that demonstrably work on this box:
    # /usr/share/plasma/look-and-feel/org.kde.breezedark.desktop and the
    # Catppuccin package. Neither has a contents/colors entry; both drive every
    # visible component through this file. Each `[<config file>][<group>]` header
    # makes Plasma write those keys into that file when the theme is applied.
    #
    # It previously emitted `[kdeglobals][General]` TWICE — once for
    # ColorScheme, once for AccentColor — so the two keys landed in duplicate
    # blocks whose merge behaviour is not something to rely on, and the block
    # omitted cursorTheme, [plasmarc][Theme] and [org.kde.kdecoration2]
    # entirely. Applying the theme therefore moved two colors and left the
    # previous theme's cursor, window decoration and splash untouched, which is
    # exactly the half-themed desktop this file is supposed to prevent.
    {
        printf '[kdeglobals][General]\n'
        printf 'ColorScheme=%s\n' "$PALETTE_SHORT"
        [ -n "${C_ACCENT:-}" ] && printf 'AccentColor=#%s\n' "$C_ACCENT"

        # A cursor is the one pixel the eye follows onto every window, so a
        # theme that recolors everything except the cursor is still incoherent.
        # The palette declares one; resolve_cursor_theme only reports it if it is
        # actually installed, so we never point Plasma at a theme id that does
        # not exist (which renders as no cursor at all).
        #
        # It is deliberately NOT emitted into contents/defaults, even though a
        # stock theme does exactly that (org.kde.breezedark.desktop ships
        # [kcminputrc][Mouse] cursorTheme=breeze_cursors). On Plasma 6.3 KConfig
        # declines to store this key, so applying the Global Theme at login
        # rewrites kcminputrc from a copy that never had it — deleting the cursor
        # theme that write_cursor_theme had just put there. The result was a
        # cursor that reverted on every single login. apply_palette sets the
        # cursor directly instead, and verifies it; see write_cursor_theme.
        if [ -n "${CURSOR_THEME:-}" ] && ! resolve_cursor_theme "$home_dir" >/dev/null 2>&1; then
            log_warn "palette wants cursor '$CURSOR_THEME' but it is not installed — leaving the cursor alone. Install it with: apt-get install bibata-cursor-theme"
        fi

        printf '\n[plasmarc][Theme]\n'
        printf 'name=default\n'

        # Breeze KDecoration2 rather than an Aurorae SVG: it ships with Plasma,
        # so it always matches the Plasma version in use, and it needs no new
        # assets. BorderSize=None keeps the borderless look this desktop already
        # had via the Catppuccin theme it replaces.
        printf '\n[kwinrc][org.kde.kdecoration2]\n'
        printf 'library=org.kde.breeze\n'
        printf 'theme=Breeze\n'
        printf 'BorderSize=None\n'
        printf 'BorderSizeAuto=false\n'
    } > "$lnf_dir/contents/defaults"

    # contents/colors — a real file copy, kept for anyone (or any tool) that
    # expects the file to be present next to the manifest. It is NOT how Plasma 6
    # picks up colors: nothing in Plasma 6 reads a theme's contents/colors, and
    # no shipped theme has one. The symlink convention inherited from Plasma 5
    # is both unsupported here and unverifiable.
    run_as_user cp -f "$colors_file" "$lnf_dir/contents/colors"

    # Plasma 6 ships `plasma-apply-lookandfeel`; keep a lookandfeelrc note so a
    # headless box (no running plasma shell) still persists the choice.
    if command_exists plasma-apply-lookandfeel; then
        if run_as_user plasma-apply-lookandfeel --apply "$lnf_id" >/dev/null 2>&1; then
            log_ok "Global Theme applied: $PALETTE_NAME"
        else
            log_warn "plasma-apply-lookandfeel didn't apply cleanly — next login picks it up."
        fi
    else
        log_warn "plasma-apply-lookandfeel not found — Global Theme written to $lnf_dir but not applied."
    fi

    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file lookandfeeltoolrc --group "Global Theme" --key "LookAndFeelPackage" "$lnf_id"
    fi

    # The registration that actually matters. `plasma-apply-lookandfeel` exits 0
    # on this box WITHOUT writing anything: deleting [Theme]
    # LookAndFeelPackage from plasmarc, running the tool, and re-reading shows
    # the key still absent. So the tool call above cannot be trusted to
    # register the theme, and lookandfeeltoolrc — which the engine writes — is
    # the tool's own bookkeeping, not a file Plasma reads.
    #
    # Plasma 6 keeps the active look-and-feel package in
    # ~/.config/plasmarc, group [Theme]. Write it directly and read it back;
    # only then claim the theme is registered.
    if ini_set_key "$home_dir/.config/plasmarc" "Theme" "LookAndFeelPackage" "$lnf_id"; then
        log_ok "Global Theme registered: $lnf_id (plasmarc)"
    else
        log_err "Could not set [Theme] LookAndFeelPackage=$lnf_id in $home_dir/.config/plasmarc"
        log_err "Add it by hand (System Settings > Appearance > Global Theme also works):"
        log_err "  kwriteconfig6 --file plasmarc --group Theme --key LookAndFeelPackage $lnf_id"
    fi
    return 0
}

# reassert_catppuccin_lnf — put the upstream Catppuccin Global Theme back on top
# after a palette has been applied, if it is installed.
#
# WHY THIS IS NEEDED: Catppuccin's contents/defaults sets
#   [kdeglobals][General] ColorScheme=CatppuccinMochaRed
# so applying Catppuccin replaces the palette engine's Plasma color scheme. The
# original design wanted Catppuccin to own the Plasma look (widgets, aurorae
# window decoration, cursor, splash) while the palette owned Konsole, the
# wallpaper and the generated .colors file — and the reverse had to hold too, so
# `46-applyThemes.sh` re-applying a palette could not silently drift the desktop
# off the shipped look.
#
# WHY IT IS NOW PALETTE-AWARE: that unconditional reassert is precisely why the
# desktop ended up split-brained. The palette marker, Konsole scheme and accent
# were all Darkmatter while the actual Plasma chrome came from Catppuccin, and no
# amount of re-applying Darkmatter could fix it — every apply reasserted
# Catppuccin again. Reasserting is now correct only when a Catppuccin palette is
# actually the one being applied; for any other palette the generated Global
# Theme must be allowed to stand, or the two palettes can never converge.
#
# DEVMKDE_PREFER_CATPPUCCIN=0 forces the Catppuccin theme off in every case.
reassert_catppuccin_lnf() {
    command_exists plasma-apply-lookandfeel || return 0
    # Documented opt-out. A non-empty test cannot express this: "0" is non-empty,
    # so `[ -n ... ]` would let DEVMKDE_PREFER_CATPPUCCIN=0 through and reassert
    # anyway. Compare the value instead.
    [ "${DEVMKDE_PREFER_CATPPUCCIN:-1}" != "0" ] || return 0

    # Map palette -> the one Global Theme whose colours it actually came from.
    #
    # This must be an exact allowlist, not a pattern match on "catppuccin" or
    # "mocha": Catppuccin ships one Global Theme per flavour, and matching a
    # family name reasserts whichever flavour happened to be installed under
    # every Catppuccin-flavoured palette. That is how mocha-blue and frappe
    # ended up wearing the Mocha RED theme. Add a flavour here only once its
    # own theme id is installed.
    local want=""
    case "${PALETTE_ID:-}" in
        mocha-red) want="Catppuccin-Mocha-Red" ;;
    esac

    if [ -z "$want" ]; then
        log_info "Palette '${PALETTE_ID:-?}' does not come from a Catppuccin Global Theme — leaving its own theme active."
        return 0
    fi

    # Exact match on the whole line: --list prints one bare id per line.
    local lnf_id
    lnf_id="$(run_as_user plasma-apply-lookandfeel --list 2>/dev/null \
        | grep -ix "$want" | head -1)"

    if [ -n "$lnf_id" ]; then
        run_as_user plasma-apply-lookandfeel --apply "$lnf_id" >/dev/null 2>&1 \
            && log_ok "Catppuccin Global Theme re-applied ($lnf_id) — it owns the Plasma look."
    else
        # Not installed is the normal state on a box that skipped Catppuccin, so
        # this is informational rather than a warning about a broken theme.
        log_info "Catppuccin Global Theme not installed — the palette's own Global Theme stays active."
    fi
    return 0
}

# apply_palette_by_short <Short> — locate a palette by its PALETTE_SHORT
# (e.g. "CatppuccinRed") and apply it; used when only the scheme name is known.
apply_palette_by_short() {
    local short="$1" id
    while IFS= read -r id; do
        [ -n "$id" ] || continue
        if [ "$(palette_field "$id" PALETTE_SHORT)" = "$short" ]; then
            apply_palette "$id" || return 1
            return 0
        fi
    done < <(palettes_registered)
    log_err "No palette rendered under the name '$short'."
    return 1
}