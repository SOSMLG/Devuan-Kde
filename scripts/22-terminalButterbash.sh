#!/usr/bin/env bash
# DEVMKDE_DESC: Install ButterBash for a more functional terminal
# DEVMKDE_DEFAULT: Y
# DEVMKDE_PHASE: core
# =======================================================
# ButterBash
# -------------------------------------------------------
# Fetches ButterBash from upstream at a PINNED commit, verifies
# the tarball's SHA256, and installs it into the user's own
# ~/.config — then wires it into ~/.bashrc by APPENDING one
# marked block. It never replaces an existing .bashrc.
#
# Why fetched and not vendored: this repo used to carry a
# verbatim copy of the project (56 KB, 12 files). That copy
# cannot be updated without a release, cannot be verified
# against upstream by anyone reading the repo, and went stale
# the moment upstream changed. Pinning a commit plus a hash
# gives the same "works offline after one fetch" property with
# a provenance you can check:
#
#   https://codeberg.org/justaguylinux/butterbash
#
# This script deliberately does NOT run upstream's install.sh.
# That script moves ~/.config/bash aside and overwrites
# ~/.bashrc outright, and it shells out to `sudo apt install`
# with its own idea of which package manager is in use. Both
# are decisions this toolkit should not delegate.
#
# Overridable (all optional):
#   BUTTERBASH_REF       commit-ish to fetch        (default: pinned below)
#   BUTTERBASH_URL       full archive URL           (default: Codeberg)
#   BUTTERBASH_SHA256    expected sha256 of archive (default: pinned below)
#
# Point those three at a newer commit and the hash from the
# release/commit page to move forward; the archive layout is
# checked before anything is installed, so a surprise upstream
# fails loudly instead of half-installing.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
require_priv

log_head "ButterBash"

# --- Pinned upstream ---------------------------------------------------------
# Pinned to a specific commit rather than a branch: "main" would silently
# change what lands on someone's shell between two runs of this script.
BUTTERBASH_REF="${BUTTERBASH_REF:-ae194a92923c922e1baaede280940a5a256da99f}"
BUTTERBASH_URL="${BUTTERBASH_URL:-https://codeberg.org/justaguylinux/butterbash/archive/${BUTTERBASH_REF}.tar.gz}"
BUTTERBASH_SHA256="${BUTTERBASH_SHA256:-0989771ec63756fa90469a7d14546b490de829c1c15cf58ac5362d40c50906c9}"

BB_CONFIG_DIR="$HOME/.config/bash"
BB_RC_DIR="$HOME/.config/butterbash"
BB_RC="$BB_RC_DIR/bashrc"
BASHRC="$HOME/.bashrc"
MARKER_BEGIN="# >>> butterbash (devuan-kde-setup 22-terminalButterbash.sh) >>>"
MARKER_END="# <<< butterbash <<<"

# --- 1. Fetch + verify -------------------------------------------------------
WORKDIR="$(mktemp -d /tmp/butterbash.XXXXXX)" || { log_err "mktemp failed."; exit 1; }
# shellcheck disable=SC2064
trap "rm -rf '$WORKDIR'" EXIT

TARBALL="$WORKDIR/butterbash.tar.gz"

fetch() {
    local url="$1" out="$2"
    if command_exists curl; then
        curl -fsSL --max-time 120 "$url" -o "$out"
    elif command_exists wget; then
        wget -q --timeout=30 --tries=3 "$url" -O "$out"
    else
        log_err "Neither curl nor wget found — install one of them and re-run."
        return 1
    fi
}

log_info "Fetching $BUTTERBASH_URL"
if ! fetch "$BUTTERBASH_URL" "$TARBALL"; then
    log_err "Download failed. If upstream moved or is down, nothing was changed."
    log_err "Override the pin if you are tracking a different commit:"
    log_err "  BUTTERBASH_REF=<sha> BUTTERBASH_SHA256=<sha256> $0"
    exit 1
fi

verify_download "$TARBALL" 4096 || { log_err "Archive looks wrong — stopping."; exit 1; }
if [ -n "$BUTTERBASH_SHA256" ] && ! sha256_verify "$TARBALL" "$BUTTERBASH_SHA256"; then
    log_err "Checksum does not match the pinned value — refusing to install."
    log_err "Expected: $BUTTERBASH_SHA256"
    exit 1
fi

# --- 2. Extract + check the layout ------------------------------------------
# Codeberg's archive root is the project name; find the one directory that
# holds bash/ rather than assuming a depth, so a mirror that nests differently
# still works.
mkdir -p "$WORKDIR/src"
if ! tar -xzf "$TARBALL" -C "$WORKDIR/src" 2>/dev/null; then
    log_err "Could not extract the archive."
    exit 1
fi

BB_SRC=""
for candidate in "$WORKDIR/src" "$WORKDIR"/src/*/; do
    [ -d "$candidate/bash" ] && [ -f "$candidate/bashrc.example" ] && BB_SRC="${candidate%/}" && break
done
if [ -z "$BB_SRC" ]; then
    log_err "Archive does not look like ButterBash (no bash/ + bashrc.example inside)."
    log_err "Refusing to guess where the files should go — nothing was changed."
    exit 1
fi
log_ok "Archive layout verified ($BB_SRC)."

# --- 3. Dependencies ---------------------------------------------------------
# Upstream's own installer would run `sudo apt install` for each of these. Doing
# it through install_pkgs means: nothing is installed when it is already there,
# and it goes through the toolkit's own privilege helper (doas on a box without
# sudo) instead of assuming sudo exists.
#
# eza is NOT optional decoration: aliases.bash keys the whole `l/ls/ll/la/lt/lh`
# alias set off `command -v eza` (then exa, then falls back to plain `ls -lF`).
# Upstream install.sh installs it too. Without it the config still loads and the
# aliases still resolve — just to the boring fallback, silently.
install_pkgs "ButterBash tools" fzf ripgrep fd-find bat eza zoxide || \
    log_warn "Some optional tools failed to install — the shell still works, fzf previews may not."

# Debian ships these two under names that do not match what ButterBash's fzf.bash
# looks for. Symlink, idempotently, into ~/.local/bin (which upstream's bashrc
# puts on PATH).
link_tool() {
    local want="$1" have="$2" dir="$HOME/.local/bin" target
    command_exists "$want" && return 0
    command_exists "$have" || return 0
    mkdir -p "$dir" || return 1
    target="$dir/$want"
    if ln -sfn "$(command -v "$have")" "$target"; then
        log_info "  linked $want -> $have"
    fi
}
link_tool fd fdfind
link_tool bat batcat

# --- 4. ~/.config/bash -------------------------------------------------------
# Back up only when there is something to back up AND it differs from what we
# are about to write, so a re-run does not litter a backup per invocation.
if [ -d "$BB_CONFIG_DIR" ]; then
    if diff -rq "$BB_SRC/bash" "$BB_CONFIG_DIR" >/dev/null 2>&1; then
        log_ok "~/.config/bash already matches upstream — left alone."
    else
        BB_BACKUP="$HOME/.config/bash.backup.$(date +%Y%m%d-%H%M%S)"
        if cp -a "$BB_CONFIG_DIR" "$BB_BACKUP"; then
            log_warn "Existing ~/.config/bash differs — backed up to $BB_BACKUP"
        else
            log_err "Could not back up $BB_CONFIG_DIR — aborting rather than overwrite it."
            exit 1
        fi
    fi
fi

if mkdir -p "$BB_CONFIG_DIR" && cp -a "$BB_SRC/bash/." "$BB_CONFIG_DIR/"; then
    log_ok "ButterBash config installed to $BB_CONFIG_DIR"
else
    log_err "Could not install $BB_CONFIG_DIR — aborting."
    exit 1
fi

# --- 5. The bashrc -----------------------------------------------------------
# Stored OUTSIDE ~/.config/bash on purpose. Upstream's bashrc globs
# ~/.config/bash/*.bash and sources everything it finds, so keeping the
# top-level rc in that directory would make it source itself.
mkdir -p "$BB_RC_DIR"
if ! cp -f "$BB_SRC/bashrc.example" "$BB_RC"; then
    log_err "Could not write $BB_RC — aborting."
    exit 1
fi
log_ok "ButterBash rc installed to $BB_RC"

# --- 6. Wire it into .bashrc, appending only --------------------------------
# Upstream's installer copies its rc over ~/.bashrc, destroying whatever was
# there. Instead: one marked block, appended, and rewritten in place on re-runs
# so the file never accumulates duplicates.
touch "$BASHRC"

rc_block() {
    cat << EOF
$MARKER_BEGIN
# Managed by devuan-kde-setup (scripts/22-terminalButterbash.sh). Edits inside
# this block are replaced on the next run; put your own tweaks below it.
if [ -f "\$HOME/.config/butterbash/bashrc" ]; then
    . "\$HOME/.config/butterbash/bashrc"
fi
$MARKER_END
EOF
}

if grep -qF "$MARKER_BEGIN" "$BASHRC" 2>/dev/null; then
    log_info "Refreshing the existing butterbash block in .bashrc ..."
    NEW_BLOCK="$(rc_block)"
    # Replace exactly the marked region, in place, so anything the user wrote
    # above or below it keeps its position. awk -v carries the new block's
    # embedded newlines fine; a here-doc into getline() does not, which is the
    # version that shipped a half-written .bashrc the first time.
    if awk -v b="$MARKER_BEGIN" -v e="$MARKER_END" -v blk="$NEW_BLOCK" '
            $0 == b  { print blk; skip = 1; next }
            skip && $0 == e { skip = 0; next }
            !skip { print }
        ' "$BASHRC" > "$BASHRC.new" && [ -s "$BASHRC.new" ]; then
        mv "$BASHRC.new" "$BASHRC"
        log_ok ".bashrc block refreshed (your own lines untouched)."
    else
        rm -f "$BASHRC.new"
        log_warn "Could not rewrite the existing block — leaving .bashrc as it is."
    fi
else
    {
        printf '\n'
        rc_block
    } >> "$BASHRC"
    log_ok "Appended the butterbash block to .bashrc (nothing above it was touched)."
fi

echo
log_ok "ButterBash installed."
log_info "Open a new terminal (or: source ~/.bashrc) to use it."
log_info "Upstream's own docs: https://codeberg.org/justaguylinux/butterbash"
log_info "To undo: delete the marked block from ~/.bashrc (the files can stay)."
