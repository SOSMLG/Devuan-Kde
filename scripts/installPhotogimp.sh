#!/usr/bin/env bash
# =======================================================
# PhotoGIMP (optional)
# -------------------------------------------------------
# Installs GIMP via apt and applies PhotoGIMP's config —
# a Photoshop-like menu layout, keyboard shortcuts, and
# single-window theme for GIMP — fetched live from the
# official repo at install time:
#   https://github.com/Diolinux/PhotoGIMP
#
# Two things this script deliberately does NOT do blindly:
#
#  1. Upstream's .desktop file assumes GIMP was installed via
#     Flatpak (Exec=flatpak run ... org.gimp.GIMP). We install
#     GIMP natively via apt instead (consistent with the rest
#     of this toolkit), so the Exec line is rewritten to
#     launch the native /usr/bin/gimp binary.
#
#  2. PhotoGIMP's config here targets GIMP's 3.0 config format
#     (~/.config/GIMP/3.0/). GIMP 2.10 uses a different,
#     incompatible config layout. This script checks the
#     installed GIMP's actual version before copying anything
#     and refuses to apply a 3.0 config to a 2.10 install
#     rather than silently dropping in files GIMP won't
#     understand.
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

REPO="Diolinux/PhotoGIMP"
FALLBACK_TAG="3.1"   # used only if the GitHub API lookup below fails/rate-limits
PHOTOGIMP_TARGET_VER="3.0"   # the GIMP config-format version this patch targets

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} PhotoGIMP${NC}"
echo -e "${CYAN}=========================================================${NC}"

for dep in curl python3 tar; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log_err "Missing required tool: $dep"
        exit 1
    fi
done

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# 1. Fetch PhotoGIMP from GitHub — latest release tag, falling back to a
#    known-good pinned tag if the API lookup fails (rate limit, offline API
#    but working codeload, etc).
# ---------------------------------------------------------------------------
log_info "Looking up the latest PhotoGIMP release tag..."
TAG=""
API_JSON="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null || true)"
if [ -n "$API_JSON" ]; then
    TAG="$(echo "$API_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('tag_name',''))" 2>/dev/null || true)"
fi

if [ -z "$TAG" ]; then
    log_warn "Could not reach the GitHub API to find the latest tag (rate-limited?)."
    log_warn "Falling back to pinned tag: $FALLBACK_TAG"
    TAG="$FALLBACK_TAG"
else
    log_ok "Latest release: $TAG"
fi

TARBALL_URL="https://codeload.github.com/${REPO}/tar.gz/refs/tags/${TAG}"
log_info "Downloading: $TARBALL_URL"
if ! curl -fL -o "$TMP_DIR/photogimp.tar.gz" "$TARBALL_URL"; then
    log_err "Download failed. Check your network, or that tag $TAG still exists in $REPO."
    exit 1
fi

verify_download "$TMP_DIR/photogimp.tar.gz" 102400 || exit 1

log_info "Extracting..."
if ! tar xzf "$TMP_DIR/photogimp.tar.gz" -C "$TMP_DIR"; then
    log_err "Failed to extract the downloaded archive."
    exit 1
fi

# The tarball's top-level folder is named "PhotoGIMP-<tag>" — find it
# rather than hardcoding, in case naming ever changes.
SRC_DIR="$(find "$TMP_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
if [ -z "$SRC_DIR" ] || [ ! -d "$SRC_DIR/.config/GIMP/$PHOTOGIMP_TARGET_VER" ]; then
    log_err "Downloaded archive doesn't have the expected .config/GIMP/$PHOTOGIMP_TARGET_VER layout."
    log_err "Upstream may have restructured the repo — check https://github.com/${REPO}"
    exit 1
fi
log_ok "PhotoGIMP $TAG downloaded and verified."

# ---------------------------------------------------------------------------
# 2. Install GIMP
# ---------------------------------------------------------------------------
if ! is_installed gimp; then
    log_info "Refreshing package lists..."
    apt_update || { log_err "apt-get update failed, aborting."; exit 1; }
    log_info "Installing GIMP..."
    sudo apt-get install -y gimp || { log_err "Failed to install GIMP."; exit 1; }
else
    log_ok "GIMP is already installed."
fi

# ---------------------------------------------------------------------------
# 3. Version safety check — this PhotoGIMP release targets GIMP 3.0's
#    config format, which is not compatible with 2.10's.
# ---------------------------------------------------------------------------
GIMP_VERSION="$(gimp --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+(\.[0-9]+)?' | head -1)"
if [ -z "$GIMP_VERSION" ]; then
    log_warn "Could not determine the installed GIMP version (gimp --version failed)."
    if ! ask "Continue anyway and assume GIMP $PHOTOGIMP_TARGET_VER.x?" "N"; then
        exit 1
    fi
    GIMP_CONFIG_VER="$PHOTOGIMP_TARGET_VER"
else
    GIMP_CONFIG_VER="$(echo "$GIMP_VERSION" | cut -d. -f1,2)"
    log_info "Detected GIMP version: $GIMP_VERSION (config dir: $GIMP_CONFIG_VER)"
fi

if [ "$GIMP_CONFIG_VER" != "$PHOTOGIMP_TARGET_VER" ]; then
    log_err "This PhotoGIMP release targets GIMP $PHOTOGIMP_TARGET_VER's config format,"
    log_err "but the installed GIMP uses the $GIMP_CONFIG_VER config format. These are"
    log_err "not compatible — copying it over would leave GIMP ignoring the theme/layout"
    log_err "rather than actually applying it."
    log_warn "Check https://github.com/${REPO} for a release matching GIMP $GIMP_CONFIG_VER."
    exit 1
fi

# ---------------------------------------------------------------------------
# 4. Apply GIMP config (backed up first, never silently clobbered)
# ---------------------------------------------------------------------------
if ask "Apply PhotoGIMP's config (Photoshop-like layout, shortcuts, theme)?"; then
    GIMP_CONFIG_DIR="$HOME/.config/GIMP/$GIMP_CONFIG_VER"

    if [ -d "$GIMP_CONFIG_DIR" ]; then
        BACKUP="$HOME/.config/GIMP/${GIMP_CONFIG_VER}.bak.$(date +%Y%m%d_%H%M%S)"
        log_info "Existing GIMP config found, backing it up to $BACKUP"
        cp -r "$GIMP_CONFIG_DIR" "$BACKUP"
    fi

    mkdir -p "$GIMP_CONFIG_DIR"
    cp -r "$SRC_DIR/.config/GIMP/$PHOTOGIMP_TARGET_VER/." "$GIMP_CONFIG_DIR/"
    log_ok "PhotoGIMP config applied to $GIMP_CONFIG_DIR"
fi

# ---------------------------------------------------------------------------
# 5. Icons
# ---------------------------------------------------------------------------
if ask "Install PhotoGIMP icons?"; then
    ICON_DIR="$HOME/.local/share/icons/hicolor"
    mkdir -p "$ICON_DIR"
    cp -r "$SRC_DIR/.local/share/icons/hicolor/." "$ICON_DIR/"
    log_ok "Icons installed to $ICON_DIR"

    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        if gtk-update-icon-cache -f "$ICON_DIR" >/dev/null 2>&1; then
            log_ok "Icon cache refreshed."
        else
            log_warn "Icon cache refresh failed (non-fatal, icons will still show after a re-login)."
        fi
    fi
fi

# ---------------------------------------------------------------------------
# 6. Desktop launcher — Exec line rewritten for the native apt install
# ---------------------------------------------------------------------------
if ask "Install PhotoGIMP application launcher (Photoshop-style icon in the app menu)?"; then
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"
    DESKTOP_FILE="$APPS_DIR/photogimp.desktop"
    SRC_DESKTOP="$(find "$SRC_DIR/.local/share/applications" -maxdepth 1 -name '*.desktop' | head -1)"

    if [ -z "$SRC_DESKTOP" ]; then
        log_err "No .desktop file found in the downloaded release, skipping launcher."
    else
        sed 's|^Exec=.*|Exec=gimp %U|' "$SRC_DESKTOP" > "$DESKTOP_FILE"
        log_ok "Launcher installed to $DESKTOP_FILE (pointed at the native gimp binary, not Flatpak)."

        if command -v update-desktop-database >/dev/null 2>&1; then
            if update-desktop-database "$APPS_DIR" >/dev/null 2>&1; then
                log_ok "Desktop database refreshed."
            else
                log_warn "Desktop database refresh failed (non-fatal)."
            fi
        fi

        for cache_cmd in kbuildsycoca6 kbuildsycoca5; do
            if command -v "$cache_cmd" >/dev/null 2>&1; then
                "$cache_cmd" >/dev/null 2>&1 || true
                break
            fi
        done
    fi
fi

echo -e "${GREEN}PhotoGIMP $TAG setup complete.${NC}"
log_warn "If GIMP is currently running, restart it for the new config/theme to take effect."
log_warn "If the PhotoGIMP icon doesn't appear in the app menu right away, log out and back in."
