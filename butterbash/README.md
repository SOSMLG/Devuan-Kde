# 🧈 ButterBash
![Made for Debian](https://img.shields.io/badge/Made%20for-Debian-A81D33?style=for-the-badge&logo=debian&logoColor=white)
![Bash](https://img.shields.io/badge/Shell-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Stars](https://img.shields.io/gitea/stars/drew/butterbash?gitea_url=https://justaguy.dev&style=for-the-badge&logo=forgejo&logoColor=white&color=yellow&label=Stars)
![Forks](https://img.shields.io/gitea/forks/drew/butterbash?gitea_url=https://justaguy.dev&style=for-the-badge&logo=forgejo&logoColor=white&color=blue&label=Forks)
![Last Commit](https://img.shields.io/gitea/last-commit/drew/butterbash?gitea_url=https://justaguy.dev&style=for-the-badge&logo=forgejo&logoColor=white&color=green&label=Last%20Commit)

A smooth, modular Bash configuration framework that makes your shell experience butter-smooth.

## ✨ Features

- **Modular Design**: Clean separation of concerns with individual files for aliases, functions, and configurations
- **FZF Integration**: Fuzzy finding for files and processes
- **Git-Aware Prompt**: Shows current branch in your prompt
- **Extensive Aliases**: Productivity shortcuts for common tasks
- **Archive Extraction**: Universal `extract` command for all archive types
- **System Functions**: Quick system info, colored man pages, and more
- **Extension Ready**: Works with [ButterNotes](https://justaguy.dev/drew/butternotes) for note-taking and todo management

## 📦 Installation

### Recommended: Install via ButterScripts

The easiest way to install ButterBash is through the [ButterScripts](https://justaguy.dev/drew/butterscripts) optional installer:

```bash
# Clone and run butterscripts installer
git clone https://justaguy.dev/drew/butterscripts.git
cd butterscripts/setup
./optional_tools.sh
# Select option 1: ButterBash ⭐
```

ButterBash is featured as the top option in ButterScripts' optional tools, providing seamless integration with the broader ecosystem of development tools.

### Direct Install

1. Clone the repository:
```bash
git clone https://justaguy.dev/drew/butterbash.git
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

> **Important**: ButterBash will backup your existing `.bashrc` and replace it with a modular configuration. This is the intended behavior for the full ButterBash experience.

## 🗂️ Structure

```
~/.config/bash/
├── aliases.bash        # Command shortcuts
├── prompt.bash         # Custom prompt with git branch
├── keybinds.bash       # Keyboard shortcuts
├── fzf.bash           # FZF configuration
├── zoxide.bash        # zoxide smarter-cd hook
└── functions/
    ├── system.bash    # System utilities
    └── utils.bash     # General utilities
```

## 🎯 Core Functions

### Utility Functions
```bash
mkcd directory        # Create and enter directory
extract file.tar.gz   # Extract any archive type
backup file.txt       # Create timestamped backup
calc 2+2             # Quick calculations
sysinfo              # Display system information
```

## ⚙️ Configuration

### Customization

Add your own customizations by creating files in `~/.config/bash/`:

1. Create a new module: `~/.config/bash/custom.bash`
2. It will be automatically loaded on next shell start

### Local Overrides

For machine-specific settings, create `~/.bashrc.local`:
```bash
# ~/.bashrc.local
export CUSTOM_VAR="value"
alias myalias="command"

# Add custom configurations here
```

### Integration with Other Projects

ButterBash works with other projects in the ButterScripts ecosystem:
- **[ButterScripts](https://justaguy.dev/drew/butterscripts)** - Comprehensive setup scripts for Debian systems
- **[ButterNotes](https://justaguy.dev/drew/butternotes)** - Note-taking and todo management extension
- Integrates with terminal emulators like WezTerm
- Compatible with window managers (DWM, BSPWM, etc.)
- Works alongside other development tools and configurations

#### Want Note-Taking and Todo Management?

ButterBash focuses on shell configuration. For productivity features like notes and todos, install **[ButterNotes](https://justaguy.dev/drew/butternotes)**:

```bash
git clone https://justaguy.dev/drew/butternotes.git
cd butternotes && ./install.sh
```

ButterNotes works alongside ButterBash and adds:
- Intelligent note-taking with clipboard integration
- Todo management with markdown checkboxes
- Project organization with FZF
- Mobile sync compatibility
- Interactive terminal UI

## 🚀 Key Bindings

- **Ctrl+L**: Clear screen
- **↑/↓**: Search command history
- **Ctrl+R**: Reverse history search (with FZF if available)

## 📋 Requirements

- Bash 4.0+
- `install.sh` pulls in the tools the config uses: `fzf`, `ripgrep`, `eza`, `zoxide`.
  - `fzf` - Fuzzy finder
  - `ripgrep` - Fast grep alternative
  - `eza` or `exa` - Modern ls replacement
  - `zoxide` - Smarter cd (`z`, `zi`)
- Optional clipboard integration (not pulled in automatically):
  - `xclip` (X11) / `wl-clipboard` (Wayland)

If you ever need to reinstall the core tools, there's a built-in helper:
```bash
install_tools  # reinstalls fzf and ripgrep
```

## 🤝 Contributing

Contributions are welcome! Please visit our [Butterforge repository](https://justaguy.dev/drew/butterbash) to:

- Report issues: https://justaguy.dev/drew/butterbash/issues
- Submit pull requests
- Join discussions

For major changes, please open an issue first to discuss your ideas.

## License

GPL-2.0 - See [LICENSE](LICENSE) for details.

## Support

<a href="https://www.buymeacoffee.com/justaguylinux" target="_blank"><img src="https://www.buymeacoffee.com/assets/img/custom_images/orange_img.png" alt="Buy me a coffee" /></a>

## Connect

- [YouTube](https://youtube.com/@justaguylinux) — tutorials and guides
- [Butterforge](https://justaguy.dev/drew) — source code and projects
- [The Butter Lab](https://lab.justaguylinux.com) — Discourse forum
- [The Churn](https://justaguylinux.chat) — community chat (Fluxer)
- [Wiki](https://justaguy.wiki) — documentation and guides
- [Mastodon](https://fosstodon.org/@justaguylinux) — @justaguylinux@fosstodon.org
- [Butterbian](https://butterbian.org) — a Debian-based distro

---

Made with butter by JustAGuyLinux
