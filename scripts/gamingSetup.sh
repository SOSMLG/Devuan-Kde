#!/usr/bin/env bash
# =======================================================
# Gaming & Windows-app compatibility (optional)
# -------------------------------------------------------
#  - Core gaming libs: Vulkan (64+32-bit), Mesa utils,
#    GameMode, MangoHud
#  - Steam, via Valve's own steam_latest.deb. This avoids
#    touching /etc/apt/sources.list at all — no contrib/
#    non-free component wrangling needed. Valve's package
#    installs its own signed APT repo for future updates.
#  - Heroic Games Launcher (Epic/GOG/Amazon), via its latest
#    GitHub release .deb (always current, not pinned)
#  - Wine, for running Windows apps directly (i386 multiarch
#    + the "wine" metapackage + winetricks)
# =======================================================
set -uo pipefail

RED="\033[0;31m"; GREEN="\033[0;32m"; YELLOW="\033[1;33m"; CYAN="\033[0;36m"; NC="\033[0m"

log_info() { echo -e "${CYAN}[*]${NC} $1"; }
log_ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[!]${NC} $1"; }
log_err()  { echo -e "${RED}[ERROR]${NC} $1"; }

is_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"
}

ask() {
    local prompt="$1" default="${2:-Y}" reply
    local hint="(Y/n)"
    [ "$default" = "N" ] && hint="(y/N)"
    read -rp "$(echo -e "${YELLOW}${prompt} ${hint}: ${NC}")" reply
    reply=${reply:-$default}
    [[ "$reply" =~ ^[Yy]$ ]]
}

install_pkgs() {
    local label="$1"; shift
    local to_install=()
    local pkg
    for pkg in "$@"; do
        is_installed "$pkg" || to_install+=("$pkg")
    done
    if [ "${#to_install[@]}" -eq 0 ]; then
        log_ok "$label already installed."
        return 0
    fi
    log_info "$label: installing ${to_install[*]}"
    if sudo apt-get install -y "${to_install[@]}"; then
        log_ok "$label installed."
        return 0
    else
        log_warn "$label: some packages failed to install (continuing)."
        return 1
    fi
}

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Gaming & Windows-app compatibility${NC}"
echo -e "${CYAN}=========================================================${NC}"

I386_ENABLED=0
ensure_i386() {
    if [ "$I386_ENABLED" -eq 1 ]; then
        return 0
    fi
    if dpkg --print-foreign-architectures | grep -qx i386; then
        log_ok "i386 multiarch already enabled."
    else
        log_info "Enabling i386 multiarch (needed for 32-bit game/Windows libraries)..."
        sudo dpkg --add-architecture i386
    fi
    log_info "Refreshing package lists..."
    apt_update || { log_err "apt-get update failed."; return 1; }
    I386_ENABLED=1
}

# ---------------------------------------------------------------------------
# Core gaming libraries — Vulkan, Mesa utils, GameMode, MangoHud
# ---------------------------------------------------------------------------
install_gaming_libs() {
    ensure_i386 || return 1
    install_pkgs "Gaming libraries" \
        libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 \
        libgl1-mesa-dri:i386 mesa-utils gamemode mangohud
}

# ---------------------------------------------------------------------------
# Steam — Valve's own .deb (self-updating via its own APT repo, no
# sources.list editing required on our end)
# ---------------------------------------------------------------------------
install_steam() {
    if is_installed steam-launcher || is_installed steam-installer || is_installed steam; then
        log_ok "A Steam package is already installed."
        return 0
    fi

    ensure_i386 || return 1
    install_pkgs "Steam's graphics dependencies" \
        libvulkan1 libvulkan1:i386 mesa-vulkan-drivers mesa-vulkan-drivers:i386 libgl1-mesa-dri:i386

    log_info "Downloading Steam's official installer package..."
    local tmp_deb
    tmp_deb="$(mktemp --suffix=.deb)"
    if ! curl -fL -o "$tmp_deb" "https://repo.steampowered.com/steam/archive/stable/steam_latest.deb"; then
        log_err "Could not download steam_latest.deb from repo.steampowered.com."
        rm -f "$tmp_deb"
        return 1
    fi

    verify_download "$tmp_deb" 102400 || return 1

    log_info "Installing Steam..."
    if sudo apt-get install -y "$tmp_deb"; then
        log_ok "Steam installed. It will self-update on first launch."
    else
        log_err "Steam install failed."
        rm -f "$tmp_deb"
        return 1
    fi
    rm -f "$tmp_deb"
}

# ---------------------------------------------------------------------------
# Heroic Games Launcher — latest GitHub release .deb (not pinned to a
# specific version, so this keeps working as new releases ship)
# ---------------------------------------------------------------------------
install_heroic() {
    if is_installed heroic; then
        log_ok "Heroic Games Launcher is already installed."
        return 0
    fi

    log_info "Looking up the latest Heroic Games Launcher release..."
    local api_url="https://api.github.com/repos/Heroic-Games-Launcher/HeroicGamesLauncher/releases/latest"
    local api_json
    if ! api_json=$(curl -fsSL "$api_url"); then
        log_err "Could not reach GitHub API to find the latest Heroic release."
        return 1
    fi

    local deb_url
    deb_url=$(echo "$api_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
# Prefer an amd64 .deb; fall back to any .deb
candidates = [a['browser_download_url'] for a in assets if a['name'].lower().endswith('.deb')]
amd64 = [u for u in candidates if 'amd64' in u.lower() or 'x86_64' in u.lower()]
print((amd64 or candidates or [''])[0])
" 2>/dev/null)

    if [ -z "$deb_url" ]; then
        log_err "Could not find a .deb asset in the latest Heroic release."
        log_warn "Check manually: https://github.com/Heroic-Games-Launcher/HeroicGamesLauncher/releases"
        return 1
    fi

    log_info "Downloading: $deb_url"
    local tmp_deb
    tmp_deb="$(mktemp --suffix=.deb)"
    if ! curl -fL -o "$tmp_deb" "$deb_url"; then
        log_err "Download failed."
        rm -f "$tmp_deb"
        return 1
    fi

    verify_download "$tmp_deb" 102400 || return 1

    log_info "Installing Heroic .deb..."
    if sudo apt-get install -y "$tmp_deb"; then
        log_ok "Heroic Games Launcher installed."
    else
        log_err "Heroic install failed (dependency issue?). Trying dpkg + fix-broken..."
        sudo dpkg -i "$tmp_deb" || true
        if sudo apt-get install -f -y; then
            log_ok "Heroic Games Launcher installed after dependency fix-up."
        else
            rm -f "$tmp_deb"
            return 1
        fi
    fi
    rm -f "$tmp_deb"
}

# ---------------------------------------------------------------------------
# Wine — run Windows apps directly
# ---------------------------------------------------------------------------
install_wine() {
    if is_installed wine; then
        log_ok "Wine is already installed."
        return 0
    fi

    ensure_i386 || return 1

    log_info "Installing wine + winetricks..."
    if sudo apt-get install -y wine ; then
        log_ok "Wine installed. Run 'winecfg' once to set up your first Wine prefix."
    else
        log_err "Wine install failed."
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
if ask "Install core gaming libraries (Vulkan, GameMode, MangoHud)?" "N"; then
    install_gaming_libs
fi

if ask "Install Steam?" "N"; then
    install_steam
fi

if ask "Install Heroic Games Launcher (Epic/GOG/Amazon)?" "N"; then
    install_heroic
fi

if ask "Install Wine (run Windows .exe apps directly)?" "N"; then
    install_wine
fi

echo -e "${GREEN}Gaming/compatibility step complete.${NC}"
log_info "Tip: 'gamemoderun %command%' and MangoHud can be added to a game's launch options for perf gains/overlay."
