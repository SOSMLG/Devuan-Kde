# ButterBash

A modular Bash configuration framework: aliases, functions, a Git-aware prompt, and optional tool integration.

## Features

- **Modular design**: Separate files for aliases, functions and configuration.
- **FZF integration**: Fuzzy finding for files and processes.
- **Git-aware prompt**: Shows the current branch in your prompt.
- **Aliases**: Shortcuts for common tasks.
- **Archive extraction**: One `extract` command for all archive types.
- **System functions**: Quick system info, colored man pages and more.
- **Extension ready**: Works with [ButterNotes](https://codeberg.org/justaguylinux/butternotes) for notes and todos.

## Installation

### Recommended: install via ButterScripts

Install ButterBash through the [ButterScripts](https://codeberg.org/justaguylinux/butterscripts) optional installer:

```bash
git clone https://codeberg.org/justaguylinux/butterscripts.git
cd butterscripts/setup
./optional_tools.sh
# Select option 1: ButterBash
```

ButterBash is the first option in ButterScripts' optional tools and fits the wider development tool set.

### Direct install

1. Clone the repository:

```bash
git clone https://codeberg.org/justaguylinux/butterbash.git
cd butterbash
```

2. Run the install script:

```bash
./install.sh
```

3. Reload your shell:

```bash
source ~/.bashrc
```

> **Important**: ButterBash backs up your existing `.bashrc` and replaces it with a modular configuration. This is the intended behavior for the full ButterBash setup.

## Structure

```
~/.config/bash/
├── aliases.bash        # Command shortcuts
├── prompt.bash         # Custom prompt with git branch
├── keybinds.bash       # Keyboard shortcuts
├── fzf.bash            # FZF configuration
├── zoxide.bash         # zoxide smarter-cd hook
└── functions/
    ├── system.bash     # System utilities
    └── utils.bash      # General utilities
```

## Core functions

```bash
mkcd directory        # Create and enter directory
extract file.tar.gz   # Extract any archive type
backup file.txt       # Create timestamped backup
calc 2+2              # Quick calculations
sysinfo               # Display system information
```

## Configuration

### Customization

Add your own customizations by creating files in `~/.config/bash/`:

1. Create a new module: `~/.config/bash/custom.bash`
2. It loads automatically on the next shell start.

### Local overrides

For machine-specific settings, create `~/.bashrc.local`:

```bash
# ~/.bashrc.local
export CUSTOM_VAR="value"
alias myalias="command"

# Add custom configurations here
```

### Integration with other projects

ButterBash works with other projects in the ButterScripts ecosystem:

- **[ButterScripts](https://codeberg.org/justaguylinux/butterscripts)** - Setup scripts for Debian systems.
- **[ButterNotes](https://codeberg.org/justaguylinux/butternotes)** - Notes and todo management.
- Terminal emulators such as WezTerm.
- Window managers such as dwm and bspwm.
- Other development tools and configurations.

#### Notes and todo management

ButterBash focuses on shell configuration. For notes and todos, install **[ButterNotes](https://codeberg.org/justaguylinux/butternotes)**:

```bash
git clone https://codeberg.org/justaguylinux/butternotes.git
cd butternotes && ./install.sh
```

ButterNotes works alongside ButterBash and adds:

- Note-taking with clipboard integration.
- Todo management with Markdown checkboxes.
- Project organization with FZF.
- Mobile sync compatibility.
- Interactive terminal UI.

## Key bindings

- **Ctrl+L**: Clear screen.
- **Up/Down**: Search command history.
- **Ctrl+R**: Reverse history search (with FZF if available).

## Requirements

- Bash 4.0+
- `install.sh` pulls in the tools the config uses: `fzf`, `ripgrep`, `eza`, `zoxide`.
  - `fzf` - Fuzzy finder.
  - `ripgrep` - Fast grep alternative.
  - `eza` or `exa` - Modern `ls` replacement.
  - `zoxide` - Smarter `cd` (`z`, `zi`).
- Optional clipboard integration (not pulled in automatically):
  - `xclip` (X11) or `wl-clipboard` (Wayland).

To reinstall the core tools:

```bash
install_tools  # reinstalls fzf and ripgrep
```

## Contributing

Contributions are welcome. Visit the [Codeberg repository](https://codeberg.org/justaguylinux/butterbash) to:

- Report issues: https://codeberg.org/justaguylinux/butterbash/issues
- Submit pull requests.
- Join discussions.

For major changes, open an issue first.

## License

GPL-2.0. See [LICENSE](LICENSE) for details.

## Support

[Buy me a coffee](https://www.buymeacoffee.com/justaguylinux)

## Connect

- [YouTube](https://youtube.com/@justaguylinux) - tutorials and guides.
- [Codeberg](https://codeberg.org/justaguylinux) - source code and projects.
- [The Butter Lab](https://lab.justaguylinux.com) - Discourse forum.
- [The Churn](https://justaguylinux.chat) - community chat (Fluxer).
- [Wiki](https://justaguy.wiki) - documentation and guides.
- [Mastodon](https://fosstodon.org/@justaguylinux) - @justaguylinux@fosstodon.org.
- [Butterbian](https://butterbian.org) - a Debian-based distro.

---

Made with butter by JustAGuyLinux.
