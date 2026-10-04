#!/usr/bin/env bash
# DEVMKDE_DESC: Install fastfetch + the bundled Devuan ASCII config (fancy + minimal)
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# fastfetch
# -------------------------------------------------------
# System info on terminal open, with the Devuan logo.
#
# The two configs ship IN this repo, as plain text, under
# assets/fastfetch/:
#
#   devuan.jsonc          fancy    -> installed as ~/.config/fastfetch/config.jsonc
#   devuan-minimal.jsonc  minimal  -> use with
#                                     fastfetch --config ~/.config/fastfetch/devuan-minimal.jsonc
#
# Both draw the Devuan logo from fastfetch's own built-in ASCII art
# ("logo.type": "builtin"), so no image ships in this repo and the art
# always matches the fastfetch version that is installed.
#
# This step used to pull a set of curated presets from the butterscripts
# repo instead. Dropped: they were remote files nothing here could verify,
# and the only thing actually wanted from them was a Devuan logo — which
# fastfetch ships itself.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root

require_priv

log_head "fastfetch"

# ---------------------------------------------------------------------------
# 1. Install fastfetch
# ---------------------------------------------------------------------------
if is_installed fastfetch; then
    log_ok "fastfetch already installed."
else
    log_info "Updating package lists..."
    apt_update -qq
    if install_pkgs "fastfetch" fastfetch; then
        log_ok "fastfetch installed."
    else
        log_err "Failed to install fastfetch."
        exit 1
    fi
fi

# ---------------------------------------------------------------------------
# 2. Devuan configs from assets/
# ---------------------------------------------------------------------------
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets/fastfetch" 2>/dev/null && pwd)"
FF_DIR="$HOME/.config/fastfetch"

install_configs() {
    local name
    if [ -z "$ASSETS_DIR" ]; then
        log_err "assets/fastfetch/ not found next to scripts/ — is this a full checkout?"
        return 1
    fi
    for name in devuan.jsonc devuan-minimal.jsonc; do
        if [ ! -f "$ASSETS_DIR/$name" ]; then
            log_err "Missing bundled config: $ASSETS_DIR/$name"
            log_err "The two fastfetch configs live in the repo at assets/fastfetch/ —"
            log_err "re-run from a full checkout, or write your own into $FF_DIR."
            return 1
        fi
    done

    mkdir -p "$FF_DIR" || return 1
    for name in devuan.jsonc devuan-minimal.jsonc; do
        # Straight overwrite is safe: these files are ours, shipped here, and
        # the only thing a user would have hand-edited is config.jsonc (below),
        # which is handled separately precisely because it is not ours.
        cp -f "$ASSETS_DIR/$name" "$FF_DIR/$name" || return 1
        log_info "  installed $name"
    done

    # The default profile. A config.jsonc the user has tuned is THEIR file:
    # back it up, then ask before replacing it.
    local default_src="$FF_DIR/devuan.jsonc" default_name="devuan.jsonc"
    if ask "Use the minimal variant as the default (instead of fancy)?" N; then
        default_src="$FF_DIR/devuan-minimal.jsonc"
        default_name="devuan-minimal.jsonc"
    fi

    if [ -f "$FF_DIR/config.jsonc" ]; then
        # Previously this backed the file up and then never installed anything
        # — the rerun silently left the old config in place and printed a
        # "switch anyway" line that copied the backup over itself. So: back up,
        # then actually offer the replacement, and print real commands for both
        # directions (new default vs. your tuned copy).
        local bak="$FF_DIR/config.jsonc.bak.$(date +%Y%m%d-%H%M%S)"
        if ! cp -f "$FF_DIR/config.jsonc" "$bak"; then
            log_warn "Existing config.jsonc could NOT be backed up — leaving it untouched."
            return 0
        fi
        log_warn "Existing config.jsonc backed up to $(basename "$bak")."

        if ask "Replace it with the bundled $default_name?" N; then
            if cp -f "$default_src" "$FF_DIR/config.jsonc"; then
                log_ok "Default config: config.jsonc (from $default_name)"
                log_info "  undo: cp $(basename "$bak") config.jsonc"
            else
                log_warn "Could not install $default_name as config.jsonc."
                cp -f "$bak" "$FF_DIR/config.jsonc" 2>/dev/null \
                    && log_info "Restored your previous config.jsonc."
            fi
        else
            log_info "Kept your config.jsonc as the default."
            log_info "  use $default_name instead: cp $default_name config.jsonc"
            log_info "  the variant stays available as: fastfetch --config ~/.config/fastfetch/$default_name"
        fi
    else
        cp -f "$default_src" "$FF_DIR/config.jsonc" \
            && log_ok "Default config: config.jsonc (from $default_name)"
    fi
    return 0
}

if ask "Install the Devuan fastfetch configs (fancy + minimal)?"; then
    install_configs || log_warn "fastfetch configs not installed — 'fastfetch' still works with its built-in defaults."
else
    log_info "Skipped the config install. 'fastfetch' will use its own defaults."
fi

log_ok "fastfetch setup complete. Try it:"
echo    "  fastfetch"
echo    "  fastfetch --config ~/.config/fastfetch/devuan-minimal.jsonc   # compact variant"
