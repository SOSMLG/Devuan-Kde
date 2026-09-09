#!/usr/bin/env bash
# =======================================================
# Vesktop & Telegram (optional)
# -------------------------------------------------------
#  - Vesktop: Vencord's standalone Discord client (better
#    Linux/Wayland support, screen-share, built-in Vencord
#    mods) via its latest GitHub release .deb — not pinned
#    to v1.6.5, so this keeps working as new versions ship.
#    https://github.com/Vencord/Vesktop
#  - Telegram Desktop: official tar.xz, extracted to
#    ~/.local/opt/Telegram with a ~/.local/bin symlink and
#    a .desktop entry. Same method as DiscordAndTelegram.sh.
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

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root — it needs to write to your own \$HOME."
    log_err "Run it as your normal user; it will call sudo itself when needed."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Vesktop & Telegram${NC}"
echo -e "${CYAN}=========================================================${NC}"

# ---------------------------------------------------------------------------
# Vesktop — latest GitHub release .deb
# ---------------------------------------------------------------------------
install_vesktop() {
    if is_installed vesktop; then
        log_ok "Vesktop is already installed."
        return 0
    fi

    log_info "Looking up the latest Vesktop release..."
    local api_url="https://api.github.com/repos/Vencord/Vesktop/releases/latest"
    local api_json
    if ! api_json=$(curl -fsSL "$api_url"); then
        log_err "Could not reach GitHub API to find the latest Vesktop release."
        return 1
    fi

    local deb_url
    deb_url=$(echo "$api_json" | python3 -c "
import json, sys
data = json.load(sys.stdin)
assets = data.get('assets', [])
candidates = [a['browser_download_url'] for a in assets if a['name'].lower().endswith('.deb')]
amd64 = [u for u in candidates if 'amd64' in u.lower() or 'x86_64' in u.lower()]
print((amd64 or candidates or [''])[0])
" 2>/dev/null)

    if [ -z "$deb_url" ]; then
        log_err "Could not find a .deb asset in the latest Vesktop release."
        log_warn "Check manually: https://github.com/Vencord/Vesktop/releases"
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

    log_info "Installing Vesktop..."
    if sudo apt-get install -y "$tmp_deb"; then
        log_ok "Vesktop installed."
    else
        log_err "Vesktop install failed (dependency issue?). Trying dpkg + fix-broken..."
        sudo dpkg -i "$tmp_deb" || true
        if sudo apt-get install -f -y; then
            log_ok "Vesktop installed after dependency fix-up."
        else
            rm -f "$tmp_deb"
            return 1
        fi
    fi
    rm -f "$tmp_deb"
}

# ---------------------------------------------------------------------------
# Telegram Desktop — official tar.xz, no sudo needed at all
# ---------------------------------------------------------------------------
install_telegram() {
    if [ -x "$HOME/.local/opt/Telegram/Telegram" ]; then
        log_ok "Telegram is already installed at $HOME/.local/opt/Telegram."
        return 0
    fi

    local tmp_dir
    tmp_dir="$(mktemp -d)"
    # shellcheck disable=SC2064
    trap "rm -rf '$tmp_dir'" RETURN

    log_info "Downloading Telegram Desktop..."
    if ! wget -q -O "$tmp_dir/telegram.tar.xz" "https://telegram.org/dl/desktop/linux"; then
        log_err "Failed to download Telegram."
        return 1
    fi

    verify_download "$tmp_dir/telegram.tar.xz" 10485760 || return 1

    mkdir -p "$HOME/.local/opt"
    if [ -d "$HOME/.local/opt/Telegram" ]; then
        log_info "Removing previous Telegram installation..."
        rm -rf "$HOME/.local/opt/Telegram"
    fi

    log_info "Extracting Telegram..."
    if ! tar -xf "$tmp_dir/telegram.tar.xz" -C "$HOME/.local/opt"; then
        log_err "Failed to extract Telegram."
        return 1
    fi
    chmod +x "$HOME/.local/opt/Telegram/Telegram"

    log_info "Creating symlink and desktop entry..."
    mkdir -p "$HOME/.local/bin" "$HOME/.local/share/applications"
    ln -sf "$HOME/.local/opt/Telegram/Telegram" "$HOME/.local/bin/telegram"

    cat > "$HOME/.local/share/applications/telegram.desktop" << EOF
[Desktop Entry]
Name=Telegram
Comment=Fast and secure messaging app
Exec=$HOME/.local/bin/telegram
Icon=telegram
Type=Application
Categories=Network;InstantMessaging;
Terminal=false
EOF

    log_ok "Telegram installed at $HOME/.local/opt/Telegram (launcher: telegram)."

    if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
        log_warn "$HOME/.local/bin is not in your PATH."
        log_warn "Add to your shell rc: export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}

# ---------------------------------------------------------------------------
# Menu
# ---------------------------------------------------------------------------
if ask "Install Vesktop (Discord client)?"; then
    install_vesktop
fi

if ask "Install Telegram Desktop?"; then
    install_telegram
fi

echo -e "${GREEN}Vesktop/Telegram step complete.${NC}"
