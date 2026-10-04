#!/usr/bin/env bash
# tests/unit/run.sh — tier 2 driver. Runs every tests/unit/test-*.sh in a
# subshell and aggregates pass/fail.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOTAL=0
FAILED=0
FAILED_LIST=()

for t in "$SCRIPT_DIR"/test-*.sh; do
    [ -f "$t" ] || continue
    name="$(basename "$t")"
    echo "  [unit] $name"
    # Each test script ends in t_summary, which exits non-zero on failure.
    if bash "$t"; then
        TOTAL=$((TOTAL + 1))
    else
        TOTAL=$((TOTAL + 1))
        FAILED=$((FAILED + 1))
        FAILED_LIST+=("$name")
    fi
done

echo
echo "== unit: $((TOTAL - FAILED))/$TOTAL test files passed =="
if [ "$FAILED" -gt 0 ]; then
    for f in "${FAILED_LIST[@]}"; do printf '    - %s\n' "$f"; done
    exit 1
fi
exit 0