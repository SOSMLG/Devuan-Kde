#!/usr/bin/env bash
# =======================================================
# moe.sh — Moe v2.6 install + sanitising (sourced by theme.sh)
# -------------------------------------------------------
# The Moe theme (jomada; kde-look ids 1284573/1284575/...) ships as SEVEN
# separate packages: this Global Theme, a color scheme, a Plasma theme, an
# Aurorae decoration, two wallpapers, a Colloid icon theme and WhiteSur
# cursors. This toolkit installs ONE of them — Moe.tar.gz, the Global Theme —
# and sanitises it. Two reasons, in order of importance:
#
#   1. Its contents/defaults references SIX components that are not in this
#      archive and not installed here:
#
#        cursorTheme=WhiteSur-cursors            -> absent
#        ColorScheme=Moe                          -> absent (no colors in the tarball)
#        Theme=Colloid                            -> absent
#        library=org.kde.kwin.aurorae
#        theme=__aurorae__svg__Moe               -> absent
#        Image=Moe-DarkSouls                      -> absent
#
#      A Global Theme is applied by WRITING those keys into the user's config.
#      An absent color scheme is the loud failure (Plasma falls back and the
#      desktop half-repaints); absent icons, cursor, Aurorae SVG and wallpaper
#      are the quiet ones — each one silently resets to whatever the previous
#      theme used, so the desktop ends up claiming Moe while wearing Breeze and
#      the old cursor. Shipping them unsanitised would trade a visible error for
#      an invisible inconsistency.
#
#   2. contents/layouts/org.kde.plasma.desktop-layout.js would REPLACE THE
#      PANEL. Applying a Global Theme that ships a layout overwrites the user's
#      containments, so the floating app bar and the auto-hiding tray bar built
#      by 47-plasmaPanel.sh — and every pinned app — would be gone. It is
#      stripped, like in apply_global_theme() and otto.sh.
#
# WHERE THE PROVENANCE COMES FROM
#
#   store.kde.org/p/1717596 is behind an Anubis gate and its file URLs are
#   assembled in JavaScript, so there is no URL a script can fetch. This file
#   pins a community mirror (LoboViejo79/KDE-Moe-Theme-Installer) at a fixed
#   commit and verifies the archive's SHA256 before extracting anything. The
#   SHA256 is load-bearing rather than decorative: it is what makes "we fetched
#   Moe" checkable, and it is checked on every run including the cached ones.
#
#   If the download fails the palette still applies. The palette engine has
#   already produced a coherent Konsole scheme, .colors file and its own Global
#   Theme; what this file adds is the Moe identity and the sanitised defaults,
#   which is a nicer desktop, not a working one.
#
# Dependency: lib/common.sh (log_*, run_as_user, sha256_verify) and lib/theme.sh.
# =======================================================

# Guard against being sourced twice in the same shell.
[ -n "${_DEVUAN_KDE_MOE_SH_LOADED:-}" ] && return 0
_DEVUAN_KDE_MOE_SH_LOADED=1

# Upstream Moe v2.6, from the manifest in the pinned archive.
MOE_VERSION="${MOE_VERSION:-2.6}"

# The id our package is registered under: MoeDarkTheme, NOT "Moe". The upstream
# id stays "Moe" so that if a user does install the real package through
# Discover, the two are distinguishable in --list and one cannot silently
# replace the other.
MOE_LNF_ID="${MOE_LNF_ID:-${PALETTE_SHORT:-MoeDark}Theme}"

MOE_UPSTREAM_REPO="LoboViejo79/KDE-Moe-Theme-Installer"
MOE_UPSTREAM_COMMIT="bdc1ce3c26b34a424a7a363ff2c47885631ed19d"
MOE_UPSTREAM_BASE="https://raw.githubusercontent.com/$MOE_UPSTREAM_REPO/$MOE_UPSTREAM_COMMIT/theme_files"

# asset <name> <sha256> — the pinned archive table. Kept as one lookup so a
# version bump is a two-line edit, and so the test tier can assert every entry
# here has a matching URL pin without parsing the download function.
MOE_ARCHIVE_SHA_LNF="f6a7599afda446ac32c4cc2d2f71d696264b301f7455879f9bf0c7163793ffc1"
MOE_ARCHIVE_SHA_COLORS="8d5de79856c860757d35430c1afc592a1e2101c284f39526f0e2a9c4f23c093a"
MOE_ARCHIVE_SHA_KVANTUM="6c7bcf351e3cfc3e30c8b667a70b42c266118bd224957f3a848d622d2113535c"
MOE_ARCHIVE_SHA_KONSOLE="4531bcc454022180280df4b45988ff2cb7255101c1c3af48bd2070addf95a1d5"

# moe_cache_dir — where pinned archives and the extracted package live.
#
# Resolved at call time, never at source time, for the same reason
# theme_state_dir() is: the test tiers export XDG_CACHE_HOME after sourcing
# lib/common.sh, and a source-time constant would point the tier at the real
# ~/.cache instead of its sandbox.
moe_cache_dir() {
    printf '%s/devuan-kde-setup/moe' "${XDG_CACHE_HOME:-$HOME/.cache}"
}

# moe_fetch <archive> <sha256> — fetch one pinned archive, verifying it first.
# On success sets MOE_FETCHED to the archive path and returns 0; returns 1 and
# leaves MOE_FETCHED unset on failure.
#
# IT RETURNS THE PATH IN A VARIABLE, NOT ON STDOUT. The obvious `out="$(moe_fetch
# ...)"` is wrong here: log_*/sha256_verify print to STDOUT (common.sh:23), so
# the captured value would be the log text with the path buried in it, and the
# caller would then hand that string to tar. The visible symptom is not an
# error — the download succeeds, verification succeeds, and the theme silently
# never gets installed. otto.sh gets away with `src="$(otto_find_lnf ...)"` only
# because those helpers deliberately do not log.
MOE_FETCHED=""
moe_fetch() {
    local archive="$1" want="$2"
    local out="$(moe_cache_dir)/$archive"
    MOE_FETCHED=""
    [ -n "$want" ] || { log_err "moe_fetch: no SHA256 pinned for $archive"; return 1; }
    mkdir -p "$(moe_cache_dir)" || return 1

    if [ -f "$out" ] && sha256_verify "$out" "$want" >/dev/null; then
        MOE_FETCHED="$out"
        return 0
    fi

    local url="$MOE_UPSTREAM_BASE/$archive"
    log_info "Fetching pinned $archive (sha256 ${want:0:12}...)"
    if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$out.part" "$url"; then
        rm -f "$out.part"
        log_warn "Could not download $archive from $MOE_UPSTREAM_REPO@$MOE_UPSTREAM_COMMIT"
        return 1
    fi
    if ! sha256_verify "$out.part" "$want" >/dev/null; then
        # Delete the bad bytes rather than leaving them for the next run to
        # "verify" against a pin it will also fail, which would turn a one-line
        # warning into a permanent error.
        rm -f "$out.part"
        log_warn "$archive failed SHA256 verification — discarded (the mirror may have changed)."
        return 1
    fi
    mv -f "$out.part" "$out" || return 1
    MOE_FETCHED="$out"
    return 0
}

# moe_extract <archive> <expected-top-dir> <dest-dir> — extract <dest>/<dir> and
# set MOE_EXTRACTED to it. Returns 0 when the package is usable, including when
# it was already extracted, so callers need no "was it cached?" branch.
#
# The expected top-level directory is a parameter rather than something inferred
# from the tarball: an archive that extracts to a different shape is a mirror
# that changed, and guessing at its layout is how a theme install ends up
# copying whatever is at the root.
MOE_EXTRACTED=""
moe_extract() {
    local archive="$1" top="$2" dest="$3"
    MOE_EXTRACTED=""
    local out="$dest/$top"
    [ -f "$archive" ] || return 1
    if [ -f "$out/.devmkde-moe-extracted" ]; then
        MOE_EXTRACTED="$out"
        return 0
    fi
    rm -rf "$dest.tmp" && mkdir -p "$dest.tmp" || return 1
    if ! tar -xzf "$archive" -C "$dest.tmp" 2>/dev/null; then
        rm -rf "$dest.tmp"
        log_warn "Could not extract $(basename "$archive")"
        return 1
    fi
    if [ ! -d "$dest.tmp/$top" ]; then
        rm -rf "$dest.tmp"
        log_warn "$(basename "$archive") does not contain $top/ — refusing to guess at its layout."
        return 1
    fi
    rm -rf "$out"
    # mkdir -p "$dest": `mv A/Moe A_parent/Moe` fails when the DESTINATION's
    # parent does not exist, and mv does not create it. Only $dest.tmp was
    # created above, so this is the line that is missing when the error is
    # "mv: cannot move ... No such file or directory" — which reads like the
    # source is missing, and it is not.
    mkdir -p "$dest" || { rm -rf "$dest.tmp"; return 1; }
    mv "$dest.tmp/$top" "$out" || { rm -rf "$dest.tmp"; return 1; }
    touch "$out/.devmkde-moe-extracted"
    rmdir "$dest.tmp" 2>/dev/null || true
    MOE_EXTRACTED="$out"
    return 0
}

# ---------------------------------------------------------------------------
# Palette verification
# ---------------------------------------------------------------------------

# moe_verify_palette <colors-file> <home_dir>
#
# Proves the palette is upstream's Moe Dark and not merely "a dark palette".
# The palette carries 34 colours that were transcribed by hand from
# MoeDark.colors and MoeDark.colorscheme; a transcription error is invisible by
# construction — every value is valid hex, so nothing complains, the desktop is
# just subtly wrong. This compares the *rendered* scheme against the upstream
# .colors, fetched from the same pinned commit, on the handful of values that
# define the theme's identity.
#
# Skipped (not failed) when the upstream file cannot be fetched: this is a
# cross-check on a third-party mirror, not a prerequisite for a working
# desktop.
moe_verify_palette() {
    local colors_file="$1" home_dir="${2:-$HOME}"
    [ -f "$colors_file" ] || { log_warn "No generated color scheme at $colors_file"; return 1; }

    local cache; cache="$(moe_cache_dir)"
    moe_fetch "MoeDark.colors.tar.gz" "$MOE_ARCHIVE_SHA_COLORS" || {
        log_warn "Upstream MoeDark.colors unavailable — palette cross-check skipped."
        return 0
    }
    local up="$MOE_FETCHED" udir="$cache/colors"
    rm -rf "$udir.tmp"; mkdir -p "$udir.tmp" || return 0
    tar -xzf "$up" -C "$udir.tmp" 2>/dev/null || { rm -rf "$udir.tmp"; return 0; }
    local ref
    ref="$(find "$udir.tmp" -name '*.colors' -type f | head -1)"
    [ -n "$ref" ] || { rm -rf "$udir.tmp"; return 0; }

    # key = "section|key" in our file, "section|key" upstream. Only the four
    # that define the theme: window background, view background, text, accent.
    local pairs=(
        "Colors:Window|BackgroundNormal|C_BG"
        "Colors:View|BackgroundNormal|C_BG"
        "Colors:View|ForegroundNormal|C_TEXT"
        "Colors:Selection|BackgroundNormal|C_ACCENT"
    )
    local mismatches=() p ours theirs
    for p in "${pairs[@]}"; do
        IFS='|' read -r sect key var <<<"$p"
        ours="$(sed -n "/^\[$sect\]$/,/^\[/p" "$colors_file" | grep -m1 "^$key=" | cut -d= -f2-)"
        theirs="$(sed -n "/^\[$sect\]$/,/^\[/p" "$ref" | grep -m1 "^$key=" | cut -d= -f2-)"
        [ -n "$theirs" ] || continue
        if [ "$ours" != "$theirs" ]; then
            mismatches+=("$var: ours=$ours upstream=$theirs")
        fi
    done
    rm -rf "$udir.tmp"

    if [ "${#mismatches[@]}" -gt 0 ]; then
        log_warn "Palette does not match upstream MoeDark.colors:"
        for m in "${mismatches[@]}"; do log_warn "  $m"; done
        return 1
    fi
    log_ok "Palette matches upstream MoeDark.colors (bg/text/accent verified)."
    return 0
}

# ---------------------------------------------------------------------------
# Sanitising upstream's defaults
# ---------------------------------------------------------------------------

# moe_sanitize_defaults <engine-defaults> <upstream-defaults> <out>
#
# ADDITIVE, not a rewrite. contents/defaults is not decoration: Plasma writes
# those keys into the user's config when the theme is applied, and that is the
# only mechanism by which a Global Theme sets a color scheme. Rebuilding the
# file from upstream's safe keys alone therefore dropped [kdeglobals][General]
# ColorScheme and AccentColor, so applying MoeDarkTheme would have left the
# palette unpainted — the theme would look applied while wearing the previous
# colors. So the engine's generated file stays the base and the two safe
# upstream sections are appended.
#
# KEPT from upstream:
#   [kwinrc][DesktopSwitcher]/[WindowSwitcher] LayoutName=org.kde.breeze.desktop
#       org.kde.breeze.desktop ships with Plasma, so it resolves everywhere.
#       This is the KWin task-switcher layout, not a desktop layout: it cannot
#       touch the panel.
#
# DROPPED, each because applying it would name a component that is not here:
#   cursorTheme=WhiteSur-cursors      kcminputrc points at a directory that does
#                                     not exist -> no cursor, not a fallback.
#   ColorScheme=Moe                    absent from the tarball; would repaint the
#                                     desktop with whatever theme came before.
#   widgetStyle=kvantum                Kvantum is opt-in here; naming it while
#                                     its theme is not installed leaves widgets
#                                     unstyled.
#   Theme=Colloid                      icons are not shipped; resets to Breeze.
#   kdecoration2 aurorae/Moe           the SVG is not shipped; Plasma logs a
#                                     missing-theme error on every login.
#   [Wallpaper] Image=Moe-DarkSouls    absent; leaves the previous wallpaper.
#   [plasmarc][Theme] name=Moe         meaningless without the rest.
#   contents/layouts/                  stripped by the caller: it would replace
#                                     the user's panel.
moe_sanitize_defaults() {
    local engine="$1" upstream="$2" out="$3"
    cp -f "$engine" "$out" || return 1
    {
        printf '\n'
        printf '# Added by scripts/lib/moe.sh from upstream Moe %s contents/defaults.\n' "$MOE_VERSION"
        printf '# Upstream also asks for six components this package does not ship:\n'
        printf '# a third-party icon theme, a cursor theme, an Aurorae SVG theme, and its\n'
        printf '# own plasma, color-scheme and wallpaper packages. Applying a Global\n'
        printf '# Theme WRITES these keys into the user config, so each absent name would\n'
        printf '# reset that part of the desktop to the previous theme rather than fail.\n'
        printf '# Only the two task-switcher layouts below are kept; both ship with\n'
        printf '# Plasma. Per-key reasoning: scripts/lib/moe.sh.\n'
        printf '#\n'
        printf '# NOTE: this comment deliberately spells out none of those names. A grep for\n'
        printf '# any of them over an installed theme has to come back empty -- that is how\n'
        printf '# the test tier proves none survived.\n'
        sed -n '/^\[kwinrc\]\[DesktopSwitcher\]$/,/^$/p' "$upstream" 2>/dev/null
        sed -n '/^\[kwinrc\]\[WindowSwitcher\]$/,/^$/p' "$upstream" 2>/dev/null
    } >> "$out"

    # The guard, because the failure above is silent and looks fine: a theme
    # missing ColorScheme still applies, and Plasma simply keeps the previous
    # scheme. Assert the one key that makes the theme do anything.
    if ! grep -q "^ColorScheme=" "$out"; then
        log_err "sanitized Moe defaults lost ColorScheme — refusing to install a theme that cannot set its own colors."
        return 1
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Identity
# ---------------------------------------------------------------------------

# moe_write_metadata <out> <lnf-id> — upstream's manifest with the id this
# toolkit registers and the components it does not use removed.
#
# The X-KPackage-Dependencies list is dropped: it is seven kde-look ids for
# packages this toolkit does not install, and leaving it in claims dependencies
# that are absent. The preview images are dropped for the same reason applied to
# the colour scheme: they are upstream artwork, so they are never vendored into
# the repo, only fetched at apply time into the user's own look-and-feel dir.
moe_write_metadata() {
    local out="$1" lnf_id="$2"
    cat > "$out" <<EOF
{
    "KPackageStructure": "Plasma/LookAndFeel",
    "KPlugin": {
        "Authors": [
            {
                "Email": "gicalucejo@gmail.com",
                "Name": "jomada"
            }
        ],
        "Category": "Global Themes (Plasma 6)",
        "ServiceTypes": [
            "Plasma/LookAndFeel"
        ],
        "EnabledByDefault": true,
        "Name": "Moe Dark",
        "Description": "Moe Desktop Design (v$MOE_VERSION) — sanitised: colors, Konsole and cursor from this toolkit's palette; panel untouched.",
        "Id": "$lnf_id",
        "Version": "$MOE_VERSION",
        "License": "GPL-3.0-or-later",
        "Website": "https://seduccionlinux.wordpress.com",
        "X-Plasma-APIVersion": "2"
    }
}
EOF
}

# ---------------------------------------------------------------------------
# Kvantum (opt-in)
# ---------------------------------------------------------------------------

# moe_apply_kvantum <home_dir> — install MoeDark's Kvantum theme unmodified.
#
# Opt-in because the pinned archive is small enough to be incomplete: it holds a
# single MoeDark.svg and MoeDark.kvconfig and nothing else, and a Kvantum theme
# that renders most of its detail from a missing file looks broken in a way that
# is hard to trace back here. The SVG is also left alone rather than recoloured
# for the same reason otto.sh never recolours Otto's SVGs — a blanket
# substitution either misses the accent or recolours something structural.
#
# Enabled with DEVMKDE_MOE_KVANTUM=1.
moe_apply_kvantum() {
    local home_dir="$1"
    [ "${DEVMKDE_MOE_KVANTUM:-0}" = "1" ] || {
        log_info "Moe Kvantum theme available but not installed (opt-in: DEVMKDE_MOE_KVANTUM=1)."
        return 0
    }
    local cache; cache="$(moe_cache_dir)"
    moe_fetch "MoeDark-kvantum.tar.gz" "$MOE_ARCHIVE_SHA_KVANTUM" || return 0
    moe_extract "$MOE_FETCHED" "MoeDark" "$cache/kvantum-src" || return 0
    local src="$MOE_EXTRACTED"

    local dst="$home_dir/.config/Kvantum/MoeDark"
    run_as_user mkdir -p "$dst" || return 1
    run_as_user cp -a "$src/." "$dst/" 2>/dev/null || true
    if [ -d "$home_dir/.config/Kvantum" ]; then
        printf '[General]\ntheme=MoeDark\n' > "$home_dir/.config/Kvantum/kvantum.conf.tmp"
        run_as_user mv -f "$home_dir/.config/Kvantum/kvantum.conf.tmp" \
                          "$home_dir/.config/Kvantum/kvantum.conf" 2>/dev/null || true
        log_ok "Kvantum theme set to MoeDark ($dst)."
    else
        log_warn "Kvantum is not installed ($home_dir/.config/Kvantum missing) — MoeDark.svg left in $dst but not activated."
    fi
    return 0
}

# ---------------------------------------------------------------------------
# Orchestration
# ---------------------------------------------------------------------------

# moe_apply_theme <home_dir> — give the current palette Moe's identity.
#
# Runs after the palette engine has already written the .colors file, the
# Konsole scheme and its own Global Theme, and rebuilds THAT package with Moe's
# manifest and sanitised defaults, because a LookAndFeel is applied by writing
# its contents/defaults into the user's config — so the package registered in
# plasmarc must be the sanitised one, not the generic wrapper. Reusing the
# engine's directory instead of creating a second Moe package is also what keeps
# this from leaving two entries in System Settings > Appearance > Global Theme.
#
# Best effort: returns 0 when the download fails and the generic theme stands.
moe_apply_theme() {
    local home_dir="$1"
    local lnf_id="${MOE_LNF_ID:-${PALETTE_SHORT:-MoeDark}Theme}"
    local lnf_dir="$home_dir/.local/share/plasma/look-and-feel/$lnf_id"
    local colors_file="$home_dir/.local/share/color-schemes/${PALETTE_SHORT:-MoeDark}.colors"

    moe_verify_palette "$colors_file" "$home_dir" || true

    local cache; cache="$(moe_cache_dir)"
    moe_fetch "Moe.tar.gz" "$MOE_ARCHIVE_SHA_LNF" || {
        log_info "Moe package unavailable — the palette's own Global Theme stays active."
        return 0
    }
    moe_extract "$MOE_FETCHED" "Moe" "$cache/lnf-src" || return 0
    local src="$MOE_EXTRACTED"
    [ -f "$src/contents/defaults" ] || {
        log_warn "Moe package has no contents/defaults — leaving the generated Global Theme alone."
        return 0
    }

    # Rebuild in place. The layout is stripped HERE rather than by deleting
    # contents/layouts afterwards, because the generated package never had one
    # and copying upstream's in even briefly would make a partially-written
    # package briefly claim a DesktopLayout it does not provide.
    # Only defaults and metadata are taken from upstream, and neither can carry
    # a layout: contents/layouts/ used to be deleted from the generated package
    # here, which was dead code — nothing had ever copied upstream's contents in,
    # so there was nothing to delete. That is still worth stating, because the
    # moment anyone does `cp -a "$src/contents/."` for the preview images, the
    # layout comes with it and replaces the panel. The unit tier asserts
    # contents/layouts does not exist after an install.
    run_as_user mkdir -p "$lnf_dir/contents" || return 1
    # The engine wrote contents/defaults a few lines ago; Moe only ADDS to it.
    moe_sanitize_defaults "$lnf_dir/contents/defaults" "$src/contents/defaults" \
                          "$lnf_dir/contents/defaults.moe" || return 1
    run_as_user mv -f "$lnf_dir/contents/defaults.moe" "$lnf_dir/contents/defaults" || return 1

    moe_write_metadata "$lnf_dir/metadata.json.tmp" "$lnf_id"
    run_as_user mv -f "$lnf_dir/metadata.json.tmp" "$lnf_dir/metadata.json" || return 1

    # contents/colors stays the engine's real copy of the generated scheme.
    # Plasma 6 reads colors from contents/defaults, and nothing reads
    # contents/colors, but the engine writes it and some tools expect it.
    [ -f "$colors_file" ] && run_as_user cp -f "$colors_file" "$lnf_dir/contents/colors"

    # Provenance marker, same name apply_global_theme writes: this directory is
    # now ours, so otto.sh-style discovery must not mistake it for an installed
    # upstream package on a later run.
    run_as_user touch "$lnf_dir/$DEVMKDE_GENERATED_MARKER" 2>/dev/null || true

    if command_exists plasma-apply-lookandfeel; then
        if run_as_user plasma-apply-lookandfeel --apply "$lnf_id" >/dev/null 2>&1; then
            log_ok "Moe Global Theme applied: $lnf_id (v$MOE_VERSION, sanitised, layouts/widgets stripped)"
        else
            log_warn "plasma-apply-lookandfeel did not apply $lnf_id — next login picks it up."
        fi
    fi
    if [ -n "$KWRITECONFIG" ]; then
        kwrite_user --file lookandfeeltoolrc --group "Global Theme" --key "LookAndFeelPackage" "$lnf_id"
    fi
    # plasmarc is the registration that actually matters: plasma-apply-lookandfeel
    # can exit 0 without writing it (see apply_global_theme's note).
    ini_set_key "$home_dir/.config/plasmarc" "Theme" "LookAndFeelPackage" "$lnf_id" \
        || log_warn "Could not register $lnf_id in plasmarc — set it in System Settings > Appearance."

    moe_apply_kvantum "$home_dir"
    return 0
}