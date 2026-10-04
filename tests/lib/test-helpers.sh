#!/usr/bin/env bash
# test-helpers.sh — tiny assertion + result-tracking helpers shared by the
# tests/*.sh tier scripts and tests/unit/*.sh unit tests. Not standalone;
# source it and call t_summary at the end.
#
#   t_ok / t_fail             record a result
#   t_assert "desc" cmd...    pass iff cmd exits 0
#   t_assert_eq desc a b      pass iff a == b
#   t_assert_grep desc pat f  pass iff f matches regex pat
#   t_assert_not_grep ...     pass iff f does NOT match pat
#   command_available name    pass iff tool exists (else fail)
#   make_tmp / cleanup_dirs    guarded temp-dir helpers
#   t_summary [label]         print totals; exit non-zero on any failure

: "${T_RUN=1}"   # harness may set this; default to standalone behaviour

T_TOTAL=0
T_FAILED=0
T_FAILURES=()

t_ok() { T_TOTAL=$((T_TOTAL + 1)); }

t_fail() {
    T_TOTAL=$((T_TOTAL + 1))
    T_FAILED=$((T_FAILED + 1))
    T_FAILURES+=("$1")
    printf '[FAIL] %s\n' "$1"
}

t_assert() {
    local desc="$1"; shift
    if "$@" >/dev/null 2>&1; then
        t_ok
    else
        t_fail "$desc"
    fi
}

t_assert_eq() {
    local desc="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        t_ok
    else
        t_fail "$desc (expected '$expected', got '$actual')"
    fi
}

# t_assert_grep "desc" pattern [file|-] — file "-" reads stdin
t_assert_grep() {
    local desc="$1" pattern="$2" file="${3:--}"
    if [ "$file" = "-" ]; then
        if grep -qE -- "$pattern"; then
            t_ok
        else
            t_fail "$desc (pattern '$pattern' not found on stdin)"
        fi
    elif [ -f "$file" ] && grep -qE -- "$pattern" "$file"; then
        t_ok
    else
        t_fail "$desc (pattern '$pattern' not found in $file)"
    fi
}

# t_assert_not_grep "desc" pattern [file|-]
t_assert_not_grep() {
    local desc="$1" pattern="$2" file="${3:--}"
    if [ "$file" = "-" ]; then
        if ! grep -qE -- "$pattern"; then
            t_ok
        else
            t_fail "$desc (pattern '$pattern' unexpectedly on stdin)"
        fi
    elif [ -f "$file" ] && ! grep -qE -- "$pattern" "$file"; then
        t_ok
    else
        t_fail "$desc (pattern '$pattern' unexpectedly in $file)"
    fi
}

command_available() {
    if command -v "$1" >/dev/null 2>&1; then
        t_ok
        return 0
    fi
    t_fail "missing tool: $1"
    return 1
}

make_tmp() {
    mktemp -d "/tmp/${1:-tests}.XXXXXX"
}

cleanup_dirs() {
    local d
    for d in "$@"; do
        case "$d" in
            /tmp/*) rm -rf "$d" ;;
            *) t_fail "refusing to remove non-/tmp path: $d" ;;
        esac
    done
}

t_summary() {
    local label="${1:-tests}"
    echo
    echo "== $label: $((T_TOTAL - T_FAILED))/$T_TOTAL passed =="
    if [ "$T_FAILED" -gt 0 ]; then
        local f
        for f in "${T_FAILURES[@]}"; do printf '    - %s\n' "$f"; done
        exit 1
    fi
    exit 0
}