#!/usr/bin/env bash
# =======================================================
# Dev Tools Extras (optional)
# -------------------------------------------------------
# A small, curated pull from ohmydebn's ingredient list
# (https://github.com/dougburks/ohmydebn, MIT licensed) — the terminal/
# developer-experience pieces that stand alone well without pulling in
# ohmydebn's heavier stack (Docker, VMs, Alacritty+Starship+Zsh as a
# whole new shell setup, Rofi, Omarchy theming). Everything here is
# additive to what installFonts.sh / terminalButterbash.sh already set
# up, not a replacement for it.
#
# Every item is its own y/N prompt — pick what's useful, skip the rest.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Dev Tools Extras"

log_info "Refreshing package lists..."
sudo apt-get update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. btop — resource monitor with a much nicer UI than top/htop.
# ---------------------------------------------------------------------------
if ask "Install btop (resource monitor)?"; then
    install_pkgs "btop" btop
fi

# ---------------------------------------------------------------------------
# 2. eza + bat — nicer ls and cat replacements. ButterBash already
#    aliases these in if present (check bash/aliases.bash), so installing
#    the binaries here is all that's needed to activate those aliases.
# ---------------------------------------------------------------------------
if ask "Install eza (modern ls) and bat (cat with syntax highlighting)?"; then
    install_pkgs "eza + bat" eza bat
    # Debian ships bat's binary as `batcat` to avoid a name clash with an
    # unrelated package — symlink it to `bat` in ~/.local/bin so
    # ButterBash's aliases (and habit) work without extra config.
    if command_exists batcat && ! command_exists bat; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        log_ok "Symlinked batcat -> ~/.local/bin/bat"
    fi
fi

# ---------------------------------------------------------------------------
# 3. zoxide — ButterBash (installed by terminalButterbash.sh) already
#    wires this up automatically if the binary is present; this just
#    installs the binary that activates it.
# ---------------------------------------------------------------------------
if ask "Install zoxide (smarter 'cd' — auto-activates in ButterBash if installed)?"; then
    install_pkgs "zoxide" zoxide
fi

# ---------------------------------------------------------------------------
# 4. Neovim + a minimal lazy.nvim starter config. Deliberately NOT LazyVim
#    or kickstart.nvim here — LazyVim currently requires Neovim >= 0.11.2
#    and kickstart.nvim >= 0.12, but Debian trixie packages Neovim 0.10.4,
#    so both would fail to bootstrap out of the box on this toolkit's
#    target system. lazy.nvim itself (just the plugin manager, no
#    framework on top) only needs >= 0.8.0, so this installs a small,
#    hand-picked, version-safe plugin set directly instead: treesitter,
#    telescope, nvim-lspconfig, gitsigns, a colorscheme, and basic
#    completion — genuinely useful, nothing that requires bleeding-edge
#    Neovim. Only lays this down if you have no existing nvim config,
#    exactly like vscodiumDevSetup.sh's starter-project behavior: never
#    touches a config you already have.
# ---------------------------------------------------------------------------
if ask "Install Neovim + a minimal lazy.nvim starter config (LSP, Treesitter, Telescope)?"; then
    install_pkgs "Neovim + build tools" neovim git curl unzip ripgrep fd-find

    NVIM_CONFIG="$HOME/.config/nvim"
    if [ -d "$NVIM_CONFIG" ]; then
        log_warn "Existing config found at \$HOME/.config/nvim — leaving it untouched (not overwriting your config)."
    else
        mkdir -p "$NVIM_CONFIG/lua"
        cat > "$NVIM_CONFIG/init.lua" << 'EOF'
-- Minimal starter config installed by devuan-kde-setup's devToolsExtras.sh.
-- Uses lazy.nvim (needs Neovim >= 0.8.0) rather than a full "distro" like
-- LazyVim/kickstart.nvim, both of which currently require a newer Neovim
-- than Debian ships. Edit freely — this is a starting point, not a framework
-- you're meant to leave untouched.

vim.g.mapleader = " "
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.expandtab = true
vim.opt.shiftwidth = 2
vim.opt.tabstop = 2
vim.opt.smartindent = true
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.termguicolors = true
vim.opt.clipboard = "unnamedplus"
vim.opt.signcolumn = "yes"
vim.opt.updatetime = 250

-- Bootstrap lazy.nvim
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

require("lazy").setup({
  { "folke/tokyonight.nvim", priority = 1000, config = function()
      vim.cmd.colorscheme("tokyonight-storm")
    end },
  { "nvim-treesitter/nvim-treesitter", build = ":TSUpdate",
    config = function()
      require("nvim-treesitter.configs").setup({
        ensure_installed = { "lua", "bash", "python", "javascript", "json", "markdown" },
        highlight = { enable = true },
      })
    end },
  { "nvim-telescope/telescope.nvim", dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find files" },
      { "<leader>fg", "<cmd>Telescope live_grep<cr>", desc = "Live grep" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
    } },
  { "neovim/nvim-lspconfig" },
  { "lewis6991/gitsigns.nvim", config = true },
  { "nvim-lualine/lualine.nvim", config = true },
})
EOF
        log_ok "Minimal Neovim config installed to ~/.config/nvim — first launch of 'nvim' will bootstrap lazy.nvim + plugins."
        log_info "Add LSP servers with, e.g., :lua vim.lsp.enable('pyright') once you install the server itself (mason.nvim is not included here — kept deliberately minimal)."
    fi

    # Debian packages the fd binary as fdfind to avoid a name clash;
    # Telescope's file-finder picker expects `fd` on PATH.
    if command_exists fdfind && ! command_exists fd; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(command -v fdfind)" "$HOME/.local/bin/fd"
        log_ok "Symlinked fdfind -> ~/.local/bin/fd"
    fi
fi

# ---------------------------------------------------------------------------
# 5. KeePassXC — password manager, the one non-dev-tool ohmydebn ingredient
#    worth including on its own merits (local-only vault, no account/cloud
#    dependency, works identically regardless of init system).
# ---------------------------------------------------------------------------
if ask "Install KeePassXC (offline password manager)?"; then
    install_pkgs "KeePassXC" keepassxc
fi

echo -e "${GREEN}Dev tools extras step complete.${NC}"
log_warn "Open a new terminal (or 'source ~/.bashrc') for new PATH entries and aliases to take effect."
