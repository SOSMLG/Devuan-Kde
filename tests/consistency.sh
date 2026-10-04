#!/usr/bin/env bash
# tests/consistency.sh — tier 3: cross-file consistency guards.
#
# Everything here is a whole-repo invariant that no single unit test can see:
# the VERSION↔RELEASE.md pairing, README rows matching the scripts on disk, the
# privilege rule applied uniformly, and the guards that keep Plasma 5 syntax
# from creeping back in. Read-only: no apt, no root, no X, no network.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=lib/test-helpers.sh
. "$SCRIPT_DIR/lib/test-helpers.sh"

# ─────────────────────────────────────────────────────────────────────────────
# 1. VERSION ↔ RELEASE.md
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f VERSION ]; then
    t_fail "VERSION file missing"
else
    t_ok
    VER="$(tr -d '[:space:]' < VERSION)"
    if [ -n "$VER" ]; then t_ok; else t_fail "VERSION is empty"; fi
    # X.Y.Z, no v prefix, no stray text.
    if [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then t_ok
    else t_fail "VERSION '$VER' is not plain MAJOR.MINOR.PATCH"; fi

    if [ ! -f RELEASE.md ]; then
        t_fail "RELEASE.md missing (release gate requires it)"
    else
        t_ok
        t_assert_grep "RELEASE.md documents version $VER" "$VER" RELEASE.md
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 2. Step scripts ↔ README
# Every 1x..5x step script must have a README row, and every README row must
# correspond to a script that exists. One direction going stale is how the docs
# end up advertising a step that was renamed away.
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f README.md ]; then
    t_fail "README.md missing"
else
    t_ok
    MISSING_ROW=""
    while IFS= read -r f; do
        base="$(basename "$f" .sh)"
        num="${base%%-*}"
        case "$num" in [0-9][0-9]) ;; *) continue ;; esac
        # Utilities are documented in their own section, not the step table.
        case "$num" in 5*) continue ;; esac
        if ! grep -qF "$base" README.md; then
            MISSING_ROW="$MISSING_ROW $base"
        fi
    done < <(find scripts -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort)
    if [ -n "$MISSING_ROW" ]; then
        for m in $MISSING_ROW; do t_fail "README.md has no row for $m"; done
    else
        t_ok
    fi

    # Every `NN-name.sh` mentioned in README must exist on disk.
    DANGLING=""
    for ref in $(grep -oE '\b[0-9]{2}-[a-zA-Z0-9_-]+\.sh\b' README.md | sort -u); do
        [ -f "scripts/$ref" ] || DANGLING="$DANGLING $ref"
    done
    if [ -n "$DANGLING" ]; then
        for d in $DANGLING; do t_fail "README.md references missing script $d"; done
    else
        t_ok
    fi

    # Every scripts/ path in the docs must carry its numeric prefix. The
    # rename to NN-camelCase.sh existed so `sort` orders steps numerically
    # rather than putting 9- after 48-, and an unprefixed path in the docs is
    # how the old convention creeps back in.
    UNPREFIXED=""
    for ref in $(grep -oE '\bscripts/[A-Za-z0-9_-]+\.sh\b' README.md | sort -u); do
        base="$(basename "$ref")"
        case "$base" in
            [0-9][0-9]-*) ;;
            verifySetup.sh) ;;
            NN-*) ;;   # the README documents the naming convention as a placeholder
            *) UNPREFIXED="$UNPREFIXED $ref" ;;
        esac
    done
    if [ -n "$UNPREFIXED" ]; then
        for u in $UNPREFIXED; do t_fail "README.md path without numeric prefix: $u"; done
    else
        t_ok
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# 3. Privilege rule: no bare sudo at any call site in scripts/
# ─────────────────────────────────────────────────────────────────────────────
if command -v python3 >/dev/null 2>&1; then
    BARE="$(python3 - <<'PY'
import re, pathlib
bad = []
for p in sorted(pathlib.Path("scripts").rglob("*.sh")):
    for i, line in enumerate(p.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        s = re.sub(r"#.*$", "", line)                 # drop comments
        s = re.sub(r'"[^"]*"', '""', s)                # drop double-quoted strings
        s = re.sub(r"'[^']*'", "''", s)                # drop single-quoted strings
        # Only a sudo used as a COMMAND (start of line, after ; & | ( or
        # `then`) is an escalation. `$(sudo ...)` and `sudo` inside prose or
        # inside a heredoc-generated artifact are handled explicitly below.
        if re.search(r'(^|[;&|(`]|\bthen\s+|\bdo\s+)\s*sudo\b', s):
            bad.append(f"{p}:{i}: {line.strip()}")
print("\n".join(bad))
PY
)"
    if [ -n "$BARE" ]; then
        while IFS= read -r l; do t_fail "bare sudo at $l"; done <<< "$BARE"
    else
        t_ok
    fi

else
    t_ok "python3 unavailable, skipped bare-sudo scan"
fi

# ─────────────────────────────────────────────────────────────────────────────
# 4. Plasma 5 syntax must not come back
#
# These run against CODE, with comments stripped first. Several scripts carry a
# comment naming the old spelling precisely so the next person doesn't
# reintroduce it ("Plasma 6 folded the old kwineffectsrc into kwinrc…"), and a
# naive grep turns that documentation into a permanent red test. Stripping
# comments is what makes the guard check behaviour instead of vocabulary.
# ─────────────────────────────────────────────────────────────────────────────

PLASMA5_BAD=0
# code_scan <pattern> <description> [scope]
#
# Scans WRITER scripts by default: scripts/[0-9][0-9]-*.sh and scripts/lib/*.sh.
#
# verifySetup.sh is deliberately excluded from these scans, and that is not a
# loophole: it is the auditor, so it MUST be able to name the deprecated key in
# order to grep for it and warn. A guard that flagged the detector would force
# the detector to stop detecting. The rule this enforces is "no step may WRITE
# a Plasma 5 key", which is the rule that actually matters.
#
# The other exclusion is comments, stripped above: several scripts explain in
# prose why the old spelling is wrong, and that documentation must not be
# forced out of the codebase to keep a test green.
#
# KNOWN LIMITATION of that strip, recorded here because it was found the hard
# way in the guard below (7c2): `sed 's/[[:space:]]*#.*$//'` truncates any line
# containing a '#' inside a string, so a violation that follows a '#' in a quoted
# argument is invisible to these scans. A quote-aware stripper is the proper fix
# and is deliberately NOT applied here: these four guards are the ones the
# existing negative controls cover, and rewriting their filter to fix a blind
# spot that no current script can reach would put green guards at risk for no
# observed failure. 7c2 uses whole-line comment filtering instead, which is
# safe for its own line shape.
code_scan() {
    local pat="$1" desc="$2" scope="${3:-writers}" hit paths
    if [ "$scope" = "writers" ]; then
        paths="$(find scripts -maxdepth 2 \( -name '[0-9][0-9]-*.sh' -o -path 'scripts/lib/*.sh' \) -print)"
    else
        paths="$(find scripts -name '*.sh' -print)"
    fi
    hit="$(printf '%s\n' "$paths" | xargs -r sed -e 's/[[:space:]]*#.*$//' 2>/dev/null \
            | grep -nE "$pat" || true)"
    if [ -n "$hit" ]; then
        t_fail "$desc"
        while IFS= read -r h; do t_fail "    $h"; done <<< "$hit"
        PLASMA5_BAD=1
    fi
}
code_scan 'kwineffectsrc'            "scripts reference kwineffectsrc (Plasma 5); effects live in kwinrc [Plugins]"
# Match BOTH the bare INI form and the kwriteconfig call form. An earlier
# version of this guard only matched `AccentColorFromWallpaper=`, which NO
# script actually writes -- they all go through `--key AccentColorFromWallpaper`
# -- so a live write sat in theme.sh for a whole release cycle while the guard
# cheerfully reported the key as absent. Matching one spelling of a key when the
# codebase uses the other is worse than not matching at all: it looks covered.
code_scan 'AccentColorFromWallpaper' "scripts reference AccentColorFromWallpaper; Plasma 6 dropped it, use AccentColor"
code_scan 'khotkeysrc'               "scripts reference khotkeysrc (Plasma 6 uses KGlobalAccel)"
# A new 5x utility or a non-step helper should still be covered.
code_scan 'khotkeysrc'               "a non-step script references khotkeysrc" all
code_scan 'metadata\.desktop'       "scripts reference metadata.desktop (Plasma 6 wants metadata.json)"
code_scan '(CurrentDesktopLayout|DesktopLayout)=(switch|windows)' \
          "kwinrc TabBox still uses the Plasma 5 layout names"
[ "$PLASMA5_BAD" -eq 0 ] && t_ok

# ─────────────────────────────────────────────────────────────────────────────
# 5. Theme ↔ palette wiring
# ─────────────────────────────────────────────────────────────────────────────
t_assert_grep "theme.sh knows the templates dir" 'THEME_TEMPLATES_DIR' scripts/lib/theme.sh
for tpl in plasma.colors.tpl konsole.colorscheme.tpl konsole.profile.tpl; do
    if [ -f "themes/_base/tpl/$tpl" ]; then t_ok
    else t_fail "missing template themes/_base/tpl/$tpl"; fi
done
# Every palette must define the same variable set as the reference palette.
# Palettes are palette_<id>() functions in one file now, so a whole-function
# window is extracted per palette rather than grepping a whole file: the grep
# would otherwise see the function name's neighbours as part of every palette.
# shellcheck source=/dev/null
source themes/palettes.sh
REF="darkmatter"
palette_var_set() {
    sed -n "/^palette_${1//-/_}() {$/,/^}$/p" themes/palettes.sh \
        | grep -oE '^(C_|RG_)?[A-Za-z0-9_]+=' | sort -u
}
REFSET="$(palette_var_set "$REF")"
DRIFT=""
for p in "${PALETTE_IDS[@]}"; do
    SET="$(palette_var_set "$p")"
    [ "$SET" = "$REFSET" ] || DRIFT="$DRIFT $p"
done
if [ -n "$DRIFT" ]; then
    for d in $DRIFT; do t_fail "palette $d defines a different variable set than $REF"; done
else
    t_ok
fi

# Every palette_<id>() in the file must be listed in PALETTE_IDS, and vice
# versa. A function nobody registered is a palette no picker can reach; an id
# with no function is a picker row that dies on selection.
#
# Compared through palette_fn, not by raw name: the file's convention is
# palette_foo_bar() for id "foo-bar", and a palette_foo-bar() would satisfy a
# naive grep while being uncallable in bash.
REG=""
for id in "${PALETTE_IDS[@]}"; do REG="$REG palette_${id//-/_}"; done
UNREG=""
for fn in $(grep -oE '^palette_[A-Za-z0-9_-]+' themes/palettes.sh | sort -u); do
    case " $REG " in *" $fn "*) ;; *) UNREG="$UNREG $fn" ;; esac
done
NOLIB=""
for id in "${PALETTE_IDS[@]}"; do
    declare -F "palette_${id//-/_}" >/dev/null 2>&1 || NOLIB="$NOLIB $id"
done
if [ -n "$UNREG$NOLIB" ]; then
    [ -n "$UNREG" ] && t_fail "palette function(s) not in PALETTE_IDS:$UNREG"
    [ -n "$NOLIB" ] && t_fail "PALETTE_IDS entries with no function:$NOLIB"
else
    t_ok
fi

# Every palette colour must be valid hex. load_palette() rejects a bad one at
# apply time, but only for the palette being applied — so a typo in a palette
# nobody has selected yet stays invisible until the day someone picks it. And
# the failure is a plausible-looking near-black rather than an error, because
# printf evaluates an invalid hex literal as 0.
HEX_BAD=""
for p in "${PALETTE_IDS[@]}"; do
    bad="$(sed -n "/^palette_${p//-/_}() {$/,/^}$/p" themes/palettes.sh \
           | grep -oE '^C_[A-Za-z0-9_]*=[^"'"'"'[:space:]#]*' \
           | sed 's/^[^=]*=//' | grep -vE '^[0-9a-fA-F]{6}$' || true)"
    [ -z "$bad" ] || HEX_BAD="$HEX_BAD $p"
done
if [ -n "$HEX_BAD" ]; then
    for d in $HEX_BAD; do t_fail "palette $d has a C_* value that is not 6-digit hex"; done
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 5b. The default palette must be the same in both places that apply one.
#
# 14-plasmaTheme.sh picks the palette on a fresh install; 46-applyThemes.sh
# re-applies one on demand AND under DEVMKDE_ASSUME_YES, which install.sh
# exports for every unattended run. They once disagreed (darkmatter vs the
# pre-migration mocha-red), so an unattended `./install.sh` would install the
# Darkmatter theme and then immediately repaint the desktop away from it.
# Nothing failed, no test noticed — it just looked like the theme step not
# working.
# ─────────────────────────────────────────────────────────────────────────────
D14="$(grep -m1 -oE '^DEFAULT_PALETTE="[^"]*"' scripts/14-plasmaTheme.sh | sed 's/.*="//;s/"//')"
D46="$(grep -m1 -oE 'DEVMKDE_DEFAULT_PALETTE:-[^}]*' scripts/46-applyThemes.sh | sed 's/.*:-//')"
if [ -n "$D14" ] && [ "$D14" = "$D46" ]; then
    t_ok
else
    t_fail "default palette drift: 14-plasmaTheme.sh=$D14 but 46-applyThemes.sh=$D46"
fi
# "Registered" is the real requirement now that palettes share one file: a
# directory that merely exists would prove nothing, an unregistered id would
# not be picked.
if [ -n "$D14" ] && case " ${PALETTE_IDS[*]} " in *" $D14 "*) true ;; *) false ;; esac; then t_ok
else t_fail "default palette '$D14' is not registered in themes/palettes.sh"; fi

# ─────────────────────────────────────────────────────────────────────────────
# 6. Step numbering: 1x core, 3x sysmgmt, 4x optional, 5x standalone
# ─────────────────────────────────────────────────────────────────────────────
PHASE_BAD=0
while IFS= read -r f; do
    base="$(basename "$f" .sh)"; num="${base%%-*}"
    ph="$(grep -m1 -oE '^# DEVMKDE_PHASE: .*$' "$f" | sed 's/^# DEVMKDE_PHASE: //')"
    case "$num" in
        1*) want=core ;;
        3*) want=sysmgmt ;;
        4*) want=optional ;;
        5*) want=standalone ;;
        *) want="" ;;
    esac
    [ "$want" = "" ] && continue
    if [ "$ph" != "$want" ]; then
        t_fail "$base: DEVMKDE_PHASE is '$ph', expected '$want' for a ${num}x step"
        PHASE_BAD=1
    fi
done < <(find scripts -maxdepth 1 -name '[0-9][0-9]-*.sh' | sort)
[ "$PHASE_BAD" -eq 0 ] && t_ok

# No duplicate step numbers (a rename collision would silently drop a step).
DUPES="$(find scripts -maxdepth 1 -name '[0-9][0-9]-*.sh' -printf '%f\n' \
         | cut -d- -f1 | sort | uniq -d)"
if [ -n "$DUPES" ]; then
    for d in $DUPES; do t_fail "duplicate step number $d-"; done
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7. No bundled theme/icon payload — it is fetched at install time
# ─────────────────────────────────────────────────────────────────────────────
if [ -d themes/darkmatter ] && find themes/darkmatter -type f \
     \( -name '*.png' -o -name '*.svg' -o -name '*.qml' -o -name '*.zip' \) \
     -print -quit 2>/dev/null | grep -q .; then
    t_fail "themes/darkmatter contains binary/compiled assets; the rice is fetched, not bundled"
else
    t_ok
fi
if [ -d icons ] && find icons -type f -print -quit 2>/dev/null | grep -q .; then
    t_fail "icons/ is populated; Zafiro icons are fetched, not bundled"
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7b. Bundled assets: the fastfetch configs, and the fact that ButterBash is
#     fetched at install time rather than vendored.
#
# Both directions matter. A config the step installs but the repo no longer
# ships makes the step fail on a fresh clone, and nothing in the script says
# where the file was supposed to come from. Conversely, a vendored butterbash/
# directory means the pinned commit is being ignored in favour of whatever is
# in the tree — the pin becomes decorative.
# ─────────────────────────────────────────────────────────────────────────────
FASTFETCH_BAD=0
for cfg in devuan.jsonc devuan-minimal.jsonc; do
    if [ -f "assets/fastfetch/$cfg" ]; then
        t_ok
    else
        t_fail "assets/fastfetch/$cfg is missing; 23-fastfetchConfig.sh installs it"
        FASTFETCH_BAD=1
    fi
    # The step must name the exact file, or it will happily install one variant
    # and advertise the other.
    if grep -qF "$cfg" scripts/23-fastfetchConfig.sh; then t_ok
    else t_fail "23-fastfetchConfig.sh never mentions $cfg"; FASTFETCH_BAD=1; fi
done

# 23-fastfetchConfig.sh used to pull remote preset JSONs. It must not reach the
# network at all now: the whole point of moving them into assets/ is that the
# configs are reviewable text in this repo.
if grep -nE '(curl|wget)' scripts/23-fastfetchConfig.sh >/dev/null 2>&1; then
    t_fail "23-fastfetchConfig.sh downloads something; its configs are bundled in assets/"
    FASTFETCH_BAD=1
else
    t_ok
fi
[ "$FASTFETCH_BAD" -eq 0 ] && t_ok

# The vendored copy must be gone from git AND from the working tree.
if [ -e butterbash ]; then
    t_fail "butterbash/ exists; 22-terminalButterbash.sh fetches a PINNED commit instead"
    FASTFETCH_BAD=1
else
    t_ok
fi
if git ls-files --error-unmatch butterbash >/dev/null 2>&1; then
    t_fail "butterbash/ is still tracked in git; the pin in script 22 would be bypassed"
    FASTFETCH_BAD=1
else
    t_ok
fi
# The pin has to be a full commit sha AND have a checksum next to it: a branch
# name is not a pin, and a pinned archive with no checksum is a pin in name
# only.
# The assignments are written as "${BUTTERBASH_REF:-<sha>}" so the pin is
# overridable from the environment. Strip the shell wrapper and keep the last
# hex run on the line, which is the default value.
# The captured text ends in '}"', so take the LAST hex run of the right length
# rather than anchoring to the end of the line.
BB_REF="$(grep -m1 -oE 'BUTTERBASH_REF="[^"]*"' scripts/22-terminalButterbash.sh | grep -oE '[0-9a-f]{40}' | tail -1)"
BB_SHA="$(grep -m1 -oE 'BUTTERBASH_SHA256="[^"]*"' scripts/22-terminalButterbash.sh | grep -oE '[0-9a-f]{64}' | tail -1)"
if [[ "$BB_REF" =~ ^[0-9a-f]{40}$ ]]; then t_ok
else t_fail "BUTTERBASH_REF is '$BB_REF', not a full 40-char commit sha"; FASTFETCH_BAD=1; fi
if [ -n "$BB_SHA" ]; then t_ok
else t_fail "22-terminalButterbash.sh pins no BUTTERBASH_SHA256"; FASTFETCH_BAD=1; fi

# ─────────────────────────────────────────────────────────────────────────────
# 7c. Otto: the palette is bundled, the theme itself is not.
#
# Otto is a GUI install from store.kde.org (behind Anubis), so nothing about it
# may be committed here — but the palette that recolours it must be. A vendored
# copy of the theme would mean shipping someone else's artwork and licence;
# a missing palette would mean the recolouring code has nothing to drive.
# ─────────────────────────────────────────────────────────────────────────────
if declare -F palette_otto >/dev/null 2>&1 && grep -q '^    otto$' themes/palettes.sh; then t_ok
else t_fail "palette_otto() missing from themes/palettes.sh"; FASTFETCH_BAD=1; fi
if [ -f scripts/lib/otto.sh ]; then t_ok
else t_fail "scripts/lib/otto.sh missing"; FASTFETCH_BAD=1; fi
# theme.sh must source it, or the otto palette silently applies without the Otto
# integration and nothing logs an error. Comments are stripped first: the header
# explains the whole relationship in prose, and a guard that matched that prose
# would report "sourced" while the . line below it had been deleted.
# Process substitution, NOT `sed ... | grep -q`: grep -q exits the moment it
# matches, sed dies on SIGPIPE, and under `set -o pipefail` the whole pipeline
# then reports failure — so a guard for "otto.sh IS sourced" fails precisely
# when it is.
if grep -qE '(^|[[:space:]])\. .*otto\.sh' < <(sed -e 's/[[:space:]]*#.*$//' scripts/lib/theme.sh); then t_ok
else t_fail "theme.sh does not source otto.sh"; FASTFETCH_BAD=1; fi
# 7d. Moe: the palette and the sanitiser are in-tree, the theme is NOT.
#
# Moe is fetched from a pinned mirror rather than bundled, for the same reason
# Otto is not bundled (someone else's artwork and licence) — but unlike Otto it
# IS reachable by URL, so the thing that must be pinned is the checksum. An
# unpinned download of a theme that WRITES the user's config is the one place
# where a compromised or re-tagged mirror would matter.
# ─────────────────────────────────────────────────────────────────────────────
if declare -F palette_moe_dark >/dev/null 2>&1 && grep -q '^    moe-dark$' themes/palettes.sh; then t_ok
else t_fail "palette_moe_dark() missing or unregistered in themes/palettes.sh"; FASTFETCH_BAD=1; fi
if [ -f scripts/lib/moe.sh ]; then t_ok
else t_fail "scripts/lib/moe.sh missing"; FASTFETCH_BAD=1; fi
if grep -qE '(^|[[:space:]])\. .*moe\.sh' < <(sed -e 's/[[:space:]]*#.*$//' scripts/lib/theme.sh); then t_ok
else t_fail "theme.sh does not source moe.sh"; FASTFETCH_BAD=1; fi
# Every archive moe.sh fetches must carry a full-length SHA256 pin, and the
# commit must be pinned too: a floating branch ref would make the hashes
# unverifiable on the next run.
BADPIN=""
for v in MOE_ARCHIVE_SHA_LNF MOE_ARCHIVE_SHA_COLORS MOE_ARCHIVE_SHA_KVANTUM MOE_ARCHIVE_SHA_KONSOLE; do
    pin="$(sed -n "s/^$v=\"\\([^\"]*\\)\"/\\1/p" scripts/lib/moe.sh)"
    printf '%s' "$pin" | grep -qE '^[0-9a-f]{64}$' || BADPIN="$BADPIN $v"
done
if [ -n "$BADPIN" ]; then
    for b in $BADPIN; do t_fail "$b is not a 64-hex-digit SHA256 pin"; done
else
    t_ok
fi
if grep -qE '^MOE_UPSTREAM_COMMIT="[0-9a-f]{40}"$' scripts/lib/moe.sh; then t_ok
else t_fail "MOE_UPSTREAM_COMMIT is not a pinned 40-hex commit"; FASTFETCH_BAD=1; fi
# No Moe artwork either: it is fetched into ~/.cache at apply time, never
# vendored. The 7c check above covers themes/ and scripts/ wholesale.

# 7e. The documented palette count matches the registry.
# Three separate documents each state how many palettes ship, and all three were
# stale at once after moe-dark landed. A count nobody can check is a count that
# rots, so it is checked: PALETTE_IDS is the only source of truth.
# PALETTE_IDS is a multi-line array, so it is read as a block rather than with a
# single-line s///.
pal_ids="$(awk '/^PALETTE_IDS=\(/{f=1;next} f&&/^\)/{exit} f{print}' themes/palettes.sh)"
n_pal="$(printf '%s\n' "$pal_ids" | tr -s ' \t' '\n' | grep -c .)"
if [ "${n_pal:-0}" -ge 1 ]; then
    t_assert_grep "README states the real palette count" ", $n_pal palettes)" README.md
    t_assert_grep "RELEASE.md states the real palette count" "$n_pal palettes ship in-tree" RELEASE.md
    t_assert_grep "the skill states the real palette count" "Kit: \\*\\*$n_pal palettes\\*" scripts/skills/devuan-kde-SKILL.md
    # And every id in the registry is named in the skill doc, or a palette
    # exists that no document mentions.
    for pid in $pal_ids; do
        if grep -q -- "$pid" scripts/skills/devuan-kde-SKILL.md; then t_ok
        else t_fail "palette '$pid' is in PALETTE_IDS but not listed in the skill doc"; fi
    done
else
    t_fail "could not read PALETTE_IDS out of themes/palettes.sh"
fi

# No Otto artwork anywhere in the tree (metadata.json in themes/ is fine — the
# palette is not artwork).
if find themes scripts -type f \( -name '*.png' -o -name '*.svg' -o -name '*.zip' \) 2>/dev/null | grep -q .; then
    t_fail "Otto/artwork binaries found under themes/ or scripts/; themes are generated, not bundled"
    FASTFETCH_BAD=1
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7c2. ImageMagick operators that quietly wreck a dark palette's wallpaper.
#
# "-function polynomial 6,-5,1" is documented as a contrast curve and maps 0→1,
# 1→2. Applied to a gradient between two near-black tones it therefore lifts the
# whole image into the highlights: measured 5.5% mean brightness without it and
# 74% with it. Nothing errors, the file is a valid PNG of the right size, and
# the result is a light grey wallpaper behind a black theme — which reads as
# "the theme did not apply". It cost a real debugging cycle to find, so the
# operator is now banned everywhere in scripts/ rather than merely removed once.
# ─────────────────────────────────────────────────────────────────────────────
# Whole-line comments are dropped, but ONLY whole-line ones, and the reason is
# specific rather than stylistic: the sed one-liner this file uses elsewhere
# (`s/[[:space:]]*#.*$//`) truncates any line containing a '#' INSIDE a string,
# and this very operator sits on a line that must contain one --
# "gradient:#${C_BG}-#${C_MANTLE}". Under that filter the guard cannot see the
# code it is guarding, while the prose explaining the ban reads perfectly. The
# check below was green with the operator present until a negative control
# caught it.
POLY="$(find scripts -name '*.sh' -print | xargs -r cat 2>/dev/null \
        | grep -v '^[[:space:]]*#' \
        | grep -n -- '-function polynomial' || true)"
if [ -n "$POLY" ]; then
    t_fail "scripts/ uses ImageMagick -function polynomial; it inverts dark gradients"
else
    t_ok
fi

# contents/colors must be a real file everywhere it is written. Plasma 6
# kpackages do not support a symlink there; apply_global_theme says so at
# length, and the Otto theme shipped with a symlink anyway because that is what
# upstream themes do. A symlink renders as a theme with no colours at all.
# The location prefix is stripped before the comment test, otherwise the
# "^[[:space:]]*#" filter can never match a line that starts with "file:12:".
SYMCOL="$(grep -rn -- 'ln -sf.*contents/colors' scripts/ 2>/dev/null \
          | sed 's/^[^:]*:[0-9]*://' | grep -v '^[[:space:]]*#' || true)"
if [ -n "$SYMCOL" ]; then
    t_fail "a script symlinks contents/colors; Plasma 6 kpackages need a real file"
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 7d. The panel script must persist panel properties the way Plasma reads them.
#
# Both plausible mechanisms are silent when wrong, and they are opposites.
# PanelView::config() is [PlasmaViews][Panel <id>][Horizontal <w>], and the
# property setters write into config().parent(); the scripting wrapper's
# writeConfig targets the CONTAINMENT group instead. So writeConfig("floating")
# persists nothing at all, and a payload built on it leaves a config file that
# looks saved (floating=true under [Containments]) while PanelView has no
# [PlasmaViews] section to read.
#
# This was caught by running the payload against a live plasmashell, not by
# reading it: every assertion below was green while floating, alignment and the
# tray's 340px length silently did nothing. Guard both directions — the inert
# writeConfig, and an opacity assignment, which the setter ignores for every
# value. This block previously asserted the exact inverse and had to be
# rewritten, which is why it now carries its evidence inline.
PANEL=scripts/47-plasmaPanel.sh
if [ -f "$PANEL" ]; then
    # Whole-line JS comments only. Stripping trailing '#' comments instead
    # would truncate a line at any '#' and hide the code after it.
    # The payload is the `cat << JS` heredoc inside build_js() — indented, like
    # every line in a function body, and closed by an indented `JS` two hundred
    # lines later. Both anchors were wrong at first (/^cat > .*<<.*JS/ and
    # /^cat << *JS$/), which made this range match nothing: the guard then
    # tested an empty string, passed every check, and reported success. An
    # empty-input guard is worse than no guard, because it looks green.
    panel_code() {
        grep -v '^[[:space:]]*//' "$PANEL" \
            | sed -n "/^[[:space:]]*cat << *'JS'$/,/^[[:space:]]*JS$/p"
    }
    if [ -z "$(panel_code)" ]; then
        t_fail "panel payload heredoc not found in $PANEL — the checks below would pass vacuously"
    else
        t_ok
    fi
    for k in floating alignment minimumLength maximumLength; do
        if panel_code | grep -qE "writeConfig\\(\"$k\""; then
            t_fail "panel writeConfig's '$k' into the containment group; PanelView reads [PlasmaViews]"
        else
            t_ok
        fi
    done
    t_assert_grep "app bar floats via the property setter" 'app\.floating = true' "$PANEL"
    t_assert_grep "app bar aligns via the property setter" 'app\.alignment = "center"' "$PANEL"
    t_assert_grep "tray bar floats via the property setter" 'tray\.floating = true' "$PANEL"
    t_assert_grep "tray bar pins its length via the setters" 'tray\.maximumLength = 340' "$PANEL"
    # An enum name the setter does not accept reads back as the default and
    # logs nothing, so the panel looks configured when it is not.
    #
    # "windowsgobelow" is NOT in this list, and was briefly added by mistake.
    # It is a correct value: the setter persists panelVisibility=3, and only
    # the getter is lossy (it answers "none" for both 0 and 3). Reading the
    # property back is not a way to test it — plasmashellrc is.
    for bad in 'hiding = "WindowsGoBelow"' 'hiding = "windowscover"' '.opacity = '; do
        if panel_code | grep -qF -- "$bad"; then
            t_fail "panel assigns a value the Plasma 6.3.6 setter ignores: $bad"
        else
            t_ok
        fi
    done
    t_assert_grep "app bar hiding stays a value the setter accepts" 'app\.hiding = "\$APP_HIDING"' "$PANEL"
    # One bar is the default layout, and the two flags that undo it are the only
    # way back. If the defaults flip, the header, README and --help all start
    # describing a layout the script no longer builds — so pin the defaults, not
    # just the flags.
    t_assert_grep "panel defaults to a single bar"  '^TRAY_PANEL=0$'    "$PANEL"
    t_assert_grep "panel defaults to no extras"     '^PANEL_EXTRAS=0$'  "$PANEL"
    t_assert_grep "panel documents --tray-panel"    '\-\-tray-panel'     "$PANEL"
    t_assert_grep "panel documents --extras"        '\-\-extras'         "$PANEL"
    # --no-tray-panel used to be the single-panel switch; it is now a no-op kept
    # so older invocations and docs keep parsing.
    t_assert_grep "panel still accepts --no-tray-panel" '\-\-no-tray-panel\) *: *; *;' "$PANEL"
    # The spacer must be non-expanding, or "floating" stretches across the
    # screen and the reason for the panel layout stops existing.
    if grep -qF 'addWidget("org.kde.plasma.panelspacer")' "$PANEL"; then t_ok
    else t_fail "47-plasmaPanel.sh no longer adds a panelspacer"; fi
    # qdbus prints D-Bus failures on stdout; discarding it produced an empty
    # log file next to a bare "evaluateScript failed" and no error at all.
    t_assert_grep "panel keeps qdbus diagnostics" '2>&1 "\$\(build_payload\)"' "$PANEL"
    # Panel geometry is written to plasmashellrc, not to the appletsrc this
    # script used to back up on its own, so a one-file backup cannot be
    # restored in full.
    t_assert_grep "panel identifies the geometry file" \
        'SHELLRC=".*\.config/plasmashellrc"' "$PANEL"
    t_assert_grep "panel backs the geometry file up" \
        'cp -a "\$SHELLRC" "\$SHELLRC_BACKUP"' "$PANEL"
    t_assert_grep "panel restores the geometry file" \
        'cp -a "\$SHELLRC_BACKUP" "\$SHELLRC"' "$PANEL"
    # An unquoted heredoc expands the JS body in the shell first: a backticked
    # word in a comment runs as a command substitution, the payload still
    # applies, and the only symptom is stderr nobody reads.
    t_assert_grep "the payload heredoc is quoted" "<< 'JS'" "$PANEL"
    t_assert_not_grep "the payload heredoc is not left unquoted" '<< JS$' "$PANEL"
    # sed's delimiter must not collide with PIN_JOINED's "||" separator, or the
    # substitution aborts and the panel silently ships with zero pinned apps.
    t_assert_not_grep "sed delimiter does not collide with the URL separator" \
        's\|URLS=' "$PANEL"
else
    t_fail "$PANEL missing"
fi


# Build the needle from parts so this very file does not match itself.
DEVHOME="/home/""sosmlg"
LEAKED="$(grep -rn "$DEVHOME" --include='*.sh' --include='*.md' --include='Makefile' \
          --include='*.yml' . 2>/dev/null | grep -v '^\./\.git/' || true)"
if [ -n "$LEAKED" ]; then
    while IFS= read -r l; do t_fail "hardcoded developer path: $l"; done <<< "$LEAKED"
else
    t_ok
fi

# ─────────────────────────────────────────────────────────────────────────────
# 9. .gitignore covers build output
# ─────────────────────────────────────────────────────────────────────────────
if [ ! -f .gitignore ]; then
    t_fail ".gitignore missing"
else
    t_ok
    # Fixed-string matching: these are glob-shaped literals, and feeding
    # '*.deb' to an ERE is a leading-* error (GNU grep warns, then matches the
    # asterisk literally — which passes by accident and hides a real typo).
    for pat in 'build/' '*.deb' '*.bak.*'; do
        t_assert ".gitignore covers $pat" grep -qF -- "$pat" .gitignore
    done
fi

echo
t_summary "consistency"