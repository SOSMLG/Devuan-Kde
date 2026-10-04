#!/usr/bin/env bash
# DEVMKDE_DESC: Copy curated per-user defaults to /etc/skel (ISO bake only — the one script that runs as root)
# DEVMKDE_DEFAULT: N
# DEVMKDE_PHASE: standalone
# =======================================================
# Export to /etc/skel
# -------------------------------------------------------
# Copies a curated set of per-user config produced by this
# toolkit into /etc/skel, so every FUTURE user account on
# that machine (and, in the ISO build, every account on the
# installed system) starts with the same defaults: fonts,
# Konsole color scheme/theme, app entries, fastfetch config.
#
# Existing files in /etc/skel are never clobbered unless
# --force is given. Run with sudo (or as root).
#
#   sudo bash scripts/52-exportToSkel.sh              # copy (as root user)
#   sudo bash scripts/52-exportToSkel.sh --user bob   # copy from bob's HOME
#   sudo bash scripts/52-exportToSkel.sh --list       # show what would be copied
#   sudo bash scripts/52-exportToSkel.sh --dry-run    # copy plan, no changes
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Which user's config to export. Default: the invoking user; when run with
# sudo that's SUDO_USER. In the ISO chroot (root, no SUDO_USER) use --user.
SOURCE_USER="${SUDO_USER:-$USER}"
MODE="copy"
FORCE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --user) SOURCE_USER="$2"; shift 2 ;;
        --list) MODE="list" ; shift ;;
        --dry-run) MODE="dry-run"; shift ;;
        --force) FORCE=1; shift ;;
        *) log_err "Unknown option: $1 (use --user, --list, --dry-run, --force)."; exit 1 ;;
    esac
done

SOURCE_HOME="$(getent passwd "$SOURCE_USER" 2>/dev/null | cut -d: -f6)"
if [ -z "$SOURCE_HOME" ] || [ ! -d "$SOURCE_HOME" ]; then
    log_err "Could not resolve a home directory for '$SOURCE_USER'. Aborting."
    exit 1
fi
SKEL="${SKEL_DIR:-/etc/skel}"

CANDIDATES=(
    "$SOURCE_HOME/.local/share/fonts"
    "$SOURCE_HOME/.local/share/icons"
    "$SOURCE_HOME/.local/share/konsole"
    "$SOURCE_HOME/.local/share/color-schemes"
    "$SOURCE_HOME/.local/share/plasma"
    "$SOURCE_HOME/.local/share/applications"
    "$SOURCE_HOME/.config/fastfetch"
    "$SOURCE_HOME/.config/fontconfig"
    "$SOURCE_HOME/.config/bash"
    "$SOURCE_HOME/.config/butterbash"
)

found=0
for src in "${CANDIDATES[@]}"; do
    [ -e "$src" ] && found=$((found + 1))
done

if [ "$found" -eq 0 ]; then
    log_warn "Nothing in the export set exists under $SOURCE_HOME yet."
    log_warn "Run the toolkit scripts first (or pick a different --user)."
    exit 0
fi

if [ "$MODE" = "list" ]; then
    echo -e "${CYAN}Would export from $SOURCE_HOME into $SKEL:${NC}"
    for src in "${CANDIDATES[@]}"; do
        [ -e "$src" ] && echo "  $src"
    done
    exit 0
fi

log_head "Exporting default config to $SKEL (user: $SOURCE_USER)"

copied=0
for src in "${CANDIDATES[@]}"; do
    [ -e "$src" ] || continue
    # Rebuild the destination path under /etc/skel (e.g. ~/.config/foo -> /etc/skel/.config/foo).
    dest="$SKEL/${src#"$SOURCE_HOME"/}"

    if [ -e "$dest" ] && [ "$FORCE" -eq 0 ]; then
        [ "$MODE" = "copy" ] && log_warn "Already in skel, not clobbering: $dest (--force to overwrite)"
        continue
    fi

    if [ "$MODE" = "copy" ]; then
        mkdir -p "$(dirname "$dest")"
        if cp -r "$src" "$dest"; then
            log_ok "  → $dest"
            copied=$((copied + 1))
        else
            log_err "  ✗ $src (copy failed)"
        fi
    else
        echo "  → $dest"
    fi
done

if [ "$MODE" = "copy" ]; then
    [ "$copied" -eq 0 ] && log_ok "Nothing new to copy."
    echo
    log_info "New accounts will inherit these defaults. Existing users are unchanged"
    log_info "(their HOME was already created without skel)."
fi

# --- .bashrc wiring ----------------------------------------------------------
# ~/.config/bash alone is dead weight without this: ButterBash's rc is only
# reached through the marked block 22-terminalButterbash.sh appends, so a new
# account would get the config files and none of the shell that loads them.
# The block is copied verbatim rather than regenerated, so skel and the source
# home can never disagree about what it contains.
BB_MARKER_BEGIN="# >>> butterbash (devuan-kde-setup 22-terminalButterbash.sh) >>>"
BB_MARKER_END="# <<< butterbash <<<"
SRC_BASHRC="$SOURCE_HOME/.bashrc"
SKEL_BASHRC="$SKEL/.bashrc"

if [ ! -f "$SRC_BASHRC" ] || ! grep -qF "$BB_MARKER_BEGIN" "$SRC_BASHRC" 2>/dev/null; then
    log_info "$SOURCE_USER has no butterbash block in .bashrc — skel .bashrc left alone."
elif [ -f "$SKEL_BASHRC" ] && grep -qF "$BB_MARKER_BEGIN" "$SKEL_BASHRC" 2>/dev/null; then
    log_info "skel .bashrc already carries the butterbash block — left alone."
elif [ "$MODE" = "dry-run" ]; then
    echo "  → $SKEL_BASHRC (butterbash block)"
else
    mkdir -p "$(dirname "$SKEL_BASHRC")"
    # awk, not sed: the markers contain characters that are regex metacharacters
    # and would need escaping that differs between sed flavours. Comparing whole
    # lines needs no pattern at all.
    if awk -v b="$BB_MARKER_BEGIN" -v e="$BB_MARKER_END" '
            $0 == b  { inside = 1; print; next }
            inside    { print; if ($0 == e) exit }
        ' "$SRC_BASHRC" >> "$SKEL_BASHRC" \
        && grep -qF "$BB_MARKER_BEGIN" "$SKEL_BASHRC" 2>/dev/null; then
        log_ok "  → $SKEL_BASHRC (butterbash block)"
    else
        log_err "  ✗ could not append the butterbash block to $SKEL_BASHRC"
    fi
fi
