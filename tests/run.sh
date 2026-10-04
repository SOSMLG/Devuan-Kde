#!/usr/bin/env bash
# tests/run.sh — the whole suite. Three tiers, all read-only.
#
# Read-only means read-only: no root, no apt mutation, no X, no network, and
# nothing written outside /tmp. Each tier is a separate script so a failure in
# one still lets the others run and report.
#
#   tier 1  lint         bash -n, shellcheck if present, unsafe-bracket guard
#   tier 2  unit         sandboxed: privilege helpers, theme engine, runner
#   tier 3  consistency  cross-file invariants
#           apt-checks   read-only package existence against the local cache
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

RC=0
declare -a SUMMARY=()

run_tier() {
    local name="$1" script="$2"
    echo
    echo "══════════════════════════════════════════════════════════════"
    echo "  $name"
    echo "══════════════════════════════════════════════════════════════"
    if [ ! -f "$script" ]; then
        echo "  MISSING: $script"
        SUMMARY+=("$name: MISSING")
        RC=1
        return
    fi
    local out rc
    out="$(bash "$script" 2>&1)"; rc=$?
    printf '%s\n' "$out"
    if [ "$rc" -ne 0 ]; then
        SUMMARY+=("$name: FAIL (rc=$rc)")
        RC=1
    else
        SUMMARY+=("$name: pass")
    fi
}

echo "Devuan KDE test suite — $(tr -d '[:space:]' < VERSION 2>/dev/null || echo '?')"
echo "repo: $REPO_ROOT"
echo "host: $(uname -sr)"

run_tier "tier 1 · lint"         "$SCRIPT_DIR/lint.sh"
run_tier "tier 2 · unit"         "$SCRIPT_DIR/unit/run.sh"
run_tier "tier 3 · consistency"  "$SCRIPT_DIR/consistency.sh"
run_tier "tier 3 · apt-checks"   "$SCRIPT_DIR/apt-checks.sh"

echo
echo "══════════════════════════════════════════════════════════════"
echo "  summary"
echo "══════════════════════════════════════════════════════════════"
for s in "${SUMMARY[@]}"; do echo "  $s"; done
echo
if [ "$RC" -eq 0 ]; then
    echo "ALL TIERS PASSED"
else
    echo "SOME TIERS FAILED"
fi
exit "$RC"