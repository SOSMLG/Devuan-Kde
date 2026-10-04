#!/usr/bin/env bash
# =======================================================
# otto.sh — Otto theme discovery + recolouring (sourced by theme.sh)
# -------------------------------------------------------
# The Otto Plasma theme (Bhushan Shah, store.kde.org/p/1358262/) ships as five
# separate GUI packages: a Global Theme, a Kvantum theme, a window decoration,
# a set of color schemes and a Konsole scheme. This toolkit bundles NONE of
# them, for two reasons:
#
#   1. store.kde.org is behind an Anubis proof-of-work gate, so there is no
#      URL a script can download from. The intended install path is the KDE
#      GUI: Discover, or "Get New..." in System Settings > Appearance.
#   2. Bundling someone else's theme would mean shipping their artwork and
#      licence terms in this repo.
#
# What this file does instead: find an installed Otto in the five places
# Plasma/Kvantum/KWin actually look, then recolour copies of it to the
# current palette's values so the desktop is one coherent red/black instead of
# "Otto's own red" plus "the palette's red".
#
# TWO RULES THAT EVERY FUNCTION HERE FOLLOWS:
#
#   Never modify what the package installed. Every write lands in a NEW
#   id derived from PALETTE_SHORT (OttoRed, OttoRed-Kvantum, ...). The
#   pristine Otto tree stays exactly as the GUI wrote it, so uninstalling or
#   switching back is a file deletion rather than a forensic exercise.
#
#   Absence is normal, not an error. A machine that never installed Otto is a
#   perfectly good machine: the palette engine has already produced a
#   complete, self-consistent Konsole scheme + .colors file + Global Theme
#   without any of this. So every function here reports what it did and what
#   it skipped, and returns 0 either way.
#
# WHAT IS *NOT* RECOLOURED, AND WHY
#
#   Konsole/.colors      The palette engine generates these itself, so they are
#                        already correct. Otto's own scheme is still recoloured
#                        (otto_recolor_konsole) and installed under a
#                        PALETTE_SHORT-prefixed name, but the default profile
#                        stays the generated one.
#   Kvantum's SVG assets Kvantum resolves most widget colours through
#                        KvAnt/general/*.conf (which IS recoloured) but draws
#                        shape detail from .svg files that carry literal fills.
#                        Rewriting those needs per-file knowledge of which
#                        elements are "the accent" versus "a highlight"; a
#                        blanket substitution either misses the accent or
#                        recolours something structural. So the SVGs ship as
#                        Otto drew them and the log says so, rather than
#                        producing a Kvantum theme that looks broken in ways
#                        nobody can debug.
#   Otto's wallpaper     Left alone when Otto ships its own (it is artwork, not
#                        a palette); a palette-tinted gradient is generated
#                        only when Otto ships no wallpaper at all.
#
# Dependency: lib/common.sh (log_*, run_as_user, ini_set_key) and lib/theme.sh
# (the palette variables C_*/RG_* are read from the *loaded* palette, never
# re-sourced here).
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVUAN_KDE_OTTO_SH_LOADED:-}" ] && return 0
_DEVUAN_KDE_OTTO_SH_LOADED=1

# The id everything of ours is written under. OttoRed, not OttoRedTheme —
# this is the LNF *package* id, and OttoRedTheme is what apply_global_theme
# generates for the palette's own wrapper theme.
OTTO_LNF_ID="${OTTO_LNF_ID:-${PALETTE_SHORT:-OttoRed}}"

# ---------------------------------------------------------------------------
# Discovery
# ---------------------------------------------------------------------------

# --- provenance marking -----------------------------------------------------
#
# Every artefact this toolkit writes gets a marker file naming its palette.
# Discovery consults it, so "is this the installed Otto, or is this something we
# generated last time?" is answered by provenance instead of by guessing at
# directory names.
#
# Why this exists: otto_is_otto matches any *declared* field whose value mentions
# Otto, and the Global Theme wrapper apply_global_theme generates for this very
# palette declares Name "Otto Red" / Description "Otto-inspired ...". So a
# second `apply_palette otto` found its OWN OUTPUT in look-and-feel, reported
# "Otto Global Theme applied", and copied the wrapper over itself. The Kvantum
# output was worse: its id is derived from the source name plus the palette, so
# every rerun rediscovered the previous run's directory and appended another
# suffix — Otto-Dark-OttoRed, then Otto-Dark-OttoRed-OttoRed, forever. Neither
# run crashed and neither printed a warning, so this was invisible.
# The marker filename now lives in lib/common.sh (DEVMKDE_GENERATED_MARKER)
# because moe.sh and theme.sh need the same one. This alias stays so the name
# otto.sh's own discovery reads is unchanged.
OTTO_GENERATED_MARKER="${DEVMKDE_GENERATED_MARKER:-.devmkde-generated}"

# otto_mark_generated <dir>
#
# Records that <dir> is ours. Best-effort: a read-only destination must not abort
# a theme application, it just leaves discovery relying on the name fallback.
otto_mark_generated() {
    local dir="$1"
    [ -d "$dir" ] || return 1
    printf 'palette=%s\ngenerated_by=devuan-kde-setup\n' "${PALETTE_SHORT:-unknown}" \
        > "$dir/$OTTO_GENERATED_MARKER" 2>/dev/null || return 1
    return 0
}

# otto_is_generated <dir> — is <dir> one of ours?
#
# The marker is authoritative. The name fallback covers directories written
# before the marker existed (an upgrade, or output from a previous version) —
# without it those are exactly the directories that get mistaken for upstream
# and copied into, compounding on every run.
otto_is_generated() {
    local dir="$1" base
    [ -n "$dir" ] || return 1
    [ -f "$dir/$OTTO_GENERATED_MARKER" ] && return 0
    base="$(basename "$dir")"
    # The LNF id this palette writes under, and the wrapper apply_global_theme
    # generates beside it.
    [ "$base" = "$OTTO_LNF_ID" ] && return 0
    [ -n "${PALETTE_SHORT:-}" ] && [ "$base" = "${PALETTE_SHORT}Theme" ] && return 0
    # Kvantum output is "<source base>-<palette>"; the Konsole artefacts are
    # "<palette>-Otto". Both are suffixes this palette appends to itself, so an
    # upstream directory cannot carry them unless it was made here.
    if [ -n "${PALETTE_SHORT:-}" ]; then
        case "$base" in
            *-"$PALETTE_SHORT"|"$PALETTE_SHORT"-Otto) return 0 ;;
        esac
    fi
    return 1
}

# otto_is_otto <dir> — does this KPackage/Kvantum directory belong to Otto?
#
# Matches on the *declared* name, never on the directory name alone: Discover
# installs into id-derived directories, but a hand-copied folder can be called
# anything, and matching "otto" in a path would happily latch onto
# ~/.local/share/plasma/look-and-feel/OttoTheme-NIGHTLY (a different upstream
# theme with a similar name) and then recolour someone else's work.
otto_is_otto() {
    local dir="$1" meta="$1/metadata.json"
    [ -f "$meta" ] || return 1
    # A declared field (Id/Name/Description/Category) whose VALUE mentions Otto.
    # Anchored on the quoted value so a directory path or an unrelated key that
    # happens to contain the letters cannot produce a match.
    grep -qiE '"(Id|Name|Description|Category)"[[:space:]]*:[[:space:]]*"[^"]*[Oo]tto' "$meta"
}

# otto_find_lnf <home_dir> — print the installed Otto Global Theme directory.
# Searches every location Plasma 6 looks, user before system, and skips anything
# this toolkit generated so a rerun cannot "discover" what it just wrote.
otto_find_lnf() {
    local home_dir="$1" base d
    for base in "$home_dir/.local/share/plasma/look-and-feel" \
                "$home_dir/.local/share/plasma/lookandfeel" \
                "/usr/local/share/plasma/look-and-feel" \
                "/usr/share/plasma/look-and-feel"; do
        [ -d "$base" ] || continue
        for d in "$base"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            otto_is_generated "$d" && continue
            otto_is_otto "$d" && { printf '%s' "$d"; return 0; }
        done
    done
    return 1
}

# otto_find_decor <home_dir> — print the installed Otto window decoration
# directory. KWin looks in ~/.local/share/kwin/decorations and
# /usr/share/kwin/decorations (plus /usr/local in between).
otto_find_decor() {
    local home_dir="$1" base d
    for base in "$home_dir/.local/share/kwin/decorations" \
                "/usr/local/share/kwin/decorations" \
                "/usr/share/kwin/decorations"; do
        [ -d "$base" ] || continue
        for d in "$base"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            otto_is_generated "$d" && continue
            otto_is_otto "$d" && { printf '%s' "$d"; return 0; }
        done
    done
    return 1
}

# otto_find_kvantum <home_dir> — print the installed Otto Kvantum theme
# directory. Kvantum themes are identified by DIRECTORY NAME (that is the
# theme id used in Kvantum.conf), and they usually have no metadata.json at
# all — so identity falls back to the name, and the name match is anchored to
# a whole path segment so "OttoDark" does not match a directory merely
# containing that text.
otto_find_kvantum() {
    local home_dir="$1" base d
    for base in "$home_dir/.config/Kvantum" \
                "$home_dir/.local/share/Kvantum" \
                "/etc/XDG/Kvantum" \
                "/usr/local/share/Kvantum" \
                "/usr/share/Kvantum"; do
        [ -d "$base" ] || continue
        for d in "$base"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            # Before the name test: the name test matches "*Otto*", and our own
            # output id is built from the source name plus this palette.
            otto_is_generated "$d" && continue
            case "$(basename "$d")" in
                *[Oo]tto*)
                    # A Kvantum theme dir is recognised by its KvAnt/ subtree.
                    [ -d "$d/KvAnt" ] || continue
                    printf '%s' "$d"
                    return 0
                    ;;
            esac
        done
    done
    return 1
}

# otto_find_wallpapers <lnf_dir> — print Otto's wallpaper images, if the
# package ships any. Looked for inside the Global Theme (contents/wallpapers),
# which is where a Plasma 6 theme keeps them, and in the standalone wallpaper
# package Discover installs.
otto_find_wallpapers() {
    local lnf_dir="$1" home_dir="$2" f
    for f in "$lnf_dir"/contents/wallpapers/*.png \
             "$lnf_dir"/contents/wallpapers/*.jpg \
             "$home_dir"/.local/share/wallpapers/*Otto*/*.png \
             "$home_dir"/.local/share/wallpapers/*Otto*/*.jpg; do
        [ -f "$f" ] && { printf '%s' "$f"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# Recolour maps
# ---------------------------------------------------------------------------

# otto_role_for_colors_key <key> — map a Plasma ColorScheme key to a palette
# role, printing the ROLE NAME (not a colour, so the caller decides hex vs
# decimal). Empty output means "this key is not ours" and the value is left
# alone.
#
# The ColorScheme spec keys are semantic (Background, Selection, Decoration,
# View, Header, ...), which is what makes this generic: it recolours Otto's
# scheme, Breeze's, or any other scheme that follows the spec, and it never
# depends on knowing Otto's particular hex values.
otto_role_for_colors_key() {
    case "$1" in
        # ---- [Colors] ----------------------------------------------------
        # Background here is the WINDOW background and Foreground the default
        # text colour — in [Colors:Selection] the same words mean something
        # else (selection colours), which is handled by its own entries below.
        Background)         printf 'C_BG' ;;
        Foreground)         printf 'C_TEXT' ;;
        Color0A)            printf 'C_0' ;;
        Color0B)            printf 'C_1' ;;
        Color0C)            printf 'C_2' ;;
        Color0D)            printf 'C_3' ;;
        Color0E)            printf 'C_4' ;;
        Color0F)            printf 'C_5' ;;
        Color[1-8])         printf 'C_%s' "${1#Color}" ;;
        # ---- [Background] -----------------------------------------------
        BackgroundNormal)   printf 'C_BG' ;;
        BackgroundAlternate) printf 'C_MANTLE' ;;
        BackgroundFocus)    printf 'C_SURFACE0' ;;
        BackgroundHover)    printf 'C_SURFACE1' ;;
        BackgroundActive)   printf 'C_SURFACE1' ;;
        BackgroundInactive) printf 'C_MANTLE' ;;
        BackgroundNormalLink) printf 'C_ACCENT' ;;
        BackgroundActiveLink) printf 'C_ACCENT' ;;
        BackgroundInactiveLink) printf 'C_ACCENT_DIM' ;;
        BackgroundWarning)  printf 'C_3' ;;
        BackgroundError)    printf 'C_1' ;;
        # ---- [Button] ----------------------------------------------------
        ButtonBackground)        printf 'C_SURFACE0' ;;
        ButtonBackgroundHover)   printf 'C_SURFACE1' ;;
        ButtonBackgroundActive)  printf 'C_SURFACE1' ;;
        ButtonBackgroundInactive) printf 'C_MANTLE' ;;
        ButtonForeground)        printf 'C_TEXT' ;;
        ButtonForegroundHover)   printf 'C_TEXT' ;;
        ButtonForegroundActive)  printf 'C_TEXT' ;;
        ButtonForegroundInactive) printf 'C_SUBTEXT1' ;;
        # ---- [Header] ----------------------------------------------------
        HeaderBackground)        printf 'C_CRUST' ;;
        HeaderBackgroundHover)   printf 'C_SURFACE0' ;;
        HeaderBackgroundActive)  printf 'C_SURFACE1' ;;
        HeaderBackgroundInactive) printf 'C_MANTLE' ;;
        HeaderForeground)        printf 'C_TEXT' ;;
        HeaderForegroundHover)   printf 'C_TEXT' ;;
        HeaderForegroundActive)  printf 'C_TEXT' ;;
        HeaderForegroundInactive) printf 'C_SUBTEXT1' ;;
        HeaderSeparator)         printf 'C_SURFACE1' ;;
        HeaderHighlight)         printf 'C_SURFACE0' ;;
        HeaderHighlightedText)   printf 'C_TEXT' ;;
        # ---- [Selection] -------------------------------------------------
        SelectionBackground)      printf 'C_ACCENT' ;;
        SelectionBackgroundHover) printf 'C_ACCENT' ;;
        SelectionBackgroundActive) printf 'C_ACCENT' ;;
        SelectionBackgroundInactive) printf 'C_ACCENT_DIM' ;;
        SelectionForeground)      printf 'C_ACCENT_FG' ;;
        SelectionForegroundHover) printf 'C_ACCENT_FG' ;;
        SelectionForegroundActive) printf 'C_ACCENT_FG' ;;
        SelectionForegroundInactive) printf 'C_ACCENT_FG' ;;
        SelectionBackgroundNormal) printf 'C_ACCENT' ;;
        # ---- [Window] ----------------------------------------------------
        WindowBackground)        printf 'C_BG' ;;
        WindowBackgroundHover)   printf 'C_SURFACE0' ;;
        WindowBackgroundActive)  printf 'C_SURFACE0' ;;
        WindowForeground)        printf 'C_TEXT' ;;
        WindowForegroundHover)   printf 'C_TEXT' ;;
        WindowForegroundActive)  printf 'C_TEXT' ;;
        WindowForegroundInactive) printf 'C_SUBTEXT1' ;;
        WindowText)              printf 'C_TEXT' ;;
        # ---- [Decoration] ------------------------------------------------
        DecorationBackground)      printf 'C_MANTLE' ;;
        DecorationBackgroundHover) printf 'C_SURFACE1' ;;
        DecorationBackgroundActive) printf 'C_SURFACE1' ;;
        DecorationForeground)      printf 'C_TEXT' ;;
        DecorationForegroundHover) printf 'C_TEXT' ;;
        DecorationForegroundActive) printf 'C_TEXT' ;;
        DecorationForegroundInactive) printf 'C_SUBTEXT1' ;;
        DecorationFocus)           printf 'C_ACCENT' ;;
        DecorationFocusHover)      printf 'C_ACCENT' ;;
        DecorationFocusActive)     printf 'C_ACCENT' ;;
        DecorationFocusInactive)   printf 'C_ACCENT_DIM' ;;
        DecorationFocusText)       printf 'C_ACCENT_FG' ;;
        DecorationFocusTextHover)  printf 'C_ACCENT_FG' ;;
        DecorationFocusTextActive) printf 'C_ACCENT_FG' ;;
        DecorationFocusTextInactive) printf 'C_ACCENT_FG' ;;
        DecorationWarning)         printf 'C_3' ;;
        DecorationError)           printf 'C_1' ;;
        # ---- [Tooltip] ----------------------------------------------------
        TooltipBackground)        printf 'C_OVERLAY0' ;;
        TooltipForeground)        printf 'C_TEXT' ;;
        TooltipBackgroundInactive) printf 'C_OVERLAY0' ;;
        TooltipForegroundInactive) printf 'C_SUBTEXT1' ;;
        # ---- [View] ------------------------------------------------------
        ViewBackground)        printf 'C_BG' ;;
        ViewBackgroundHover)   printf 'C_SURFACE0' ;;
        ViewBackgroundActive)  printf 'C_SURFACE0' ;;
        ViewForeground)        printf 'C_TEXT' ;;
        ViewForegroundHover)   printf 'C_TEXT' ;;
        ViewForegroundActive)  printf 'C_TEXT' ;;
        ViewForegroundInactive) printf 'C_SUBTEXT1' ;;
        ViewText)              printf 'C_TEXT' ;;
        ViewPlaceholderText)   printf 'C_SUBTEXT1' ;;
        # ---- [Menu] / [PopupMenu] ---------------------------------------
        MenuBackground)        printf 'C_SURFACE0' ;;
        MenuForeground)        printf 'C_TEXT' ;;
        MenuSeparator)         printf 'C_SURFACE1' ;;
        MenuShortcutBackground) printf 'C_SURFACE0' ;;
        PopupMenuBackground)      printf 'C_SURFACE0' ;;
        PopupMenuForeground)      printf 'C_TEXT' ;;
        PopupMenuSeparator)       printf 'C_SURFACE1' ;;
        PopupMenuShortcutBackground) printf 'C_SURFACE0' ;;
        # ---- [TabBar] / [Tab] -------------------------------------------
        TabBarBackground)        printf 'C_CRUST' ;;
        TabBarSeparator)         printf 'C_SURFACE1' ;;
        TabBackground)           printf 'C_SURFACE0' ;;
        TabBackgroundHover)      printf 'C_SURFACE1' ;;
        TabBackgroundActive)     printf 'C_MANTLE' ;;
        TabBackgroundInactive)   printf 'C_CRUST' ;;
        TabBarBackgroundActive)  printf 'C_SURFACE0' ;;
        TabBarText)              printf 'C_TEXT' ;;
        TabBarTextActive)        printf 'C_TEXT' ;;
        TabBarTextInactive)      printf 'C_SUBTEXT1' ;;
        TabText)                 printf 'C_TEXT' ;;
        TabTextActive)           printf 'C_TEXT' ;;
        TabTextInactive)         printf 'C_SUBTEXT1' ;;
        # ---- [LineEdit] / [TextSelection] ------------------------------
        LineEditBackground)        printf 'C_SURFACE0' ;;
        LineEditBackgroundHover)   printf 'C_SURFACE1' ;;
        LineEditBackgroundActive)  printf 'C_SURFACE1' ;;
        LineEditForeground)        printf 'C_TEXT' ;;
        LineEditForegroundHover)   printf 'C_TEXT' ;;
        LineEditForegroundActive)  printf 'C_TEXT' ;;
        LineEditClearButton)       printf 'C_SUBTEXT1' ;;
        TextSelectionBackground)   printf 'C_ACCENT' ;;
        TextSelectionForeground)   printf 'C_ACCENT_FG' ;;
        # ---- [Slider] ----------------------------------------------------
        SliderBackground)        printf 'C_OVERLAY0' ;;
        SliderBackgroundHover)   printf 'C_OVERLAY1' ;;
        SliderBackgroundActive)  printf 'C_OVERLAY1' ;;
        SliderHandle)            printf 'C_ACCENT' ;;
        SliderHandleHover)       printf 'C_ACCENT' ;;
        SliderHandleActive)      printf 'C_ACCENT' ;;
        SliderHandleInactive)    printf 'C_ACCENT_DIM' ;;
        # ---- [Separator] -------------------------------------------------
        SeparatorBackground)   printf 'C_SURFACE1' ;;
        SeparatorForeground)   printf 'C_SURFACE1' ;;
        # ---- [Panel] -----------------------------------------------------
        PanelBackground)          printf 'C_CRUST' ;;
        PanelBackgroundHover)     printf 'C_SURFACE0' ;;
        PanelBackgroundActive)    printf 'C_SURFACE1' ;;
        PanelText)                printf 'C_TEXT' ;;
        PanelTextHover)           printf 'C_TEXT' ;;
        PanelTextActive)          printf 'C_TEXT' ;;
        PanelTextInactive)        printf 'C_SUBTEXT1' ;;
        PanelLabelText)           printf 'C_TEXT' ;;
        PanelLabelTextInactive)   printf 'C_SUBTEXT1' ;;
        PanelHighlight)           printf 'C_ACCENT' ;;
        PanelLine)                printf 'C_SURFACE1' ;;
        # ---- [Titlebar] --------------------------------------------------
        Titlebar)             printf 'C_TEXT' ;;
        TitlebarText)         printf 'C_TEXT' ;;
        TitlebarActive)       printf 'C_SURFACE0' ;;
        TitlebarInactive)     printf 'C_MANTLE' ;;
        TitlebarActiveText)   printf 'C_TEXT' ;;
        TitlebarInactiveText) printf 'C_SUBTEXT1' ;;
        # ---- [Icons] -----------------------------------------------------
        IconBackground)      printf 'C_TEXT' ;;
        IconOnSurface)       printf 'C_TEXT' ;;
        *) printf '' ;;
    esac
}

# otto_recolor_colors <src> <dst> — copy a Plasma .colors file, rewriting the
# decimal R,G,B values of every key the map above recognises.
#
# The output is a real .colors file: the source's groups and any key the map
# does not know (including the header metadata) are preserved verbatim.
# Returns 0 if at least one key was rewritten, 1 if none was (i.e. this is not
# a ColorScheme file after all), so callers can report it instead of silently
# shipping an unchanged copy.
otto_recolor_colors() {
    local src="$1" dst="$2" changed=0 key role val
    [ -f "$src" ] || return 1
    local tmp="$dst.otto.tmp"
    # Create the destination directory BEFORE opening the temp file. Writing the
    # temp first fails in a directory that does not exist yet, and the caller
    # then reports "this is not a color scheme" — a failure mode that looks
    # exactly like a genuine parse miss and sends you hunting in the wrong place.
    mkdir -p "$(dirname "$dst")" || return 1
    : > "$tmp" || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        # Only rewrite "Key=R,G,B" lines; anything else (group headers,
        # metadata, comments) passes through untouched.
        case "$line" in
            [A-Za-z]*=*)
                key="${line%%=*}"
                val="${line#*=}"
                role="$(otto_role_for_colors_key "$key")"
                if [ -n "$role" ] && [ -n "${!role-}" ]; then
                    # Strip any leading '#' and keep the file's decimal form.
                    # A few shipped schemes add a 4th field (alpha) to a value;
                    # preserve it instead of silently dropping it.
                    local rest extra=""
                    rest="$(printf '%s' "${val#\#}")"
                    extra="$(printf '%s' "$rest" | awk -F, 'NF>3 { out=""; for (i=4;i<=NF;i++) out=out (i>4 ? "," : "") $i; print out }')"
                    [ -n "$extra" ] && extra=",$extra"
                    if printf '%s' "$rest" | grep -qE '^[0-9]{1,3},[0-9]{1,3},[0-9]{1,3}'; then
                        printf '%s=%s%s\n' "$key" "$(hex2rgb "${!role}")" "$extra" >> "$tmp"
                        changed=1
                        continue
                    fi
                fi
                ;;
        esac
        printf '%s\n' "$line" >> "$tmp"
    done < "$src"

    if [ "$changed" -eq 0 ]; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$dst" || return 1
    return 0
}

# otto_role_for_kvantum_key <key> — map a Kvantum .conf colour key to a palette
# role. Same idea as the .colors map; Kvantum's vocabulary is its own.
#
# Unknown keys are deliberately NOT mapped. Kvantum's config has hundreds of
# keys and a wrong guess here shows up as a subtly wrong button gradient, not
# as an error, so coverage is limited to the keys that carry the theme's
# overall colour identity.
otto_role_for_kvantum_key() {
    case "$1" in
        general.color)          printf 'C_MANTLE' ;;
        general.base)           printf 'C_BG' ;;
        general.text)           printf 'C_TEXT' ;;
        general.text.color)     printf 'C_TEXT' ;;
        window.color)           printf 'C_BG' ;;
        window.color.active)    printf 'C_BG' ;;
        window.color.inactive)  printf 'C_MANTLE' ;;
        window.text)            printf 'C_TEXT' ;;
        window.text.active)     printf 'C_TEXT' ;;
        window.text.inactive)   printf 'C_SUBTEXT1' ;;
        window.hilight.color)   printf 'C_ACCENT' ;;
        window.hilight.text)    printf 'C_ACCENT_FG' ;;
        window.hilight.color.active)   printf 'C_ACCENT' ;;
        window.hilight.color.inactive) printf 'C_ACCENT_DIM' ;;
        window.handle.color)    printf 'C_SURFACE1' ;;
        title.area.color)       printf 'C_CRUST' ;;
        title.area.color.active)  printf 'C_CRUST' ;;
        title.area.color.inactive) printf 'C_MANTLE' ;;
        title.text)             printf 'C_TEXT' ;;
        title.text.active)      printf 'C_TEXT' ;;
        title.text.inactive)    printf 'C_SUBTEXT1' ;;
        title.close.color)      printf 'C_TEXT' ;;
        title.close.color.hover) printf 'C_ACCENT' ;;
        title.button.color)     printf 'C_SURFACE1' ;;
        title.button.color.hover) printf 'C_ACCENT' ;;
        title.button.color.active) printf 'C_ACCENT' ;;
        title.button.color.inactive) printf 'C_SURFACE0' ;;
        icon.color)             printf 'C_TEXT' ;;
        icon.color.disabled)    printf 'C_SUBTEXT1' ;;
        *) printf '' ;;
    esac
}

# otto_recolor_kvantum_conf <src> <dst> — one Kvantum .conf file, same
# rewrite rules as otto_recolor_colors but for Kvantum's "key=rgb(229,72,77)"
# value form.
otto_recolor_kvantum_conf() {
    local src="$1" dst="$2" changed=0 key role val
    [ -f "$src" ] || return 1
    local tmp="$dst.otto.tmp"
    : > "$tmp" || return 1

    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            [A-Za-z]*=*)
                key="${line%%=*}"
                val="${line#*=}"
                role="$(otto_role_for_kvantum_key "$key")"
                if [ -n "$role" ] && [ -n "${!role-}" ]; then
                    # Kvantum writes all three of these depending on which file
                    # it is: rgb(R,G,B) in KvAnt/general/*.conf, a bare R,G,B in
                    # some of the same, and #rrggbb in .kvconfig variants. Match
                    # the file's own form — rewriting rgb() as #hex (or the
                    # reverse) is a silent format change that some Kvantum
                    # versions reject by rendering the fallback colour.
                    case "$val" in
                        rgb\(*\))
                            printf '%s=rgb(%s)\n' "$key" "$(hex2rgb "${!role}")" >> "$tmp"
                            changed=1
                            continue
                            ;;
                        \#*)
                            printf '%s=#%s\n' "$key" "${!role}" >> "$tmp"
                            changed=1
                            continue
                            ;;
                        [0-9]*,[0-9]*,[0-9]*)
                            printf '%s=%s\n' "$key" "$(hex2rgb "${!role}")" >> "$tmp"
                            changed=1
                            continue
                            ;;
                    esac
                fi
                ;;
        esac
        printf '%s\n' "$line" >> "$tmp"
    done < "$src"

    if [ "$changed" -eq 0 ]; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$dst" || return 1
    return 0
}

# otto_recolor_kvantum <src_dir> <dst_dir> — copy a Kvantum theme, recolouring
# the .conf files under KvAnt/. SVGs are copied as-is (see the header): the log
# says what was and was not touched rather than pretending the theme is fully
# recoloured.
#
# The file count lands in the global OTTO_KV_FILES_RECOLORED rather than on
# stdout: this runs inside a command substitution at the call site, where a
# stray byte from a failing cp would silently become the reported count.
OTTO_KV_FILES_RECOLORED=0
otto_recolor_kvantum() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 1
    OTTO_KV_FILES_RECOLORED=0
    rm -rf "$dst" || return 1
    cp -a "$src" "$dst" >/dev/null 2>&1 || return 1

    local f
    while IFS= read -r f; do
        # Skip the translated templates: they hold the same keys with locale
        # suffixes and are regenerated by Kvantum itself.
        case "$f" in *.kvc|*/templates/*) continue ;; esac
        # Read src and dst are the same file: the helper writes a sibling temp
        # file first and only then moves it over, so this is not destructive.
        if otto_recolor_kvantum_conf "$f" "$f"; then
            OTTO_KV_FILES_RECOLORED=$((OTTO_KV_FILES_RECOLORED + 1))
        fi
    done < <(find "$dst" -type f -name '*.conf' 2>/dev/null)

    # Kvantum also caches a compiled copy of the SVG; a stale cache can shadow
    # a recoloured conf. Remove ours so it is rebuilt on next use.
    find "$dst" -type f -name '*.svgcache' -delete 2>/dev/null
    return 0
}

# otto_konsole_section_role <section-name> — map a Konsole colorscheme section
# to a palette role, printing the role name. Konsole's file is a list of
# one-value sections, so the section name IS the key:
#
#   [Background] [BackgroundFaint] [BackgroundIntense]
#   [Color0] .. [Color7]  and their [ColorNFaint] / [ColorNLight] variants
#   [Foreground] [ForegroundFaint] [ForegroundIntense]
#   [General] [GeneralFaint] [GeneralIntense]
#
# The Faint variants are the "dimmed" renders and the Light variants are the
# bright ones, i.e. exactly what C_8..C_15 are for — that mapping is why the
# ANSI palette matters here and why inventing a "closest grey" would be wrong.
otto_konsole_section_role() {
    local sec="$1"
    case "$sec" in
        Background|BackgroundFaint)   printf 'C_0' ;;
        BackgroundIntense)            printf 'C_8' ;;
        Foreground)                   printf 'C_7' ;;
        ForegroundFaint)              printf 'C_8' ;;
        ForegroundIntense)            printf 'C_15' ;;
        General)                      printf 'C_TEXT' ;;
        GeneralFaint)                 printf 'C_SUBTEXT0' ;;
        GeneralIntense)               printf 'C_SUBTEXT1' ;;
        Color[0-7])                   printf 'C_%s' "${sec#Color}" ;;
        Color[0-7]Faint)              printf 'C_8' ;;
        Color[0-7]Light)              printf 'C_%s' "$(( ${sec:5:1} + 8 ))" ;;
        *) printf '' ;;
    esac
}

# otto_recolor_konsole <home_dir> <out> — recolour Otto's own Konsole scheme
# (if the Konsole package was installed) into <out>.
#
# The DEFAULT profile stays the palette-generated one: this engine already
# wrote a Konsole scheme from the same palette, so the recoloured copy is for
# anyone who prefers Otto's own weight/contrast, not the palette's.
otto_recolor_konsole() {
    local home_dir="$1" out="$2" d f src=""
    for d in "$home_dir/.local/share/konsole" "/usr/local/share/konsole" "/usr/share/konsole"; do
        [ -d "$d" ] || continue
        for f in "$d"/*Otto*.colorscheme "$d"/*[Oo]tto*.colorscheme; do
            [ -f "$f" ] || continue
            # Skip anything we wrote ourselves (they carry our own name).
            case "$f" in *"$PALETTE_SHORT"*) continue ;; esac
            src="$f"; break
        done
        [ -n "$src" ] && break
    done
    [ -n "$src" ] || return 1

    local tmp="$out.otto.tmp" sec="" role changed=0
    # Create the directory BEFORE the temp file — `: > "$tmp"` in a directory
    # that does not exist yet fails, and the caller then reports "no Konsole
    # scheme found", which is indistinguishable from a genuine miss.
    mkdir -p "$(dirname "$out")" || return 1
    : > "$tmp" || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \[*\])
                sec="${line#[}"; sec="${sec%]}"
                role="$(otto_konsole_section_role "$sec")"
                if [ -n "$role" ] && [ -n "${!role-}" ]; then
                    # This section's value IS the whole body: write the section
                    # header plus the recoloured decimal, then clear `role` so
                    # any FURTHER lines in this section (Konsole's [General]
                    # carries Name=, Opacity=, ...) are copied through instead
                    # of being swallowed as if they were the value.
                    printf '[%s]\n' "$sec" >> "$tmp"
                    printf '%s\n' "$(hex2rgb "${!role}")" >> "$tmp"
                    if [ "$sec" = "General" ]; then
                        # Konsole shows this name in the profile editor, so the
                        # recoloured copy must not claim to be stock Otto.
                        printf 'Name=%s\n' "${PALETTE_SHORT}-Otto" >> "$tmp"
                    fi
                    role=""
                    changed=1
                    continue
                fi
                ;;
            *)
                # Lines inside a recognised section have already been replaced
                # by the header case above; everything else passes through.
                ;;
        esac
        printf '%s\n' "$line" >> "$tmp"
    done < "$src"

    if [ "$changed" -eq 0 ]; then
        rm -f "$tmp"
        return 1
    fi
    mv "$tmp" "$out" || return 1
    return 0
}

# ---------------------------------------------------------------------------
# The Global Theme
# ---------------------------------------------------------------------------

# _otto_read_json_string <file> <key> — the LAST string value declared for <key>
# in a metadata.json, or empty.
#
# LAST, not first, and not "first match wins": a Plasma theme's KPlugin block
# contains both an Authors array whose entries each have a "Name", and its own
# "Name". Greedily taking the first one renames the AUTHOR and leaves the
# theme's display name alone — which is both wrong and, since it edits a credit
# line, the kind of wrong nobody notices.
_otto_read_json_string() {
    local file="$1" key="$2"
    awk -v key="\"$key\"" '
        index($0, key) && $0 ~ key"[ \t]*:" {
            if (match($0, key"[ \t]*:[ \t]*\"[^\"]*\"")) {
                s = substr($0, RSTART, RLENGTH)
                sub(key"[ \t]*:[ \t]*\"", "", s)
                sub("\"$", "", s)
                val = s
            }
        }
        END { if (val != "") printf "%s", val }
    ' "$file"
}

# _otto_rewrite_last_json_string <file> <key> <new-value> — replace the string
# value of the LAST occurrence of <key>, rewriting the file in place.
#
# Rewriting in one awk pass rather than a chain of sed -e calls is what makes
# "the last occurrence" expressible at all: sed applies every expression to
# every line, so the moment Authors and KPlugin both carry a "Name" there is no
# way to say which one you meant.
_otto_rewrite_last_json_string() {
    local file="$1" key="$2" newval="$3"
    [ -f "$file" ] || return 1
    awk -v key="\"$key\"" -v newval="$newval" '
        { lines[NR] = $0
          if (index($0, key) && $0 ~ key"[ \t]*:") last = NR }
        END {
            if (last == 0) exit 1
            # sub() as a STATEMENT. Assigning it (`lines[last] = sub(...)`)
            # would store the number of substitutions and replace the line with
            # the integer 1 — turning one JSON object into something Plasma
            # cannot parse at all.
            sub(key"[ \t]*:[ \t]*\"[^\"]*\"", key ": \"" newval "\"", lines[last])
            for (i = 1; i <= NR; i++) print lines[i]
        }
    ' "$file" > "$file.otto.tmp" || { rm -f "$file.otto.tmp"; return 1; }
    mv "$file.otto.tmp" "$file" || return 1
    return 0
}

# otto_lnf_metadata <src_lnf> <dst_lnf> — rewrite the copy's metadata.json in
# place.
#
# The source file is copied verbatim FIRST and then only the three fields that
# must differ are edited: Id (the package id has to be unique, and ours is
# palette-derived so two palettes can hold two Otto copies), Name (so the entry
# in System Settings is distinguishable) and Version.
#
# Everything else — Authors, License, Category, Description, Website — is left
# exactly as Otto declared it. Parsing and re-emitting a JSON blob in bash
# means an array whose shape differs from the guess loses entries, and dropping
# the original author or licence from a recolour of someone else's theme is a
# worse outcome than a slightly verbose description.
otto_lnf_metadata() {
    local src="$1" dst="$2"
    local meta="$dst/metadata.json"
    [ -f "$src/metadata.json" ] || return 1

    cp -f "$src/metadata.json" "$meta" || return 1

    _otto_rewrite_last_json_string "$meta" Id "$OTTO_LNF_ID" \
        || log_warn "Otto metadata.json declares no Id — the copy may not load in Plasma."

    local old_name
    old_name="$(_otto_read_json_string "$src/metadata.json" Name)"
    [ -n "$old_name" ] || old_name="Otto"
    _otto_rewrite_last_json_string "$meta" Name "$old_name ($PALETTE_NAME)"

    _otto_rewrite_last_json_string "$meta" Version "$THEME_VERSION" || true
    return 0
}

# otto_lnf_defaults_decoration <home_dir> — the [kwinrc][org.kde.kdecoration2]
# block for our Global Theme's contents/defaults.
#
# The palette engine defaults to Breeze, which ships with Plasma and always
# matches. When Otto's decoration IS installed we use it instead — otherwise
# the window borders would be the one part of the desktop still wearing the
# previous theme's colours, which is the most visible possible half-apply.
#
# library vs theme: KWin's kdecoration2 wants the plugin's LIBRARY name in
# `library` and the decoration's own id in `theme`. For Otto that is
# `library=org.kde.kwin.otto` / `theme=Otto` (or whatever the installed
# metadata.json declares) — so read it rather than guessing.
otto_lnf_defaults_decoration() {
    local home_dir="$1"
    local decor theme_id="Otto" lib="org.kde.kwin.otto"
    decor="$(otto_find_decor "$home_dir")" || decor=""
    if [ -n "$decor" ] && [ -f "$decor/metadata.json" ]; then
        local t
        t="$(sed -n 's/.*"Id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$decor/metadata.json" | head -1)"
        [ -n "$t" ] && theme_id="$t"
        local l
        l="$(sed -n 's/.*"KPackageStructure"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$decor/metadata.json" | head -1)"
        [ -n "$l" ] && lib="$l"
    fi
    if [ -n "$decor" ]; then
        printf '\n[kwinrc][org.kde.kdecoration2]\n'
        printf 'library=%s\n' "$lib"
        printf 'theme=%s\n' "$theme_id"
        printf 'BorderSize=2\n'
        printf 'BorderSizeAuto=false\n'
        return 0
    fi
    # No Otto decoration installed: Breeze, exactly like the engine's default.
    printf '\n[kwinrc][org.kde.kdecoration2]\n'
    printf 'library=org.kde.breeze\n'
    printf 'theme=Breeze\n'
    printf 'BorderSize=None\n'
    printf 'BorderSizeAuto=false\n'
    return 1
}

# otto_make_lnf <home_dir> — build our recoloured Otto Global Theme and apply
# it. Returns 0 when the theme was built and applied, 1 when Otto is not
# installed (a normal state — the caller then leaves the palette's own Global
# Theme in place).
otto_make_lnf() {
    local home_dir="$1"
    local src
    src="$(otto_find_lnf "$home_dir")" || return 1
    [ -n "$src" ] || return 1

    local root="$home_dir/.local/share/plasma/look-and-feel"
    local dst="$root/$OTTO_LNF_ID"
    run_as_user rm -rf "$dst" || return 1
    run_as_user mkdir -p "$dst/contents" || return 1
    # Provenance, before anything else is written: otto_find_lnf must be able to
    # tell this directory from an installed Otto on every later run.
    run_as_user touch "$dst/$OTTO_GENERATED_MARKER" || true

    # Copy contents, then remove the two subtrees that would hijack the desktop
    # layout. THIS IS THE POINT OF THE WHOLE FILE:
    #
    #   contents/layouts/  default panel + desktop layouts. Applying a Global
    #                      Theme that ships these REPLACES the panel — so the
    #                      floating app bar and the auto-hiding tray bar built
    #                      by 47-plasmaPanel.sh would silently disappear, along
    #                      with every pinned app and the user's panel prefs.
    #   contents/widgets/  applet defaults for the widgets it ships.
    #
    # A theme without those directories is still a valid Plasma 6 LookAndFeel
    # (Plasma applies what contents/defaults and contents/colors say and leaves
    # the layout alone) — which is exactly what we want: Otto's colours and
    # assets, the user's own panel.
    if [ -d "$src/contents" ]; then
        run_as_user cp -a "$src/contents/." "$dst/contents/" 2>/dev/null || true
    fi
    run_as_user rm -rf "$dst/contents/layouts" "$dst/contents/widgets"
    run_as_user cp -a "$src/metadata.json" "$dst/metadata.json" 2>/dev/null || true

    otto_lnf_metadata "$src" "$dst"

    # contents/colors: a REAL COPY of the palette's generated scheme, matching what
    # apply_global_theme does and for the same reason — Plasma 6 kpackages do
    # not support a symlink here, and the engine has that written down at
    # theme.sh's "contents/colors  A REAL copy of the .colors file. NOT a
    # symlink." Every shipped theme symlinks it; that is not one of them.
    #
    # The copy can only lag the source if the .colors is regenerated without
    # this theme being rebuilt, and both are written by the same
    # apply_palette run, so the drift this trades away does not arise.
    local colors_file="$home_dir/.local/share/color-schemes/$PALETTE_SHORT.colors"
    if [ -f "$colors_file" ]; then
        run_as_user rm -f "$dst/contents/colors"
        run_as_user cp -f "$colors_file" "$dst/contents/colors"
    fi

    # contents/defaults: keep Otto's own if it has one (it may set widget or
    # splash settings worth keeping), but replace the decoration block so the
    # window decoration follows the palette.
    #
    # The old block is removed with awk rather than a sed range. A sed range
    # like `/start/,/^\[/d` also DELETES its end line, and the end line here is
    # the NEXT section's header — so the naive form silently merges the two
    # sections that followed the decoration block and the file no longer means
    # what it says. awk re-prints the terminating header and only drops the body.
    local defaults_file="$dst/contents/defaults"
    if [ -f "$src/contents/defaults" ]; then
        cp -f "$src/contents/defaults" "$defaults_file"
    else
        : > "$defaults_file"
    fi
    awk '
        /^\[kwinrc\]\[org\.kde\.kdecoration2\]/ { skip = 1; next }
        skip && /^\[/ { skip = 0 }
        skip { next }
        { print }
    ' "$defaults_file" > "$defaults_file.otto.tmp" && mv "$defaults_file.otto.tmp" "$defaults_file"
    printf '\n' >> "$defaults_file"
    otto_lnf_defaults_decoration "$home_dir" >> "$defaults_file"

    # Apply it.
    if command_exists plasma-apply-lookandfeel; then
        if run_as_user plasma-apply-lookandfeel --apply "$OTTO_LNF_ID" >/dev/null 2>&1; then
            log_ok "Otto Global Theme applied: $OTTO_LNF_ID (recoloured, layouts/widgets stripped)"
        else
            log_warn "plasma-apply-lookandfeel did not apply $OTTO_LNF_ID — next login picks it up."
        fi
    fi
    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file lookandfeeltoolrc --group "Global Theme" --key "LookAndFeelPackage" "$OTTO_LNF_ID"
    fi
    if ini_set_key "$home_dir/.config/plasmarc" "Theme" "LookAndFeelPackage" "$OTTO_LNF_ID"; then
        log_ok "Otto Global Theme registered: $OTTO_LNF_ID (plasmarc)"
    else
        log_err "Could not register $OTTO_LNF_ID in plasmarc — set it in System Settings > Appearance."
    fi
    return 0
}

# otto_apply_kvantum <home_dir> — recolour Otto's Kvantum theme and make it the
# one Kvantum uses. Prints what happened; absence is fine.
otto_apply_kvantum() {
    local home_dir="$1" src
    src="$(otto_find_kvantum "$home_dir")" || return 1
    [ -n "$src" ] || return 1
    local base_name
    base_name="$(basename "$src")"
    local dst
    dst="$(dirname "$src")/${base_name}-${PALETTE_SHORT}"

    local n
    n="$(otto_recolor_kvantum "$src" "$dst")" || return 1
    # The recoloured copy lives in the same Kvantum directory and is named after
    # Otto, so without a marker the NEXT run finds this one as its source and
    # derives yet another name from it.
    run_as_user touch "$dst/$OTTO_GENERATED_MARKER" || true
    log_ok "Kvantum theme recoloured: $dst ($n config files rewritten, SVGs left as Otto shipped them)."

    # Make it the active Kvantum theme. Kvantum reads Kvantum.conf (user) or
    # kvantumconfig (system); the user file wins when both exist, and writing it
    # is what applies the theme without a logout for most apps (a running app
    # still needs its own restart to re-query).
    local kvdir="$home_dir/.config/Kvantum"
    run_as_user mkdir -p "$kvdir"
    if [ -f "$kvdir/Kvantum.conf" ]; then
        if ! grep -qE "^theme=" "$kvdir/Kvantum.conf"; then
            printf '\ntheme=%s\n' "$(basename "$dst")" >> "$kvdir/Kvantum.conf"
        else
            run_as_user sed -i "s|^theme=.*|theme=$(basename "$dst")|" "$kvdir/Kvantum.conf"
        fi
        log_ok "Kvantum theme set: $(basename "$dst") (~/.config/Kvantum/Kvantum.conf)"
    else
        log_info "Kvantum.conf not present — theme written to $dst but not activated."
        log_info "  activate with: kvantummanager --set $(basename "$dst")"
    fi
    return 0
}

# otto_apply_wallpaper <home_dir> <lnf_dir> — use Otto's own wallpaper when it
# ships one (it is artwork, not a palette value, so recolouring it would be
# vandalism), otherwise generate a palette gradient with ImageMagick.
otto_apply_wallpaper() {
    local home_dir="$1" lnf_dir="${2:-}"
    local img
    if [ -n "$lnf_dir" ] && img="$(otto_find_wallpapers "$lnf_dir" "$home_dir")" && [ -n "$img" ]; then
        apply_wallpaper_image "$home_dir" "$img" && {
            log_ok "Otto's own wallpaper kept: $(basename "$img")"
            return 0
        }
    fi
    # No Otto wallpaper: a palette-tinted gradient, generated locally.
    if ! command_exists convert && ! command_exists magick; then
        log_info "No ImageMagick and no Otto wallpaper — wallpaper left alone."
        return 1
    fi
    local conv
    conv="$(command_exists convert && command -v convert || command -v magick)"
    local dir="$home_dir/.local/share/backgrounds"
    run_as_user mkdir -p "$dir"
    local out="$dir/${PALETTE_SHORT}-gradient.png"
    # No -function polynomial here, and that is a correction rather than an
    # omission. "6,-5,1" is ImageMagick's contrast curve: it maps 0 to 1 and 1
    # to 2, so on a DARK palette it does not add contrast, it inverts the range
    # into the highlights. Measured on this palette: mean brightness 5.5%
    # without it, 74% with it — a light grey wallpaper hung behind a black theme,
    # which then looked like the theme had failed. Script 14 builds its gradient
    # the plain way and the live wallpaper from it measures 7%, which is why its
    # output is what this copies.
    #
    # The '#' is required: ImageMagick parses a bare "0e0e11" as a colour NAME,
    # not as hex, and fails with "unrecognized color `0e0e11'" — so the
    # wallpaper is quietly never generated. (Verified against both binaries:
    # the legacy `convert` parses '#' inside gradient: fine; only a *leading* '#'
    # on a whole argument is treated as a comment.)
    if run_as_user "$conv" -size 1920x1080 "gradient:#${C_BG}-#${C_MANTLE}" \
        "$out" >/dev/null 2>&1 \
        && [ -s "$out" ]; then

        apply_wallpaper_image "$home_dir" "$out" && {
            log_ok "Wallpaper generated from the palette: $(basename "$out")"
            return 0
        }
    fi
    log_warn "Wallpaper generation failed — wallpaper left alone (cosmetic only)."
    return 1
}

# otto_apply_theme <home_dir> — the orchestrator. Called by the theme engine
# for the Otto palette; safe to call for any palette (it does nothing when the
# palette is not Otto-derived).
#
# Everything here is best-effort and separately reported. A palette apply that
# succeeds with every Otto component missing is a completely working desktop,
# so nothing in this function may fail the apply.
otto_apply_theme() {
    local home_dir="$1"
    [ -n "$home_dir" ] || return 1

    local found=0

    # 1. Kvantum.
    if ! otto_apply_kvantum "$home_dir"; then
        log_info "Otto's Kvantum theme not installed — Kvantum left alone."
        log_info "  install it with Discover: 'Otto' (Kvantum theme)."
    else
        found=1
    fi

    # 2. Otto's own color schemes, recoloured alongside the generated one (same
    #    reasoning as Konsole below: the generated one stays the default).
    local schemes_dir="$home_dir/.local/share/color-schemes"
    run_as_user mkdir -p "$schemes_dir"
    local cs
    for cs in "$home_dir/.local/share/color-schemes"/*Otto*.colors \
              "/usr/local/share/color-schemes"/*Otto*.colors \
              "/usr/share/color-schemes"/*Otto*.colors; do
        [ -f "$cs" ] || continue
        case "$cs" in *"$PALETTE_SHORT"*) continue ;; esac
        if otto_recolor_colors "$cs" "$schemes_dir/${PALETTE_SHORT}-Otto.colors"; then
            log_ok "Otto color scheme recoloured: ${PALETTE_SHORT}-Otto.colors (default stays ${PALETTE_SHORT})"
            found=1
        fi
        break
    done

    # 3. Konsole: recolour Otto's scheme alongside the generated default.
    local konsole_dir="$home_dir/.local/share/konsole"
    run_as_user mkdir -p "$konsole_dir"
    if otto_recolor_konsole "$home_dir" "$konsole_dir/${PALETTE_SHORT}-Otto.colorscheme"; then
        log_ok "Otto's Konsole scheme recoloured: ${PALETTE_SHORT}-Otto.colorscheme (default stays ${PALETTE_SHORT})"
        found=1
    fi

    # 4. Global Theme (also applies the wallpaper, since the LNF carries it).
    local lnf_src
    if lnf_src="$(otto_find_lnf "$home_dir")" && [ -n "$lnf_src" ]; then
        found=1
        if ! otto_make_lnf "$home_dir"; then
            log_warn "Otto Global Theme copy failed — the palette's own theme stays active."
        fi
        otto_apply_wallpaper "$home_dir" "$lnf_src" || true
    else
        log_info "Otto's Global Theme not installed — the palette's own theme stays active."
        log_info "  install it with Discover: 'Otto' (Plasma theme)."
        # No Otto to draw a wallpaper from, but the palette still deserves one.
        otto_apply_wallpaper "$home_dir" "" || true
    fi

    if [ "$found" -eq 0 ]; then
        log_info "No Otto components found — $PALETTE_NAME is complete on its own (Konsole scheme, color scheme, Global Theme, cursor)."
        log_info "  For the full look, install the Otto packages from Discover, then re-apply this palette."
    fi
    return 0
}
