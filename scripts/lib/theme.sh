#!/usr/bin/env bash
# =======================================================
# theme.sh — the palette theme engine (sourced by scripts)
# -------------------------------------------------------
# Turns the plain hex palettes in themes/<name>/palette.sh into a
# coherent KDE Plasma color story in one call:
#
#   ~/.local/share/konsole/<Short>.colorscheme   Konsole terminal ANSI palette
#   ~/.local/share/konsole/<Short>.profile       a Konsole profile pointing at it
#   ~/.local/share/color-schemes/<Short>.colors  KDE Plasma color scheme
#   konsolerc (DefaultProfile) + kdeglobals (ColorScheme + accentColor)
#
# Every <name>/palette.sh defines the same set of variables (see the
# schema in themes/mocha-red/palette.sh or any sibling); the templates in
# themes/_base/tpl/ reference them as @VAR@ (hex) or @RG_VAR@ (decimal
# "R,G,B") and are expanded with sed — no runtime per-color hardcoding,
# so adding a palette is adding one directory, nothing else.
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

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devuan-kde-setup"
CURRENT_THEME_FILE="$STATE_DIR/current-theme"

# Every variable a palette may define (and thus every @VAR@ a template may
# reference). RG_* twins are derived from the C_* entries at load time.
_PALETTE_VARS=(PALETTE_ID PALETTE_NAME PALETTE_SHORT PALETTE_DESC
    C_BG C_MANTLE C_CRUST C_SURFACE0 C_SURFACE1 C_OVERLAY0 C_OVERLAY1
    C_TEXT C_SUBTEXT0 C_SUBTEXT1
    C_ACCENT C_ACCENT_FG C_ACCENT_DIM
    C_0 C_1 C_2 C_3 C_4 C_5 C_6 C_7 C_8 C_9 C_10 C_11 C_12 C_13 C_14 C_15)

# hex2rgb <hex> — 6-hex digit color → decimal "R,G,B". Returns the string
# on stdout; empty and status 1 for bad input.
hex2rgb() {
    local h="${1#\#}"
    [ "${#h}" -eq 6 ] || { echo ""; return 1; }
    printf "%d,%d,%d" "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
}

# list_palettes — one line per palette: "id|Short|Name".
list_palettes() {
    local dir
    for dir in "$THEMES_DIR"/*/; do
        [ -f "$dir/palette.sh" ] || continue
        local id
        id="$(basename "$dir")"
        [ "$id" = "_base" ] && continue
        local short name
        short="$(PALETTE_SHORT= bash -c "source '$dir/palette.sh' 2>/dev/null; printf '%s' \"\${PALETTE_SHORT:-}\"")"
        name="$(PALETTE_NAME= bash -c "source '$dir/palette.sh' 2>/dev/null; printf '%s' \"\${PALETTE_NAME:-}\"")"
        echo "$id|$short|$name"
    done | sort
}

# load_palette <dir> — sources a palette.sh; aborts when required vars are
# missing so templates never render blanks.
load_palette() {
    local dir="$1"
    [ -f "$dir/palette.sh" ] || { log_err "No palette at $dir — is themes/<name>/palette.sh present?"; return 1; }
    # shellcheck source=/dev/null
    source "$dir/palette.sh"

    local missing=() v
    for v in "${_PALETTE_VARS[@]}"; do
        [ -n "${!v-}" ] || missing+=("$v")
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        log_err "palette.sh missing required vars: ${missing[*]}"
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
apply_palette() {
    local name="$1"
    local dir="$THEMES_DIR/$name"
    load_palette "$dir" || return 1

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
    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file konsolerc --group "Desktop Entry" --key DefaultProfile "$PALETTE_SHORT.profile"
        kwrite_user --file kdeglobals --group General --key ColorScheme "$PALETTE_SHORT"
        kwrite_user --file kdeglobals --group General --key accentColor "#${C_ACCENT}"
        kwrite_user --file kdeglobals --group General --key accentColorFromWallpaper "false"
        log_ok "Default Konsole profile + Plasma color scheme + accent (#${C_ACCENT}) persisted."
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

    # ---- 5. State marker -------------------------------------------------
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$name" > "$CURRENT_THEME_FILE"
    log_ok "Palette '$name' is now the active theme (recorded in $CURRENT_THEME_FILE)."
    return 0
}

# apply_palette_by_short <Short> — locate a palette by its PALETTE_SHORT
# (e.g. "CatppuccinRed") and apply it; used when only the scheme name is known.
apply_palette_by_short() {
    local short="$1" dir
    for dir in "$THEMES_DIR"/*/; do
        [ -f "$dir/palette.sh" ] || continue
        [ "$(basename "$dir")" = "_base" ] && continue
        if [ "$(PALETTE_SHORT= bash -c "source '$dir/palette.sh' 2>/dev/null; printf '%s' \"\${PALETTE_SHORT:-}\"")" = "$short" ]; then
            apply_palette "$(basename "$dir")" || return 1
            return 0
        fi
    done
    log_err "No palette rendered under the name '$short'."
    return 1
}