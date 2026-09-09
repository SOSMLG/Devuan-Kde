#!/usr/bin/env bash
# ==========================================
# 🧩  Devuan/Debian KDE Setup — Ordered Runner
# Runs setup scripts in the order defined below,
# asks Y/N per script with a default value.
# Same pattern as DebianSway's run.sh.
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

usage() {
    cat <<EOF
Usage: $0 [options]

Runs the toolkit's setup scripts in the order defined below, asking Y/N
per script. Options:

  --list                Print each script (order, description, default) and exit.
  --only a.sh,b.sh      Run only the listed scripts, in their defined order.
                        Accepts filenames with or without the '.sh' suffix.
  --yes, -y             Answer every prompt with its default (unattended).
  --no-update           Skip the runner's single 'apt-get update' (scripts also skip
                        their own refreshes). Set automatically if apt fails.
  --verify              After the run, run scripts/verifySetup.sh and report results.
  -h, --help            Show this help.
EOF
}

# --- Flags -----------------------------------------------------------------
DO_LIST=0
DO_VERIFY=0
ASSUME_YES=0
SKIP_APT_UPDATE=0
ONLY_NAMES=()

while [ $# -gt 0 ]; do
    case "$1" in
        --list) DO_LIST=1 ;;
        --only)
            [ $# -ge 2 ] || { echo -e "${RED}--only needs a comma-separated list of scripts.${RESET}"; exit 1; }
            shift
            IFS=',' read -ra _entries <<< "$1"
            ONLY_NAMES+=("${_entries[@]}")
            ;;
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
# must land in the real user's $HOME, not /root. Scripts call sudo
# themselves for the bits that need it.
if [ "$(id -u)" -eq 0 ] && [ -z "${SUDO_USER:-}" ]; then
    echo -e "${RED}Please run this as your normal user, not as root / sudo bash run.sh.${RESET}"
    echo -e "${YELLOW}Each script will call sudo itself for the parts that need it.${RESET}"
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

# --- Ordered list: "script|description|default" ---
SCRIPTS=(
    "addUserToGroups.sh|Add your user to input/video/render groups (needed for touchpad + GPU accel fixes)|Y"
    "kdeDebloat.sh|Debloat KDE Plasma (games/education/PIM/extras/Kate/Konqueror/Dragon Player) toward a minimal-but-functional install|Y"
    "usefulApps.sh|Install VLC, TLP (+ ThinkPad battery thresholds), and a few small KDE-completing utilities|Y"
    "catppuccinPlasma.sh|Catppuccin (Mocha, Red accent) Global Theme, icons, Konsole profile — the toolkit's theming step|Y"
    "bootThemeSetup.sh|Carry the Catppuccin theme to Plymouth (boot splash), GRUB, and the SDDM login screen|Y"
    "touchpadTrackpointFix.sh|Apply touchpad/trackpoint polling + libinput fixes|Y"
    "hardwareSupport.sh|Install WiFi/Bluetooth firmware, CPU microcode, and fwupd firmware updates|Y"
    "bluetoothSetup.sh|Set up the Bluetooth stack, Bluedevil, and audio bridging for headsets/earbuds|Y"
    "multimediaCodecs.sh|Install audio/video codecs + DVD playback support|Y"
    "firefoxHarden.sh|Install & harden Firefox ESR with Betterfox + privacy policies|Y"
    "installFonts.sh|Install Noto, Font Awesome, and JetBrainsMono Nerd Font|Y"
    "terminalButterbash.sh|Install ButterBash for a more functional terminal|Y"
    "fastfetchConfig.sh|Install fastfetch + curated config presets|Y"
    "desktopEssentials.sh|Set up Flatpak/Discover, PackageKit update notifications, printing, Partition Manager, and the firewall panel|Y"
    "timeshiftSetup.sh|Install Timeshift for system snapshots/restore|Y"
    "networkTimeSync.sh|Enable NTP time sync via chrony (harmless if already synced)|N"
    "installPhotogimp.sh|(optional) Install GIMP + PhotoGIMP's Photoshop-like layout/theme|N"
    "installVscodium.sh|(optional) Install VSCodium editor|N"
    "vscodiumDevSetup.sh|(optional) Configure VSCodium for C++/Python development|N"
    "aiOpencode.sh|Install OpenCode AI coding agent + hotkey + system skill file (from ohmydebn)|Y"
    "devToolsExtras.sh|(optional) Install curated dev extras: btop, eza, bat, zoxide check, Neovim+lazy.nvim, KeePassXC|N"
    "gamingSetup.sh|(optional) Install Heroic Games Launcher / Steam / Wine|N"
    "vesktopTelegram.sh|(optional) Install Vesktop (Discord client) / Telegram|N"
)

# --- --list: print the ordering and exit ----------------------------------
if [ "$DO_LIST" -eq 1 ]; then
    echo -e "${BLUE}Toolkit scripts, in run order:${RESET}\n"
    i=1
    for ENTRY in "${SCRIPTS[@]}"; do
        SCRIPT="${ENTRY%%|*}"
        REST="${ENTRY#*|}"
        DESC="${REST%%|*}"
        DEFAULT="${REST##*|}"
        printf '  %2d.  %-28s default: %-1s  %s\n' "$i" "$SCRIPT" "${DEFAULT^^}" "$DESC"
        ((i++))
    done
    echo
    echo -e "Run everything:   ${CYAN}./run.sh${RESET}"
    echo -e "Pick a subset:    ${CYAN}./run.sh --only addUserToGroups.sh,usefulApps.sh${RESET}"
    echo -e "Fully unattended: ${CYAN}./run.sh --yes${RESET}"
    exit 0
fi

# --- --only: pick the subset, keep the defined order -----------------------
SELECTED=()
if [ "${#ONLY_NAMES[@]}" -gt 0 ]; then
    # Normalize requested names (tolerate the trailing .sh or not).
    declare -A WANTED
    for n in "${ONLY_NAMES[@]}"; do
        [ -z "$n" ] && continue
        n="${n%.sh}"
        WANTED["${n%%.sh}"]=1
    done
    unset n
    for ENTRY in "${SCRIPTS[@]}"; do
        SCRIPT="${ENTRY%%|*}"
        if [ -n "${WANTED[${SCRIPT%.sh}]+x}" ]; then
            SELECTED+=("$ENTRY")
            unset "WANTED[${SCRIPT%.sh}]"
        fi
    done
    for leftover in "${!WANTED[@]}"; do
        echo -e "${YELLOW}⚠ Not a toolkit script, ignoring: $leftover.sh${RESET}"
    done
    unset leftover
    if [ "${#SELECTED[@]}" -eq 0 ]; then
        echo -e "${RED}No matching scripts for --only. Use --list to see available ones.${RESET}"
        exit 1
    fi
else
    SELECTED=("${SCRIPTS[@]}")
fi

echo -e "${BLUE}=========================================================${RESET}"
echo -e "${BLUE}   Devuan/Debian KDE Setup${RESET}"
echo -e "${BLUE}=========================================================${RESET}\n"

# --- One apt refresh, then let the scripts skip their own ------------------
# Scripts call apt_update(), which is a no-op when DEVMKDE_SKIP_APT_UPDATE
# is set — so we refresh exactly once up front instead of ~13 times.
export DEVMKDE_SKIP_APT_UPDATE=1
if [ "$SKIP_APT_UPDATE" -eq 0 ]; then
    echo -e "${CYAN}[*] Refreshing package lists once (scripts will skip their own refreshes)...${RESET}"
    if ! sudo apt-get update; then
        echo -e "${YELLOW}[!] apt-get update failed — continuing anyway. Some installs may fail if lists are stale.${RESET}"
    fi
fi

# --- Summary log -----------------------------------------------------------
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/devuan-kde-setup"
mkdir -p "$STATE_DIR"
LOG_FILE="$STATE_DIR/last-run.log"
record_run() { printf '%(%F %T)T  %s\n' -1 "$1" >> "$LOG_FILE"; }

record_run "$0 ${ONLY_NAMES[*]:-all} (assume-yes=${ASSUME_YES:-0}, skip-apt=${SKIP_APT_UPDATE:-0})"

FAILED=()
SKIPPED=()

for ENTRY in "${SELECTED[@]}"; do
    SCRIPT="${ENTRY%%|*}"
    REST="${ENTRY#*|}"
    DESC="${REST%%|*}"
    DEFAULT="${REST##*|}"
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