#!/usr/bin/env bash
# DEVMKDE_DESC: Install Vesktop (Discord client) / Telegram
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: optional
# =======================================================
# Vesktop & Telegram (optional)
# -------------------------------------------------------
#  - Vesktop: Vencord's standalone Discord client (better
#    Linux/Wayland support, screen-share, built-in Vencord
#    mods) installed from the latest GitHub release .deb.
#    Stable is deliberate, not a leftover: Vesktop publishes
#    no dev/nightly channel. There is no releases/tag/dev
#    (404), and of the last 30 releases exactly one is a
#    prerelease — v1.5.2-alpha.1, from April 2024. So the
#    latest release IS the newest build Vesktop publishes.
#    The Flatpak is dev.vencord.Vesktop, but that appid
#    tracks the same stable tags; it is not a dev channel.
#    https://github.com/Vencord/Vesktop
#  - Telegram Desktop: official stable tar.xz from
#    telegram.org/dl/desktop/linux, extracted to
#    ~/.local/opt/Telegram with a ~/.local/bin symlink and
#    a .desktop entry. Also deliberate: Telegram's only other
#    channel is beta (GitHub prereleases ship
#    td-setup-linux-x64-<ver>-beta.tar.xz), not a dev build.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

log_head "Vesktop & Telegram"

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
    if ! curl -fL --retry 3 -o "$tmp_deb" "$deb_url"; then
        log_err "Download failed."
        rm -f "$tmp_deb"
        return 1
    fi

    verify_download "$tmp_deb" 102400 || return 1

    log_info "Installing Vesktop..."
    if install_deb_file "Vesktop" "$tmp_deb" --repair; then
        log_ok "Vesktop installed."
    else
        log_err "Vesktop install failed even after a dependency fix-up."
        rm -f "$tmp_deb"
        return 1
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
    if ! curl -fL --retry 3 -o "$tmp_dir/telegram.tar.xz" "https://telegram.org/dl/desktop/linux"; then
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
