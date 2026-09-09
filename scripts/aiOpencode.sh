#!/usr/bin/env bash
# =======================================================
# AI: OpenCode
# -------------------------------------------------------
# Installs OpenCode (https://opencode.ai) — an open-source, terminal-based
# AI coding agent that works with Claude, GPT, Gemini, and other providers
# (bring your own API key, or use its free tier). This is the one piece
# cherry-picked wholesale from ohmydebn (https://github.com/dougburks/ohmydebn,
# MIT licensed) rather than reimplemented — same tool, same idea (a
# Super+A hotkey that installs-then-launches on first press), adapted
# here to run under a terminal emulator instead of Alacritty specifically,
# since this toolkit doesn't install a specific terminal for you.
#
# Also drops a small "skill" file describing this system, in the format
# OpenCode (and Claude Code, if you use it too) can read for repo/system
# context — same concept as ohmydebn's own AI skill file.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "AI: OpenCode"

if command_exists opencode; then
    log_ok "OpenCode already installed ($(opencode --version 2>/dev/null || echo 'version unknown'))."
else
    echo -e "${CYAN}OpenCode can be installed two ways:${NC}"
    echo "  1) Official script: curl -fsSL https://opencode.ai/install | bash"
    echo "     (downloads a prebuilt binary straight from opencode.ai — fastest, but"
    echo "      piping curl to bash means trusting that script sight-unseen)"
    echo "  2) npm: npm install -g opencode-ai"
    echo "     (goes through the npm registry instead — needs Node.js/npm installed first)"
    echo
    read -rp "$(echo -e "${YELLOW}Install via [1] official script, [2] npm, or [N] skip? (1/2/N): ${NC}")" METHOD

    case "$METHOD" in
        1)
            log_info "Running the official OpenCode installer..."
            if curl -fsSL https://opencode.ai/install | bash; then
                log_ok "OpenCode installed."
            else
                log_err "OpenCode installation failed."
            fi
            ;;
        2)
            if ! command_exists npm; then
                log_info "npm not found — installing Node.js LTS + npm first."
                install_pkgs "Node.js + npm" nodejs npm
            fi
            if command_exists npm; then
                log_info "Installing opencode-ai via npm..."
                if sudo npm install -g opencode-ai; then
                    log_ok "OpenCode installed via npm."
                else
                    log_err "npm install failed."
                fi
            else
                log_err "npm still not available — skipping."
            fi
            ;;
        *)
            log_warn "Skipped OpenCode installation."
            ;;
    esac
fi

# Make sure ~/.opencode/bin (the official installer's default location) or
# $HOME/bin is on PATH for future shells, without duplicating the line.
for CANDIDATE in "$HOME/.opencode/bin" "$HOME/bin"; do
    if [ -d "$CANDIDATE" ] && ! grep -qF "$CANDIDATE" "$HOME/.bashrc" 2>/dev/null; then
        echo "export PATH=\"$CANDIDATE:\$PATH\"" >> "$HOME/.bashrc"
        log_ok "Added $CANDIDATE to PATH in ~/.bashrc"
    fi
done

# ---------------------------------------------------------------------------
# Hotkey: Super+A -> open a terminal running opencode.
#
# KDE's global shortcuts are NOT gsettings/dconf (that's Cinnamon/GNOME) —
# they're kglobalaccel, driven by ~/.config/kglobalshortcutsrc plus a
# matching .desktop launcher. This is the same mechanism System Settings'
# own Shortcuts > "Add Command..." button uses under the hood (verified
# against https://github.com/nix-community/plasma-manager/issues/18 and a
# second independent write-up, both showing the identical file format):
#
#   ~/.local/share/applications/<name>.desktop:
#     [Desktop Entry]
#     Exec=<command>
#     Name=<name>
#     NoDisplay=true
#     StartupNotify=false
#     Type=Application
#     X-KDE-GlobalAccel-CommandShortcut=true
#
#   ~/.config/kglobalshortcutsrc:
#     [<name>.desktop]
#     _k_friendly_name=<name>
#     _launch=<key-sequence>,none,<name>
#
# kglobalaccel reads this at login, not live — like this toolkit's other
# KDE config writes (KRunner centering, etc.), this takes effect at your
# next login, not immediately.
# ---------------------------------------------------------------------------
if [ -n "$KWRITECONFIG" ] && ask "Bind Super+A to launch OpenCode in a terminal?"; then
    DESKTOP_NAME="opencode-shortcut"
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"

    cat > "$APPS_DIR/${DESKTOP_NAME}.desktop" << EOF
[Desktop Entry]
Exec=x-terminal-emulator -e opencode
Name=OpenCode AI
NoDisplay=true
StartupNotify=false
Type=Application
X-KDE-GlobalAccel-CommandShortcut=true
EOF

    kwrite_user --file kglobalshortcutsrc --group "${DESKTOP_NAME}.desktop" \
        --key "_k_friendly_name" "OpenCode AI"
    kwrite_user --file kglobalshortcutsrc --group "${DESKTOP_NAME}.desktop" \
        --key "_launch" "Meta+A,none,OpenCode AI"

    log_ok "Super+A will launch OpenCode in a terminal — takes effect at your next login"
    log_ok "(kglobalaccel reads shortcuts at session start, not live)."
    log_info "Already bound to something else? Reassign it yourself in System Settings > Shortcuts >"
    log_info "search 'OpenCode AI', or edit ~/.config/kglobalshortcutsrc directly."
else
    log_info "Skipped the hotkey — bind it manually later via System Settings > Shortcuts > Add Command"
    log_info "(command: x-terminal-emulator -e opencode) if you want it."
fi

# ---------------------------------------------------------------------------
# System skill file — same idea as ohmydebn's own "skill that all these AI
# tools can use to understand the underlying platform." OpenCode and
# Claude Code both look for AGENTS.md / CLAUDE.md / a skills directory
# depending on version; this drops a plain, tool-agnostic markdown file
# in both common locations so whichever one you use picks it up.
# ---------------------------------------------------------------------------
if ask "Install a system 'skill' file so AI tools know this is a Devuan/KDE Plasma box?"; then
    SKILL_SRC="$SCRIPT_DIR/../skills/devuan-kde-SKILL.md"
    if [ -f "$SKILL_SRC" ]; then
        mkdir -p "$HOME/.config/opencode"
        cp "$SKILL_SRC" "$HOME/.config/opencode/AGENTS.md" 2>/dev/null \
            && log_ok "Installed to ~/.config/opencode/AGENTS.md"
        if [ ! -f "$HOME/AGENTS.md" ]; then
            cp "$SKILL_SRC" "$HOME/AGENTS.md" 2>/dev/null \
                && log_ok "Also installed to ~/AGENTS.md (picked up by most terminal AI agents run from \$HOME)."
        fi
    else
        log_warn "Skill file not found at $SKILL_SRC — skipping."
    fi
fi

echo -e "${GREEN}AI (OpenCode) step complete.${NC}"
log_info "Run 'opencode auth login' once to connect a provider (or use its free tier), then just 'opencode' to start."
