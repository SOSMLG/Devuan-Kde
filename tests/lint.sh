#!/usr/bin/env bash
# tests/lint.sh — tier 1: syntax + static checks (all read-only, no root).
#
# 1. bash -n         — every .sh file in the repo
# 2. shellcheck -x -S warning — if present (skippable via DEVKDE_TESTS_NO_SHELLCHECK)
# 3. the bash `[ -n "$x" && "$x" = y ]` trap — see below
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$REPO_ROOT"

# shellcheck source=lib/test-helpers.sh
. "$SCRIPT_DIR/lib/test-helpers.sh"

BAD=0

# ── 1. bash -n (syntax) ─────────────────────────────────────────────────────
echo "  [lint] bash -n ..."

mapfile -t SH_FILES < <(find . \
    \( -path './.git' -o -path './iso/rootfs' \) \
    -prune -o -type f -name '*.sh' -print \
    | sort)

for f in "${SH_FILES[@]}"; do
    t_assert "bash -n $f" bash -n "$f"
done

# ── 2. shellcheck ───────────────────────────────────────────────────────────
SKIP_SC="${DEVKDE_TESTS_NO_SHELLCHECK:-0}"
if [ "$SKIP_SC" -eq 1 ] || ! command -v shellcheck >/dev/null 2>&1; then
    if [ "$SKIP_SC" -eq 1 ]; then
        echo "  [lint] shellcheck skipped (DEVKDE_TESTS_NO_SHELLCHECK=1)"
    else
        echo "  [lint] shellcheck not installed, skipped (apt-get install shellcheck)"
    fi
    t_ok   # absence is not a failure
    t_ok
else
    echo "  [lint] shellcheck ..."
    if [ "${#SH_FILES[@]}" -gt 0 ]; then
        t_assert "shellcheck -x -S warning" shellcheck -x -S warning "${SH_FILES[@]}"
    fi
fi

# ── 3. The `[ -n "$x" && "$x" = y ]` trap ─────────────────────────────────
# This is not a style nit. bash's `[` builtin in this environment REJECTS the
# combined form and exits with "[: missing ]":
#
#     $ [ -n "x11" && "x11" = "x11" ] && echo yes
#     bash: line 1: [: missing `]'
#
# and the `if ...; then` still runs the body, so the guard silently does the
# wrong thing. It cost a real debugging cycle in run.sh, so it gets a guard:
# the correct form is two separate `[ ]` tests. Catch it everywhere at once.
#
# Comments are stripped first — this file, and run.sh, both have to *name* the
# bad form in prose to explain why it's banned.
echo "  [lint] single-bracket && conjunction guard ..."
BRACKET_TRAP=0
while IFS= read -r f; do
    if sed -e 's/[[:space:]]*#.*$//' "$f" | grep -nE '\[[^]]*-n [^]]*&&' >/dev/null 2>&1; then
        t_fail "single-[ '&&' conjunction (bash rejects it): $f"
        BRACKET_TRAP=1
    fi
done < <(find scripts -type f -name '*.sh' | sort; echo run.sh; echo install.sh)
[ "$BRACKET_TRAP" -eq 0 ] && t_ok
echo "      (comment lines stripped before matching)"

# ── 4. every step script sources lib/common.sh if it uses shared helpers ───
# A script that calls priv/ask/log_* without sourcing common.sh dies at the
# first call with "command not found" — after apt has already been touched.
echo "  [lint] shared-helper sourcing ..."
SHARED='\b(priv|priv_n|priv_as|require_priv|ask|install_pkgs|install_deb_file|purge_if_installed|apt_update|kwrite_user|is_installed|log_info|log_ok|log_warn|log_err|run_as_user|command_exists|init_system|start_service|sha256_verify|bind_global_shortcut)\b'
UNSOURCED=""
while IFS= read -r f; do
    grep -qE "$SHARED" "$f" || continue
    grep -qE 'lib/common\.sh' "$f" || UNSOURCED="$UNSOURCED $f"
done < <(find scripts -maxdepth 1 -type f -name '*.sh' | sort)

if [ -n "$UNSOURCED" ]; then
    for f in $UNSOURCED; do
        t_fail "uses shared helpers but doesn't source lib/common.sh: $f"
    done
else
    t_ok
fi

echo
t_summary "lint"