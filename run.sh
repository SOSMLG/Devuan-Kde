#!/usr/bin/env bash
# ==========================================
# 🧩  Devuan/Debian KDE Setup — Ordered Runner
# -------------------------------------------------------
# Runs the toolkit's step scripts in numeric order, asking Y/N per
# script with the default declared by the script itself.
#
# Step discovery is automatic: every scripts/[0-9]*.sh file is a step,
# and it carries its own metadata in three header lines:
#
#   # DEVMKDE_DESC: one-line description shown by --list and at run time
#   # DEVMKDE_DEFAULT: Y|N         — what --yes answers
#   # DEVMKDE_PHASE: core|sysmgmt|optional|standalone
#
# The numeric prefix is the ordering. It also names the phase band:
# 1x = core, 3x = sysmgmt, 4x = optional, 5x = standalone (not run here).
# `standalone` steps are deliberately excluded from a normal run — they are
# maintenance utilities you invoke by hand.
# ==========================================

set -uo pipefail
# NOTE: intentionally not using `set -e` here. Individual scripts manage
# their own error handling; one script failing should not silently abort
# every later step (you'd lose the touchpad fix because Firefox's download
# timed out, etc). Each script is still expected to exit non-zero on
# failure so this runner can report it.

# --- Colors ---
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
CYAN="\033[0;36m"
RESET="\033[0m"

# --- Directory setup ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"

# run.sh never sources scripts/lib/common.sh so it stays usable even when a
# script's lib is broken mid-refactor; it keeps a local priv() with the same
# contract as the shared helper: sudo first, doas fallback, DEVMKDE_PRIV wins.
priv() {
    if [ -n "${DEVMKDE_PRIV:-}" ]; then
        "$DEVMKDE_PRIV" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        doas "$@"
    else
        echo -e "${RED}No privilege-escalation tool found (tried DEVMKDE_PRIV, sudo, doas).${RESET}" >&2
        return 127
    fi
}

usage() {
    cat <<EOF
Usage: $0 [options]

Runs the toolkit's step scripts in numeric order, asking Y/N per script.
Options:

  --list                Print each step (order, script, phase, description,
                        default) and exit.
  --only a,b            Run only the listed steps, in their defined order.
                        Accepts the filename with or without '.sh', and with
                        or without the numeric prefix (both 'kdeDebloat' and
                        '12-kdeDebloat' resolve to 12-kdeDebloat.sh).
  --phase sec1,sec2     Run only whole phases (core, sysmgmt, optional).
  --full                Run every step in order (the default). Explicit so a
                        wrapper like install.sh can be self-documenting.
  --yes, -y             Answer every prompt with its default (unattended).
  --no-update           Skip the runner's single 'apt-get update' (scripts also
                        skip their own refreshes). Set automatically if apt fails.
  --verify              After the run, run scripts/verifySetup.sh and report results.
  -h, --help            Show this help.

Phases: core (1x, runs by default) | sysmgmt (3x) | optional (4x)
Standalone utilities (5x) are never run by this runner — invoke them directly,
e.g. 'bash scripts/50-configBackup.sh backup'. See --list-utilities.
EOF
}

# --- Flags -----------------------------------------------------------------
DO_LIST=0
DO_LIST_UTILS=0
DO_VERIFY=0
ASSUME_YES=0
SKIP_APT_UPDATE=0
ONLY_NAMES=()
PHASE_NAMES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --list) DO_LIST=1 ;;
        --list-utilities) DO_LIST_UTILS=1 ;;
        --only)
            [ $# -ge 2 ] || { echo -e "${RED}--only needs a comma-separated list of steps.${RESET}"; exit 1; }
            shift
            IFS=',' read -ra _entries <<< "$1"
            ONLY_NAMES+=("${_entries[@]}")
            ;;
        --phase)
            [ $# -ge 2 ] || { echo -e "${RED}--phase needs a comma-separated list of phases (core, sysmgmt, optional).${RESET}"; exit 1; }
            shift
            IFS=',' read -ra _entries <<< "$1"
            PHASE_NAMES+=("${_entries[@]}")
            ;;
        --full) PHASE_NAMES=() ;;
        --yes|-y) ASSUME_YES=1 ;;
        --no-update|--skip-apt-update) SKIP_APT_UPDATE=1 ;;
        --verify) DO_VERIFY=1 ;;
        -h|--help) usage; exit 0 ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            usage
            exit 1
            ;;
    esac
    shift
done

[ "$ASSUME_YES" -eq 1 ] && export DEVMKDE_ASSUME_YES=1

# --- Refuse to run as root directly ---
# Per-user state (Firefox profile, ~/.bashrc, KDE configs, ~/.local/bin)
# must land in the real user's $HOME, not /root. Scripts escalate
# themselves for the bits that need it.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "${RED}Please run this as your normal user, not as root / sudo bash run.sh.${RESET}"
    echo -e "${YELLOW}Each script will escalate itself for the parts that need it.${RESET}"
    exit 1
fi

# --- Distro check (Devuan or Debian; both ship /etc/debian_version) ---
if [ -f /etc/devuan_version ]; then
    echo -e "${GREEN}Devuan detected: $(cat /etc/devuan_version)${RESET}"
elif [ -f /etc/debian_version ]; then
    echo -e "${GREEN}Debian-based system detected: $(cat /etc/debian_version)${RESET}"
else
    echo -e "${YELLOW}Warning: this toolkit targets Devuan/Debian. Your system may not be compatible.${RESET}"
    if [ -z "${DEVMKDE_ASSUME_YES:-}" ]; then
        read -r -p "Continue anyway? (y/N): " continue_anyway
        [[ "$continue_anyway" =~ ^[Yy]$ ]] || exit 1
    fi
fi

# --- Step metadata, read from each script's own header ----------------------
# step_meta <file> <FIELD> -> value (empty string if the header is missing)
step_meta() {
    grep -m1 "^# DEVMKDE_$2:" "$1" 2>/dev/null | sed "s/^# DEVMKDE_$2:[[:space:]]*//"
}

# Every numbered script is a step. Populate STEP_FILES in numeric order.
STEP_FILES=()
STEP_DESC=()
STEP_DEFAULT=()
STEP_PHASE=()

while IFS= read -r f; do
    [ -n "$f" ] || continue
    STEP_FILES+=("$(basename "$f")")
    STEP_DESC+=("$(step_meta "$f" DESC)")
    STEP_DEFAULT+=("$(step_meta "$f" DEFAULT)")
    STEP_PHASE+=("$(step_meta "$f" PHASE)")
done < <(find "$SCRIPTS_DIR" -maxdepth 1 -type f -name '[0-9]*.sh' | sort)

if [ "${#STEP_FILES[@]}" -eq 0 ]; then
    echo -e "${RED}No steps found in $SCRIPTS_DIR (expected scripts/[0-9]*.sh).${RESET}"
    exit 1
fi

# Phase (--phase) names must be valid. 'standalone' is a real phase value but
# is never selectable here: 5x utilities are run by hand.
RUNNABLE_PHASES=(core sysmgmt optional)
declare -A SECTIONS_OK=([core]=1 [sysmgmt]=1 [optional]=1)
if [ "${#PHASE_NAMES[@]}" -gt 0 ]; then
    for p in "${PHASE_NAMES[@]}"; do
        if [ -z "${SECTIONS_OK[$p]:-}" ]; then
            echo -e "${RED}Unknown --phase section: $p (valid: core, sysmgmt, optional).${RESET}"
            exit 1
        fi
    done
fi

# is_runnable_phase <phase> -> 0 when the phase belongs in a normal run
is_runnable_phase() {
    case "$1" in
        core|sysmgmt|optional) return 0 ;;
        *) return 1 ;;
    esac
}

# --- --list / --list-utilities: print and exit -----------------------------
if [ "$DO_LIST" -eq 1 ] || [ "$DO_LIST_UTILS" -eq 1 ]; then
    [ "$DO_LIST_UTILS" -eq 1 ] && echo -e "${BLUE}Standalone utilities (not run by this runner):${RESET}\n" \
                              || echo -e "${BLUE}Toolkit steps, in run order:${RESET}\n"
    i=1
    for idx in "${!STEP_FILES[@]}"; do
        # --list shows runnable phases; --list-utilities shows standalone.
        if [ "$DO_LIST_UTILS" -eq 1 ]; then
            is_runnable_phase "${STEP_PHASE[$idx]}" && continue
        else
            is_runnable_phase "${STEP_PHASE[$idx]}" || continue
        fi
        printf '  %2d.  %-30s [%-9s] default: %-1s  %s\n' \
            "$i" "${STEP_FILES[$idx]}" "${STEP_PHASE[$idx]}" "${STEP_DEFAULT[$idx]:-N}" "${STEP_DESC[$idx]}"
        ((i++))
    done
    echo
    if [ "$DO_LIST_UTILS" -eq 1 ]; then
        echo -e "Run one by hand: ${CYAN}bash scripts/50-configBackup.sh backup${RESET}"
    else
        echo -e "Run everything:   ${CYAN}./run.sh --full${RESET}"
        echo -e "Pick a subset:    ${CYAN}./run.sh --only kdeDebloat,usefulApps${RESET}"
        echo -e "Pick a phase:     ${CYAN}./run.sh --phase core   (phases: core, sysmgmt, optional)${RESET}"
        echo -e "Fully unattended: ${CYAN}./run.sh --yes --full${RESET}"
        echo -e "Manual utilities: ${CYAN}./run.sh --list-utilities${RESET}"
    fi
    exit 0
fi

# --- Phase (--phase) filter -------------------------------------------------
BASE_IDX=()
if [ "${#PHASE_NAMES[@]}" -gt 0 ]; then
    for idx in "${!STEP_FILES[@]}"; do
        for p in "${PHASE_NAMES[@]}"; do
            [ "${STEP_PHASE[$idx]}" = "$p" ] && BASE_IDX+=("$idx")
        done
    done
else
    for idx in "${!STEP_FILES[@]}"; do
        is_runnable_phase "${STEP_PHASE[$idx]}" && BASE_IDX+=("$idx")
    done
fi

SELECTED=()
if [ "${#ONLY_NAMES[@]}" -gt 0 ]; then
    # Accept 'name', 'name.sh', '10-name' or '10-name.sh' for each request, and
    # report anything that doesn't resolve against the phase-filtered set.
    declare -A WANTED
    for n in "${ONLY_NAMES[@]}"; do
        [ -z "$n" ] && continue
        n="${n%.sh}"
        WANTED["$n"]=1
    done
    unset n
    for idx in "${BASE_IDX[@]}"; do
        stem="${STEP_FILES[$idx]%.sh}"
        short="${stem#*-}"
        if [ -n "${WANTED[$stem]+x}" ]; then
            SELECTED+=("$idx")
            unset "WANTED[$stem]"
        elif [ "$short" != "$stem" ] && [ -n "${WANTED[$short]+x}" ]; then
            SELECTED+=("$idx")
            unset "WANTED[$short]"
        fi
    done
    unset stem short
    for leftover in "${!WANTED[@]}"; do
        echo -e "${YELLOW}⚠ Not a toolkit step in the selected phase(s), ignoring: $leftover${RESET}"
    done
    unset leftover
    if [ "${#SELECTED[@]}" -eq 0 ]; then
        echo -e "${RED}No matching steps for --only. Use --list to see available ones.${RESET}"
        exit 1
    fi
else
    SELECTED=("${BASE_IDX[@]}")
fi

echo -e "${BLUE}=========================================================${RESET}"
echo -e "${BLUE}   Devuan/Debian KDE Setup${RESET}"
echo -e "${BLUE}=========================================================${RESET}\n"

# --- Session-type notice ---------------------------------------------------
# Plasma 6.8 drops the X11 session entirely (6.7 is the last X11 release).
# Warn on X11 so the choice is deliberate, but run either way.
# NOTE: two separate [ ] tests, never `[ -n "$x" && "$x" = y ]` — bash's [
# builtin in this environment rejects that form with "missing ]".
if [ -n "${XDG_SESSION_TYPE:-}" ] && [ "${XDG_SESSION_TYPE:-}" = "x11" ]; then
    echo -e "${YELLOW}[!] This is an X11 session. Plasma 6.8 will be Wayland-only — see"
    echo -e "    33-plasmaPerformance.sh for the migration checklist.${RESET}\n"
fi

# --- One apt refresh, then let the scripts skip their own ------------------
# Scripts call apt_update(), which is a no-op when DEVMKDE_SKIP_APT_UPDATE
# is set — so we refresh exactly once up front instead of ~13 times.
export DEVMKDE_SKIP_APT_UPDATE=1
if [ "$SKIP_APT_UPDATE" -eq 0 ]; then
    echo -e "${CYAN}[*] Refreshing package lists once (scripts will skip their own refreshes)...${RESET}"
    if ! priv apt-get update; then
        echo -e "${YELLOW}[!] apt-get update failed — continuing anyway. Some installs may fail if lists are stale.${RESET}"
    fi
fi

# --- Summary log -----------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devuan-kde-setup"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/last-run.log"
record_run() { printf '%(%F %T)T  %s\n' -1 "$1" >> "$LOG_FILE"; }

record_run "$0 ${ONLY_NAMES[*]:-${PHASE_NAMES[*]:-full}} (assume-yes=${ASSUME_YES:-0}, skip-apt=${SKIP_APT_UPDATE:-0})"

FAILED=()
SKIPPED=()

for idx in "${SELECTED[@]}"; do
    SCRIPT="${STEP_FILES[$idx]}"
    DESC="${STEP_DESC[$idx]}"
    DEFAULT="${STEP_DEFAULT[$idx]:-N}"
    SCRIPT_PATH="$SCRIPTS_DIR/$SCRIPT"

    echo -e "${YELLOW}▶ ${SCRIPT}${RESET}"
    echo -e "   ${CYAN}${DESC}${RESET}"

    if [ ! -f "$SCRIPT_PATH" ]; then
        echo -e "${RED}   ❌ Script not found: $SCRIPT_PATH${RESET}\n"
        FAILED+=("$SCRIPT (missing)")
        record_run "$SCRIPT  missing"
        continue
    fi

    DEFAULT=${DEFAULT^^}
    PROMPT="   ➤ Run this script? (y/N): "
    [ "$DEFAULT" = "Y" ] && PROMPT="   ➤ Run this script? (Y/n): "

    if [ -n "${DEVMKDE_ASSUME_YES:-}" ]; then
        ANSWER="$DEFAULT"
        echo -e "${CYAN}   (unattended) → ${ANSWER}${RESET}"
    else
        read -rp "$PROMPT" ANSWER
        ANSWER=${ANSWER:-$DEFAULT}
    fi
    echo

    case "${ANSWER^^}" in
        Y)
            echo -e "${GREEN}   ✅ Running $SCRIPT...${RESET}"
            if bash "$SCRIPT_PATH"; then
                echo -e "${GREEN}   ✅ Done: $SCRIPT${RESET}\n"
                record_run "$SCRIPT  ok"
            else
                echo -e "${RED}   ❌ $SCRIPT exited with an error (continuing with the rest)${RESET}\n"
                FAILED+=("$SCRIPT")
                record_run "$SCRIPT  failed"
            fi
            ;;
        *)
            echo -e "${YELLOW}   ⚠ Skipped: $SCRIPT${RESET}\n"
            SKIPPED+=("$SCRIPT")
            record_run "$SCRIPT  skipped"
            ;;
    esac
done

# --- --verify: end-state audit --------------------------------------------
if [ "$DO_VERIFY" -eq 1 ]; then
    VERIFY_PATH="$SCRIPTS_DIR/verifySetup.sh"
    if [ -f "$VERIFY_PATH" ]; then
        echo -e "${BLUE}=========================================================${RESET}"
        echo -e "${BLUE}   🔍 Verifying setup...${RESET}"
        echo -e "${BLUE}=========================================================${RESET}\n"
        if bash "$VERIFY_PATH"; then
            record_run "verify  ok"
        else
            record_run "verify  issues"
        fi
    else
        echo -e "${YELLOW}⚠ verifySetup.sh not found — skipping --verify.${RESET}"
    fi
fi

echo -e "${BLUE}=========================================================${RESET}"
echo -e "${BLUE}   🏁 All tasks processed.${RESET}"
echo -e "${BLUE}=========================================================${RESET}"

if [ "${#SKIPPED[@]}" -gt 0 ]; then
    echo -e "${YELLOW}Skipped: ${SKIPPED[*]}${RESET}"
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
    echo -e "${RED}Failed:  ${FAILED[*]}${RESET}"
    echo -e "${YELLOW}Re-run individual scripts directly with: bash scripts/<name>.sh${RESET}"
    record_run "result  failed"
    exit 1
fi

echo -e "${GREEN}Done. A logout/reboot is recommended (group membership + KDE service changes).${RESET}"
record_run "result  ok"
echo -e "${CYAN}Full log: $LOG_FILE${RESET}"
