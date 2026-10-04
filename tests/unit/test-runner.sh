#!/usr/bin/env bash
# tests/unit/test-runner.sh — tier 2: run.sh / install.sh behaviour.
#
# These tests NEVER execute a step. `./run.sh --only x | head` once really did
# run 12-kdeDebloat.sh, because ask() saw EOF on the closed stdin and silently
# took every default — so every invocation here is restricted to flags that
# only print, plus explicit greps against run.sh's own source for the logic
# that decides what to execute.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

RUN="$REPO_ROOT/run.sh"

# ── read-only flags: safe to actually run ───────────────────────────────────
out="$("$RUN" --list 2>&1)"
t_assert_grep "--list prints a header"            'Runnable steps|Run everything' <<< "$out"

# Every numbered step script must appear, in numeric order.
for s in 10-addUserToGroups 14-plasmaTheme 28-kdeHotkeys 33-plasmaPerformance 48-plasmaAddons; do
    t_assert_grep "--list includes $s" "$s" <<< "$out"
done

# Numeric (not lexicographic) ordering: 33 must come after 29 and before 40.
line_of() { grep -n "$1" <<< "$out" | head -1 | cut -d: -f1; }
L29="$(line_of 29-aiOpencode)"; L33="$(line_of 33-plasmaPerformance)"; L40="$(line_of 40-installPhotogimp)"
if [ -n "$L29" ] && [ -n "$L33" ] && [ -n "$L40" ] && [ "$L29" -lt "$L33" ] && [ "$L33" -lt "$L40" ]; then
    t_ok
else
    t_fail "--list is not in numeric order (29=$L29 33=$L33 40=$L40)"
fi

# --list must NOT include the standalone utilities (5x).
for s in 50-configBackup 51-systemMaintenance 52-exportToSkel; do
    if grep -q "$s" <<< "$out"; then
        t_fail "--list wrongly includes standalone step $s"
    else
        t_ok
    fi
done

# ── --list-utilities shows ONLY the 5x utilities ───────────────────────────
uout="$("$RUN" --list-utilities 2>&1)"
t_assert_grep "--list-utilities prints a header" 'Standalone utilities' <<< "$uout"
for s in 50-configBackup 51-systemMaintenance 52-exportToSkel; do
    t_assert_grep "--list-utilities includes $s" "$s" <<< "$uout"
done
for s in 10-addUserToGroups 33-plasmaPerformance 48-plasmaAddons; do
    if grep -q "$s" <<< "$uout"; then
        t_fail "--list-utilities wrongly includes runnable step $s"
    else
        t_ok
    fi
done

# ── every step script carries valid headers ─────────────────────────────────
BAD_HEADERS=0
while IFS= read -r f; do
    grep -qE '^# DEVMKDE_DESC: .+' "$f" || { t_fail "$f: missing/blank DEVMKDE_DESC"; BAD_HEADERS=1; }
    grep -qE '^# DEVMKDE_DEFAULT: [YN]$' "$f" || { t_fail "$f: DEVMKDE_DEFAULT must be Y or N"; BAD_HEADERS=1; }
    grep -qE '^# DEVMKDE_PHASE: (core|sysmgmt|optional|standalone)$' "$f" \
        || { t_fail "$f: DEVMKDE_PHASE must be core|sysmgmt|optional|standalone"; BAD_HEADERS=1; }
done < <(find "$REPO_ROOT/scripts" -maxdepth 1 -type f -name '[0-9][0-9]-*.sh' | sort)
[ "$BAD_HEADERS" -eq 0 ] && t_ok

# ── the X11 guard uses the two-test form bash actually accepts ─────────────
# `if [ -n "$x" && "$x" = y ]` prints "[: missing ]" in this environment and
# still executes the branch. The correct form is two separate [ ] tests.
#
# The detector is `[ ... -n ... && ... ]` with NO `]` between the `-n` and the
# `&&` — a `[^]]*` that can't cross a closing bracket. A looser pattern like
# `XDG_SESSION_TYPE.*&&.*x11` matches the GOOD line too, because
# `[ -n "${XDG_SESSION_TYPE:-}" ] && [ "${XDG_SESSION_TYPE:-}" = "x11" ]`
# contains an `&&` and an `= "x11"`, and would have kept this test permanently
# red against correct code.
if sed -e 's/[[:space:]]*#.*$//' "$RUN" | grep -qE '\[[^]]*-n [^]]*&&'; then
    t_fail "run.sh: X11 check still uses the single-[ && form"
else
    t_ok
fi
t_assert_grep "run.sh warns about X11" 'X11' "$RUN"
t_assert_grep "run.sh actually checks XDG_SESSION_TYPE" 'XDG_SESSION_TYPE' "$RUN"

# ── unknown flags are rejected rather than silently ignored ────────────────
if "$RUN" --definitely-not-a-flag >/dev/null 2>&1; then
    t_fail "run.sh accepted an unknown flag"
else
    t_ok
fi

# ── --only with a bad name must not silently run nothing then "succeed" ────
# (Checked by inspection: run.sh validates the name before resolving.)
t_assert_grep "run.sh validates --only names" 'Unknown step|unknown step|not found|no step' "$RUN"

# ── run.sh must route escalation through priv(), not bare sudo ─────────────
if sed -e 's/[[:space:]]*#.*$//' "$RUN" | grep -qE '(^|[;&|(])sudo[[:space:]]'; then
    t_fail "run.sh invokes bare sudo instead of priv()"
else
    t_ok
fi
t_assert_grep "run.sh defines priv()" 'priv()' "$RUN"
t_assert_grep "run.sh prefers sudo then doas" 'command -v sudo' "$RUN"

# ── install.sh is a thin, non-interactive wrapper ───────────────────────────
INST="$REPO_ROOT/install.sh"
t_assert_grep "install.sh forces unattended mode" 'DEVMKDE_ASSUME_YES=1' "$INST"
t_assert_grep "install.sh defaults to --full"    '--full'              "$INST"
t_assert_grep "install.sh appends --verify"     '--verify'            "$INST"
t_assert_grep "install.sh documents DEVMKDE_PRIV" 'DEVMKDE_PRIV'       "$INST"
if sed -e 's/[[:space:]]*#.*$//' "$INST" | grep -qE '(^|[;&|(])sudo[[:space:]]'; then
    t_fail "install.sh invokes bare sudo"
else
    t_ok
fi

# ── both entry points are executable ───────────────────────────────────────
t_assert "run.sh is executable"    test -x "$RUN"
t_assert "install.sh is executable" test -x "$INST"

# ─--help exits 0 and prints usage ───────────────────────────────────────────
t_assert "run.sh --help exits 0"    bash -c "\"$RUN\" --help >/dev/null 2>&1"
t_assert "install.sh --help exits 0" bash -c "\"$INST\" --help >/dev/null 2>&1"

t_summary "unit/runner"