#!/usr/bin/env bash
# Installs ButterBash (bundled locally under ../butterbash so this works
# offline / without depending on the upstream repo still existing).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

BUTTERBASH_SRC="$SCRIPT_DIR/../butterbash"

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root — it installs into your own \$HOME/.config/bash and ~/.bashrc."
    exit 1
fi

if [ ! -d "$BUTTERBASH_SRC" ] || [ ! -f "$BUTTERBASH_SRC/install.sh" ]; then
    log_err "Bundled ButterBash not found at $BUTTERBASH_SRC"
    log_err "Expected the extracted butterbash-main archive to live at devuan-kde-setup/butterbash/"
    exit 1
fi

log_info "Installing ButterBash from $BUTTERBASH_SRC ..."

# ButterBash's own install.sh cd-relies on being run from inside its
# directory (it references ./bash and ./bashrc.example as relative paths).
if ( cd "$BUTTERBASH_SRC" && bash install.sh --yes ); then
    log_ok "ButterBash installed."
    echo -e "${YELLOW}Run 'source ~/.bashrc' or open a new terminal to use it.${NC}"
else
    log_err "ButterBash installation failed."
    exit 1
fi
