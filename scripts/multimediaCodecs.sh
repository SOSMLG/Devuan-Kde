#!/usr/bin/env bash
# =======================================================
# Multimedia Codecs
# -------------------------------------------------------
# The single most common "why doesn't this just work like
# Mint" complaint: MP3s, H.264/H.265 video, and DVDs don't
# play out of the box on a stock Debian/Devuan install
# because the codecs are licensing-encumbered and live
# outside main. This installs the same practical set Mint's
# own "Install Multimedia Codecs" step pulls in.
#
# libdvd-pkg is the one genuine gotcha here: it builds
# libdvdcss from source via a debconf-driven postinst step
# that can sit waiting for input if not handled carefully.
# This runs it under DEBIAN_FRONTEND=noninteractive with a
# hard timeout, so the script can never hang indefinitely.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

if [ "$(id -u)" -eq 0 ]; then
    log_err "Do not run this as root."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} Multimedia Codecs${NC}"
echo -e "${CYAN}=========================================================${NC}"

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. Core codec packages
# ---------------------------------------------------------------------------
if ask "Install audio/video codec packages (ffmpeg, GStreamer plugins)?"; then
    install_pkgs "Codec packages" \
        ffmpeg \
        gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
        gstreamer1.0-plugins-bad gstreamer1.0-plugins-ugly \
        gstreamer1.0-libav libavcodec-extra
fi

# ---------------------------------------------------------------------------
# 2. DVD playback (libdvdcss, built from source by libdvd-pkg's postinst)
# ---------------------------------------------------------------------------
if ask "Install DVD playback support (libdvd-pkg)?"; then
    if is_installed libdvd-pkg && is_installed libdvdcss2; then
        log_ok "libdvd-pkg already installed and libdvdcss already built."
    elif check_repo_package libdvd-pkg "contrib"; then
        log_info "Installing libdvd-pkg..."
        if sudo DEBIAN_FRONTEND=noninteractive apt-get install -y libdvd-pkg; then
            log_info "Building libdvdcss (this runs non-interactively, capped at 5 minutes)..."
            if sudo timeout 300 env DEBIAN_FRONTEND=noninteractive dpkg-reconfigure libdvd-pkg; then
                log_ok "libdvd-pkg configured."
            else
                log_warn "libdvd-pkg's build step timed out or failed."
                log_warn "Retry manually later with: sudo dpkg-reconfigure libdvd-pkg"
            fi

            # The build produces a separate "libdvdcss2" package — its
            # presence is the real signal the build succeeded.
            if is_installed libdvdcss2; then
                log_ok "libdvdcss built successfully."
            else
                log_warn "Could not confirm libdvdcss built. DVDs with copy protection may not play."
                log_warn "Check manually with: sudo dpkg-reconfigure libdvd-pkg"
            fi
        else
            log_err "Failed to install libdvd-pkg."
        fi
    fi
fi

echo -e "${GREEN}Multimedia codecs step complete.${NC}"
