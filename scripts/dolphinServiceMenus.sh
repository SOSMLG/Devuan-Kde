#!/usr/bin/env bash
# =======================================================
# Dolphin Service Menus — right-click context menu additions
# -------------------------------------------------------
# Recreates the most useful right-click moments from the appearance
# videos (one-click PDF compression, one-click image compression, "Open
# in VS Code") written directly rather than copied from any third-party
# action pack — these are simple enough that writing them ourselves means
# no dependency on an external action's exact current behavior, and it
# means "Open in OpenCode" can exist at all (nobody's published a plugin
# for a tool that didn't exist when most of those were written).
#
# Each action is a small wrapper script in ~/.local/bin (so the logic is
# one command, easy to read/edit) plus a KDE service-menu .desktop file
# in ~/.local/share/kio/servicemenus/ (the Dolphin equivalent of Nemo
# Actions — the same concept, native file format, works on KDE Plasma).
# Dolphin picks up new service menus on its next launch; if one doesn't
# show up, close all Dolphin windows and reopen.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Dolphin Service Menus"

log_info "Refreshing package lists..."
sudo apt-get update || { log_err "apt-get update failed, aborting."; exit 1; }

BIN_DIR="$HOME/.local/bin"
MENUS_DIR="$HOME/.local/share/kio/servicemenus"
mkdir -p "$BIN_DIR" "$MENUS_DIR"

INSTALLED_ANY=0

# ---------------------------------------------------------------------------
# 1. Compress PDF (Ghostscript, /ebook preset — a solid size/quality
#    balance, same idea as the videos' one-click PDF shrink).
# ---------------------------------------------------------------------------
if ask "Add 'Compress PDF' to the right-click menu (Ghostscript)?"; then
    install_pkgs "Ghostscript" ghostscript

    cat > "$BIN_DIR/devuan-compress-pdf.sh" << 'EOF'
#!/usr/bin/env bash
# Compresses each given PDF to "<name>-compressed.pdf" alongside the original.
set -uo pipefail
OK=0; FAIL=0
for f in "$@"; do
    [ -f "$f" ] || continue
    out="${f%.pdf}-compressed.pdf"
    if gs -sDEVICE=pdfwrite -dCompatibilityLevel=1.4 -dPDFSETTINGS=/ebook \
          -dNOPAUSE -dQUIET -dBATCH -sOutputFile="$out" "$f" 2>/dev/null; then
        OK=$((OK+1))
    else
        FAIL=$((FAIL+1))
    fi
done
if command -v notify-send >/dev/null 2>&1; then
    notify-send -i application-pdf "PDF compression done" "${OK} compressed, ${FAIL} failed." 2>/dev/null || true
fi
EOF
    chmod +x "$BIN_DIR/devuan-compress-pdf.sh"

    cat > "$MENUS_DIR/devuan-compress-pdf.desktop" << EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=application/pdf;
Actions=compressPdf;
X-KDE-Priority=TopLevel

[Desktop Action compressPdf]
Name=Compress PDF
Comment=Shrink this PDF with Ghostscript
Icon=application-pdf
Exec=$BIN_DIR/devuan-compress-pdf.sh %F
EOF
    log_ok "'Compress PDF' added."
    INSTALLED_ANY=1
fi

# ---------------------------------------------------------------------------
# 2. Compress Image (ImageMagick, quality 85 — visually lossless for
#    photos, meaningfully smaller files).
# ---------------------------------------------------------------------------
if ask "Add 'Compress Image' to the right-click menu (ImageMagick)?"; then
    install_pkgs "ImageMagick" imagemagick

    cat > "$BIN_DIR/devuan-compress-image.sh" << 'EOF'
#!/usr/bin/env bash
# Compresses each given image to "<name>-compressed.<ext>" alongside the original.
set -uo pipefail
OK=0; FAIL=0
for f in "$@"; do
    [ -f "$f" ] || continue
    ext="${f##*.}"
    base="${f%.*}"
    out="${base}-compressed.${ext}"
    if convert "$f" -strip -quality 85 "$out" 2>/dev/null; then
        OK=$((OK+1))
    else
        FAIL=$((FAIL+1))
    fi
done
if command -v notify-send >/dev/null 2>&1; then
    notify-send -i image-x-generic "Image compression done" "${OK} compressed, ${FAIL} failed." 2>/dev/null || true
fi
EOF
    chmod +x "$BIN_DIR/devuan-compress-image.sh"

    cat > "$MENUS_DIR/devuan-compress-image.desktop" << EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=image/jpeg;image/png;image/webp;image/bmp;image/tiff;
Actions=compressImage;
X-KDE-Priority=TopLevel

[Desktop Action compressImage]
Name=Compress Image
Comment=Shrink this image with ImageMagick (quality 85)
Icon=image-x-generic
Exec=$BIN_DIR/devuan-compress-image.sh %F
EOF
    log_ok "'Compress Image' added."
    INSTALLED_ANY=1
fi

# ---------------------------------------------------------------------------
# 3. Open in VS Code — right-click a folder, open it as a VS Code
#    workspace. Only shows up if VSCodium/VS Code is actually on PATH.
# ---------------------------------------------------------------------------
if ask "Add 'Open in VS Code' to folder right-click menus?"; then
    CODE_BIN=""
    for candidate in code codium; do
        command_exists "$candidate" && CODE_BIN="$candidate" && break
    done
    if [ -z "$CODE_BIN" ]; then
        log_warn "Neither 'code' nor 'codium' found on PATH — install VSCodium first (scripts/installVscodium.sh),"
        log_warn "then re-run this step. Skipping for now."
    else
        cat > "$BIN_DIR/devuan-open-vscode.sh" << EOF
#!/usr/bin/env bash
# Opens the given folder(s) in VS Code / VSCodium.
set -uo pipefail
exec $CODE_BIN "\$@"
EOF
        chmod +x "$BIN_DIR/devuan-open-vscode.sh"

        cat > "$MENUS_DIR/devuan-open-vscode.desktop" << EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;
Actions=openVScode;
X-KDE-Priority=TopLevel

[Desktop Action openVScode]
Name=Open in VS Code
Comment=Open this folder in VS Code / VSCodium
Icon=vscodium
Exec=$BIN_DIR/devuan-open-vscode.sh %f
EOF
        log_ok "'Open in VS Code' added (using '$CODE_BIN')."
        INSTALLED_ANY=1
    fi
fi

# ---------------------------------------------------------------------------
# 4. Open in OpenCode — right-click a folder, open a terminal there
#    running OpenCode. The one action here with no video/plugin precedent
#    — ties directly into aiOpencode.sh. Uses Dolphin's Terminal=true so
#    no x-terminal-emulator guess is needed.
# ---------------------------------------------------------------------------
if ask "Add 'Open in OpenCode' to folder right-click menus?"; then
    if ! command_exists opencode; then
        log_warn "'opencode' not found on PATH — install it first (scripts/aiOpencode.sh), then re-run this step."
        log_warn "Adding the menu entry anyway; it just won't do anything until OpenCode is installed."
    fi

    cat > "$BIN_DIR/devuan-open-opencode.sh" << 'EOF'
#!/usr/bin/env bash
# Opens OpenCode in the given directory (from a Dolphin Terminal=true
# service menu, so this runs inside a terminal emulator).
set -uo pipefail
DIR="${1:-$HOME}"
cd "$DIR" || exit 1
exec opencode
EOF
    chmod +x "$BIN_DIR/devuan-open-opencode.sh"

    cat > "$MENUS_DIR/devuan-open-opencode.desktop" << EOF
[Desktop Entry]
Type=Service
ServiceTypes=KonqPopupMenu/Plugin
MimeType=inode/directory;
Actions=openOpencode;
X-KDE-Priority=TopLevel
Terminal=true

[Desktop Action openOpencode]
Name=Open in OpenCode
Comment=Open a terminal here running the OpenCode AI agent
Icon=utilities-terminal
Exec=$BIN_DIR/devuan-open-opencode.sh %f
EOF
    log_ok "'Open in OpenCode' added."
    INSTALLED_ANY=1
fi

if [ "$INSTALLED_ANY" -eq 1 ]; then
    echo -e "${GREEN}Dolphin Service Menus step complete.${NC}"
    log_warn "If a new menu doesn't show up in the right-click menu right away, close all Dolphin"
    log_warn "windows and reopen — KDE loads service menus on Dolphin launch (no daemon to restart)."
else
    log_info "Nothing selected — nothing changed."
fi