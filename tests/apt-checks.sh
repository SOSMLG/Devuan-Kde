#!/usr/bin/env bash
# tests/apt-checks.sh — tier 3: read-only apt-cache package existence checks.
# Extracts every package name referenced by scripts/*.sh, then verifies each
# name exists in the local apt cache. One bulk `apt-cache dumpavail` call (fast)
# rather than N × apt-cache show. Skips gracefully when apt lists are missing.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# shellcheck source=lib/test-helpers.sh
. "$SCRIPT_DIR/lib/test-helpers.sh"

if ! command -v apt-cache >/dev/null 2>&1; then
    echo "  [apt-checks] apt-cache not found, skipping"
    t_ok "apt-cache not found, skipped"
    t_summary "apt-checks (skipped)"
fi

echo "  [apt-checks] dumping package names from local apt cache ..."
APT_PKGS="$(mktemp /tmp/devmkde-aptchecks.XXXXXX)"
trap 'rm -f "$APT_PKGS"' EXIT

apt-cache dumpavail 2>/dev/null \
    | grep -E '^Package:' | cut -d' ' -f2 | sort -u > "$APT_PKGS"

if [ ! -s "$APT_PKGS" ]; then
    echo "  [apt-checks] apt package lists appear empty or broken, skipping"
    echo "  [apt-checks] run 'apt-get update' to populate the cache"
    t_ok "apt lists empty, skipped"
    t_summary "apt-checks (skipped)"
fi

echo "  [apt-checks] extracting package names from scripts/ ..."
# shellcheck source=lib/extract-packages.sh
. "$SCRIPT_DIR/lib/extract-packages.sh"
ALL_PKGS="$(extract_packages_from scripts/*.sh | sort -u)"
PKG_COUNT="$(printf '%s\n' "$ALL_PKGS" | grep -c . || true)"
echo "  [apt-checks] found $PKG_COUNT unique package names"

# A package-shape token that is obviously English is extractor leakage, not a
# package. Catching it here means a future quoting bug shows up as
# "package not found: the" instead of silently passing because the name
# happens to exist.
LEAK="$(printf '%s\n' "$ALL_PKGS" | grep -xE \
    'the|this|that|for|and|from|with|your|you|see|use|try|get|set|not|but|all|any|its|one|two|new|old|run|then|re|or|if|is|as|at|by|do|so|to|up|we|no|my|it' || true)"
if [ -n "$LEAK" ]; then
    for w in $LEAK; do
        t_fail "extractor leaked prose as a package name: '$w'"
    done
else
    t_ok
fi

# .deb paths and Flatpak IDs are not archive package names either.
LEAK2="$(printf '%s\n' "$ALL_PKGS" | grep -E '\.deb$|^(com|org|io|md|app)\.[a-z]' || true)"
if [ -n "$LEAK2" ]; then
    for w in $LEAK2; do
        t_fail "extractor leaked a non-archive artifact: '$w'"
    done
else
    t_ok
fi

echo "  [apt-checks] checking existence in local apt cache (read-only) ..."
KNOWN=0
UNKNOWN=""
KNOWN_MISS="$SCRIPT_DIR/lib/known-miss.list"

# known-miss.list carries an inline reason after each name ("kjots   # dropped
# in Debian 13"). Strip to bare names once, so the exact-match lookups below
# can't be defeated by trailing comment padding.
KNOWN_MISS_NAMES=""
if [ -f "$KNOWN_MISS" ]; then
    KNOWN_MISS_NAMES="$(sed -e 's/[[:space:]]*#.*$//' -e '/^[[:space:]]*$/d' "$KNOWN_MISS")"
fi
KNOWN_MISS_NAMES="$KNOWN_MISS_NAMES"$'\n'

while IFS= read -r pkg; do
    [ -z "$pkg" ] && continue
    # known-miss: a real name that deliberately isn't an archive package
    # (installed as a .deb or via npm) or that Debian 13 has dropped.
    if printf '%b' "$KNOWN_MISS_NAMES" | grep -qFx -- "$pkg"; then
        KNOWN=$((KNOWN + 1))
        continue
    fi
    if grep -qFx -- "$pkg" "$APT_PKGS"; then
        KNOWN=$((KNOWN + 1))
    else
        UNKNOWN="$UNKNOWN $pkg"
    fi
done <<< "$ALL_PKGS"

echo "  [apt-checks] $KNOWN/$PKG_COUNT verified (known-miss entries included)"

if [ -n "$UNKNOWN" ]; then
    for pkg in $UNKNOWN; do
        t_fail "package not found in apt cache: $pkg"
    done
    echo
    echo "  If the name is correct but lives in contrib/non-free or is fetched"
    echo "  outside apt, add it to tests/lib/known-miss.list WITH a reason."
else
    t_ok "all $PKG_COUNT package names verified in apt cache"
fi

# Every known-miss entry should actually be needed. An entry that has since
# appeared in the archive (or become unreferenced) is stale and hides a real
# signal, so flag it.
if [ -n "$KNOWN_MISS_NAMES" ]; then
    STALE=""
    while IFS= read -r pkg; do
        [ -z "$pkg" ] && continue
        if grep -qFx -- "$pkg" "$APT_PKGS"; then
            STALE="$STALE ${pkg}(now-in-archive)"
        fi
        if ! printf '%s\n' "$ALL_PKGS" | grep -qxF -- "$pkg"; then
            STALE="$STALE ${pkg}(unreferenced)"
        fi
    done <<< "$KNOWN_MISS_NAMES"
    if [ -n "$STALE" ]; then
        for s in $STALE; do
            t_fail "stale known-miss entry: $s"
        done
    else
        t_ok
    fi
fi

echo
t_summary "apt-checks"