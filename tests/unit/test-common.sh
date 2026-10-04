#!/usr/bin/env bash
# tests/unit/test-common.sh — tier 2: lib/common.sh unit tests.
#
# Sandbox rules: no root, no apt, no X, no network.
#
# Two structural notes, both learned the hard way:
#
#  1. The fake sudo/doas are named exactly `sudo` / `doas` because that is
#     what _priv_resolve probes for, and PATH contains ONLY the sandbox bin
#     dir — no /usr/bin. Naming them anything else (or leaving /usr/bin on
#     PATH) means the host's real sudo is still visible and a removed fake
#     silently falls through to it, so the test passes for the wrong reason.
#
#  2. Assertions run in THIS shell, not a `( ... )` subshell. t_ok/t_fail
#     mutate counters, and a subshell's mutations die with it — every
#     assertion inside one would be discarded and the summary would report
#     0/0. PATH and PRIV_BIN are mutated directly instead, which is safe
#     because they are read at call time.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=../lib/test-helpers.sh
. "$SCRIPT_DIR/../lib/test-helpers.sh"

SANDBOX="$(make_tmp devmkde-common)"

BIN="$SANDBOX/bin"
mkdir -p "$BIN"
# awk and mkdir are here for ini_set_key (awk does the INI read-back, mkdir
# creates its scratch dirs) and for the assertions below. Both are symlinked to
# the real binary like the rest, so they behave normally; the point of the list
# is that the sandbox PATH resolves nothing outside it.
for tool in env bash sh sed grep cat cp mv rm chmod mktemp id getent date tr cut awk mkdir dirname; do
    p="$(command -v "$tool" 2>/dev/null)"
    [ -n "$p" ] && ln -sf "$p" "$BIN/$tool"
done

# printf, NOT echo: `echo "$@"` with a leading -n is `echo -n ...`, and bash's
# echo swallows -n as its own "no trailing newline" flag. Since priv_n() sends
# exactly a leading -n, an echo-based fake logs "true" and the assertion fails
# for a reason that has nothing to do with the code under test.
cat > "$BIN/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${FAKE_PRIV_LOG:?}"
exit 0
EOF
cp "$BIN/sudo" "$BIN/doas"
chmod +x "$BIN/sudo" "$BIN/doas"

export FAKE_PRIV_LOG="$SANDBOX/priv.log"
: > "$FAKE_PRIV_LOG"

# Hermetic PATH from here on.
PATH="$BIN"
export PATH
unset DEVMKDE_PRIV 2>/dev/null || true

# shellcheck source=/dev/null
. "$REPO_ROOT/scripts/lib/common.sh"

# ── 1. sudo-first is the locked decision ───────────────────────────────────
PRIV_BIN=""
if _priv_resolve >/dev/null 2>&1; then
    t_assert_eq "priv: prefers sudo when both present" "sudo" "$PRIV_BIN"
else
    t_fail "priv: _priv_resolve failed with both fakes present"
fi

# ── 2. doas fallback when sudo is absent ───────────────────────────────────
mv "$BIN/sudo" "$BIN/sudo.off"
PRIV_BIN=""
if _priv_resolve >/dev/null 2>&1; then
    t_assert_eq "priv: falls back to doas without sudo" "doas" "$PRIV_BIN"
else
    t_fail "priv: _priv_resolve failed with only doas present"
fi
mv "$BIN/sudo.off" "$BIN/sudo"

# ── 3. DEVMKDE_PRIV override wins over auto-detection ──────────────────────
PRIV_BIN=""
DEVMKDE_PRIV=doas
PRIV_BIN=""
_priv_resolve >/dev/null 2>&1
t_assert_eq "priv: DEVMKDE_PRIV overrides auto-detect" "doas" "$PRIV_BIN"
unset DEVMKDE_PRIV

# ── 4. a bad override is REJECTED, not silently ignored ────────────────────
PRIV_BIN=""
DEVMKDE_PRIV=definitely-not-installed
_priv_resolve >/dev/null 2>&1
rc=$?
t_assert_eq "priv: bad DEVMKDE_PRIV fails" "1" "$rc"
unset DEVMKDE_PRIV

# ── 5. neither tool present: clean failure, never a half-run command ───────
mv "$BIN/sudo" "$BIN/sudo.off"; mv "$BIN/doas" "$BIN/doas.off"
PRIV_BIN=""
_priv_resolve >/dev/null 2>&1
t_assert_eq "priv: no escalation tool fails" "1" "$?"
: > "$FAKE_PRIV_LOG"
PRIV_BIN=""
priv echo should-not-run >/dev/null 2>&1
if [ -s "$FAKE_PRIV_LOG" ]; then
    t_fail "priv: ran something even though no escalation tool exists"
else
    t_ok
fi
mv "$BIN/sudo.off" "$BIN/sudo"; mv "$BIN/doas.off" "$BIN/doas"

# ── 6. argv passthrough, including -n and -u ──────────────────────────────
PRIV_BIN=""
_priv_resolve >/dev/null 2>&1

: > "$FAKE_PRIV_LOG"
priv echo hello world >/dev/null 2>&1
t_assert_grep "priv: passes argv through" '^echo hello world$' "$FAKE_PRIV_LOG"

: > "$FAKE_PRIV_LOG"
priv_n true >/dev/null 2>&1
t_assert_grep "priv_n: sends -n (non-interactive)" '^-n true$' "$FAKE_PRIV_LOG"

: > "$FAKE_PRIV_LOG"
priv_as nobody id -un >/dev/null 2>&1
t_assert_grep "priv_as: sends -u <user>" '^-u nobody id -un$' "$FAKE_PRIV_LOG"

# ── 7. run_as_user must not escalate when we ARE $ACTUAL_USER ─────────────
# Otherwise every single theme write escalates for nothing.
: > "$FAKE_PRIV_LOG"
ACTUAL_USER="$(id -un)"
run_as_user true >/dev/null 2>&1
if [ -s "$FAKE_PRIV_LOG" ]; then
    t_fail "run_as_user: escalated even though we are already \$ACTUAL_USER"
else
    t_ok
fi

# ── 8. init_system only ever returns a known value ─────────────────────────
case "$(init_system)" in
    systemd|openrc|sysvinit|unknown) t_ok ;;
    *) t_fail "init_system returned an unexpected value: $(init_system)" ;;
esac

# ── 9. ask() honours DEVMKDE_ASSUME_YES by taking the default ──────────────
DEVMKDE_ASSUME_YES=1
if ask "default-yes question" Y; then t_ok; else t_fail "ask: default Y should be true"; fi
if ask "default-no question" N; then t_fail "ask: default N should be false"; else t_ok; fi
unset DEVMKDE_ASSUME_YES

# ── 10. ask() at EOF must not flip a default-N prompt to yes ──────────────
# The bug this pins: `./run.sh --only x | head` hands every script a closed
# stdin; `read` returns instantly empty and the default is taken silently.
if ask "eof question" N </dev/null 2>/dev/null; then
    t_fail "ask at EOF with default N returned true"
else
    t_ok
fi

# ── 11. ini_set_key writes, verifies, and preserves its neighbours ─────────
# The bug this pins: kwriteconfig6 exits 0 and writes NOTHING for
# `kcminputrc [Mouse] cursorTheme` on Plasma 6.3, so the cursor was never
# applied and nothing errored. ini_set_key is the fallback that actually works,
# and it must confirm the value landed rather than trust an exit code.
INI_DIR="$SANDBOX/ini"
mkdir -p "$INI_DIR"
INI="$INI_DIR/kcminputrc"
printf '[Mouse]\nX11LibInputXAccelProfileFlat=true\n' > "$INI"

if ini_set_key "$INI" Mouse cursorTheme Bibata-Modern-Ice; then t_ok
else t_fail "ini_set_key: setting a new key in an existing group"; fi

# Neighbouring keys in the same group must survive.
if grep -q '^X11LibInputXAccelProfileFlat=true$' "$INI"; then t_ok
else t_fail "ini_set_key: clobbered an existing key in the same group"; fi

# Overwrite in place, no duplicate key left behind.
if ini_set_key "$INI" Mouse cursorTheme Other-Theme; then t_ok
else t_fail "ini_set_key: overwriting an existing key"; fi
if [ "$(grep -c '^cursorTheme=' "$INI")" -eq 1 ]; then t_ok
else t_fail "ini_set_key: left a duplicate cursorTheme key"; fi

# Idempotent: same value twice must still verify.
if ini_set_key "$INI" Mouse cursorTheme Other-Theme; then t_ok
else t_fail "ini_set_key: re-setting the same value should verify"; fi

# A brand new group is appended, existing content untouched.
if ini_set_key "$INI" General newKey val2; then t_ok
else t_fail "ini_set_key: creating a new group"; fi
if grep -q '^cursorTheme=Other-Theme$' "$INI"; then t_ok
else t_fail "ini_set_key: new group lost the previous group"; fi

# Values containing spaces are not truncated or mis-split.
if ini_set_key "$INI" General spaced "two words"; then t_ok
else t_fail "ini_set_key: value with spaces"; fi

# A file that does not exist yet is created with its group header.
INI_NEW="$INI_DIR/does-not-exist-yet"
if ini_set_key "$INI_NEW" Mouse cursorTheme Some-Theme; then t_ok
else t_fail "ini_set_key: creating a missing file"; fi

# It must FAIL when it cannot achieve what it promised, otherwise callers that
# branch on the return value would report a change that never happened. A path
# whose parent component is a regular file can never be created.
printf 'not a directory\n' > "$INI_DIR/a-file"
if ini_set_key "$INI_DIR/a-file/kcminputrc" Mouse cursorTheme Some-Theme; then
    t_fail "ini_set_key: reported success for an unwritable target"
else
    t_ok
fi

# An empty value is a legitimate "clear this key", and must still verify.
if ini_set_key "$INI" Mouse cursorTheme "" && grep -q '^cursorTheme=$' "$INI"; then t_ok
else t_fail "ini_set_key: could not write/verify an empty value"; fi

t_summary "unit/common"