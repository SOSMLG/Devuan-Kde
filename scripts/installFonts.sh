#!/usr/bin/env bash
# =======================================================
# Font Installer
# -------------------------------------------------------
# Installs: Noto (Latin + Arabic + Emoji), Font Awesome,
#           JetBrainsMono Nerd Font (latest GitHub release)
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root."
    exit 1
fi

if ! command -v sudo &>/dev/null; then
    log_err "sudo not found."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Font Installer${NC}"
echo -e "${CYAN}=========================================================${NC}"

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. APT packages
# ---------------------------------------------------------------------------
log_info "Updating package lists..."
apt_update -qq

log_info "Installing Noto + Font Awesome via apt..."
if sudo apt-get install -y \
    curl \
    fonts-font-awesome \
    fonts-noto-core \
    fonts-noto-unhinted \
    fonts-noto-color-emoji \
    fonts-noto-mono; then
    log_ok "APT fonts installed"
else
    log_err "APT install failed"
    exit 1
fi

# ---------------------------------------------------------------------------
# 2. JetBrainsMono Nerd Font
# ---------------------------------------------------------------------------
NERD_FONT_DIR="${HOME}/.local/share/fonts/NerdFonts"
mkdir -p "$NERD_FONT_DIR"

if fc-list | grep -qi "JetBrainsMono Nerd Font"; then
    log_warn "JetBrainsMono Nerd Font already installed — skipping download"
else
    log_info "Fetching latest release URL from GitHub..."
    DOWNLOAD_URL=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest \
        | grep -oP '"browser_download_url": "\K[^"]+' \
        | grep -i "JetBrainsMono.*tar\.xz" \
        | head -1)

    if [[ -z "$DOWNLOAD_URL" ]]; then
        log_warn "GitHub API failed, using fallback URL..."
        DOWNLOAD_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.2.1/JetBrainsMono.tar.xz"
    fi

    FONT_ARCHIVE="${WORK_DIR}/JetBrainsMono.tar.xz"
    log_info "Downloading JetBrainsMono Nerd Font..."
    if ! curl -fsSL --progress-bar -L -o "$FONT_ARCHIVE" "$DOWNLOAD_URL"; then
        log_err "Download failed: ${DOWNLOAD_URL}"
        exit 1
    fi

    verify_download "$FONT_ARCHIVE" 1048576 || exit 1

    # Upstream nerd-fonts publishes "<asset>.tar.xz.sha256" per release asset.
    # Compare against it when reachable; otherwise fall back to the structural
    # check above plus a logged sha256 to eyeball manually.
    EXPECTED_SHA="$(curl -fsSL --max-time 20 "${DOWNLOAD_URL}.sha256" 2>/dev/null | awk '{print $1}' | tr 'A-F' 'a-f')"
    if [ -n "$EXPECTED_SHA" ]; then
        if ! sha256_verify "$FONT_ARCHIVE" "$EXPECTED_SHA"; then
            log_err "Checksum mismatch — the download may have been tampered with. Removing it."
            exit 1
        fi
    else
        log_warn "Could not fetch upstream .sha256 for this release — relying on the structural check."
        log_warn "Compare manually if you want: $(sha256sum "$FONT_ARCHIVE" | cut -d' ' -f1)"
    fi

    log_info "Extracting fonts..."
    if ! tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR" --wildcards '*.ttf' 2>/dev/null; then
        log_warn "Falling back to full extraction..."
        if ! tar -xf "$FONT_ARCHIVE" -C "$NERD_FONT_DIR"; then
            log_err "Failed to extract font archive"
            exit 1
        fi
    fi
    log_ok "JetBrainsMono Nerd Font installed to ${NERD_FONT_DIR}"
fi

# ---------------------------------------------------------------------------
# 3. Fontconfig
# ---------------------------------------------------------------------------
FONTCONF_DIR="${HOME}/.config/fontconfig"
FONTCONF="${FONTCONF_DIR}/fonts.conf"
mkdir -p "$FONTCONF_DIR"

log_info "Writing ${FONTCONF}..."
cat > "$FONTCONF" << 'EOF'
<?xml version='1.0'?>
<!DOCTYPE fontconfig SYSTEM 'fonts.dtd'>
<fontconfig>

  <!-- Monospace: Prefer JetBrainsMono Nerd Font, fallback to Noto Mono -->
  <alias>
    <family>monospace</family>
    <prefer>
      <family>JetBrainsMono Nerd Font Mono</family>
      <family>Noto Sans Mono</family>
      <family>DejaVu Sans Mono</family>
    </prefer>
  </alias>

  <!-- Sans-serif: Noto Sans + Arabic -->
  <alias>
    <family>sans-serif</family>
    <prefer>
      <family>Noto Sans</family>
      <family>Noto Sans Arabic</family>
      <family>Noto Color Emoji</family>
    </prefer>
  </alias>

  <!-- Serif: Noto Serif -->
  <alias>
    <family>serif</family>
    <prefer>
      <family>Noto Serif</family>
      <family>Noto Serif Arabic</family>
    </prefer>
  </alias>

  <!-- Emoji: Always use color emoji -->
  <match target="pattern">
    <test name="family"><string>emoji</string></test>
    <edit name="family" mode="assign" binding="same">
      <string>Noto Color Emoji</string>
    </edit>
  </match>

  <!-- Rendering: Subpixel hinting for LCD screens -->
  <match target="font">
    <edit name="antialias"  mode="assign"><bool>true</bool></edit>
    <edit name="hinting"    mode="assign"><bool>true</bool></edit>
    <edit name="hintstyle"  mode="assign"><const>hintslight</const></edit>
    <edit name="rgba"       mode="assign"><const>rgb</const></edit>
    <edit name="lcdfilter"  mode="assign"><const>lcddefault</const></edit>
  </match>

</fontconfig>
EOF
log_ok "fonts.conf written"

# ---------------------------------------------------------------------------
# 4. Rebuild font cache
# ---------------------------------------------------------------------------
log_info "Rebuilding font cache..."
sudo fc-cache -f
fc-cache -f "$NERD_FONT_DIR"
log_ok "Font cache updated"

echo
log_ok "All done!"
echo -e "${CYAN}Verify with:${NC}"
echo -e "  fc-match 'JetBrainsMono Nerd Font Mono'"
echo -e "  fc-match 'Noto Sans Arabic'"
echo -e "  fc-match monospace"
