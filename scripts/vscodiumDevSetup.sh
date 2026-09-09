#!/usr/bin/env bash
# =======================================================
# VSCodium — C++ & Python dev setup (optional)
# -------------------------------------------------------
# Two Microsoft extensions people expect from real VS Code
# do NOT work on VSCodium, so this uses the extensions the
# VSCodium community actually settled on instead:
#
#   - ms-vscode.cpptools (C/C++) is license-blocked from
#     running on VSCodium since April 2025 (Microsoft added
#     a runtime check to the compiled binary). Using clangd
#     + CodeLLDB instead — open-source, on Open VSX, and
#     arguably better on Linux/GCC-Clang projects anyway.
#   - Pylance is closed-source and Microsoft has confirmed
#     it will never be on Open VSX. Using basedpyright
#     instead — an open-source Pyright fork that reimplements
#     most of Pylance's IntelliSense features.
#
# Installs:
#   C++:    clangd, clang-format, gdb, build-essential, cmake
#           + llvm-vs-code-extensions.vscode-clangd, vadimcn.vscode-lldb,
#             twxs.cmake, jeff-hykin.better-cpp-syntax
#   Python: python3-venv/pip
#           + ms-python.python, ms-python.debugpy,
#             detachhead.basedpyright, charliermarsh.ruff
#
# Then writes safe defaults into VSCodium's user settings.json
# (merged, never overwritten — your existing settings are kept)
# and drops a tiny starter project with a working build+debug
# config for both languages, so F5 just works out of the box.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

install_ext() {
    local id="$1"
    log_info "Installing extension: $id"
    if codium --install-extension "$id" --force > /dev/null 2>&1; then
        log_ok "  $id"
    else
        log_warn "  Failed to install $id (continuing)."
    fi
}

if [[ $EUID -eq 0 ]]; then
    log_err "Do not run this as root — it needs to write to your own \$HOME."
    log_err "Run it as your normal user; it will call sudo itself when needed."
    exit 1
fi

echo -e "${CYAN}=========================================================${NC}"
echo -e "${CYAN} VSCodium — C++ & Python dev setup${NC}"
echo -e "${CYAN}=========================================================${NC}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# 0. Make sure VSCodium itself is installed
# ---------------------------------------------------------------------------
if ! command -v codium >/dev/null 2>&1; then
    log_info "VSCodium not found, installing it first..."
    if [ -f "$SCRIPT_DIR/installVscodium.sh" ]; then
        bash "$SCRIPT_DIR/installVscodium.sh" || { log_err "VSCodium install failed, aborting."; exit 1; }
    else
        log_err "codium is not installed and installVscodium.sh is missing from $SCRIPT_DIR."
        exit 1
    fi
fi

log_info "Refreshing package lists..."
apt_update || { log_err "apt-get update failed, aborting."; exit 1; }

# ---------------------------------------------------------------------------
# 1. C++ toolchain + extensions
# ---------------------------------------------------------------------------
if ask "Set up C++ (clangd + CodeLLDB, since Microsoft's cpptools is blocked on VSCodium)?"; then
    install_pkgs "C++ toolchain" build-essential gdb clangd clang-format cmake

    install_ext "llvm-vs-code-extensions.vscode-clangd"
    install_ext "vadimcn.vscode-lldb"
    install_ext "twxs.cmake"
    install_ext "jeff-hykin.better-cpp-syntax"
fi

# ---------------------------------------------------------------------------
# 2. Python toolchain + extensions
# ---------------------------------------------------------------------------
if ask "Set up Python (basedpyright + Ruff, since Pylance is closed-source and blocked on Open VSX)?"; then
    install_pkgs "Python toolchain" python3 python3-pip python3-venv

    install_ext "ms-python.python"
    install_ext "ms-python.debugpy"
    install_ext "detachhead.basedpyright"
    install_ext "charliermarsh.ruff"
fi

# ---------------------------------------------------------------------------
# 3. VSCodium user settings — merged safely, never overwritten
# ---------------------------------------------------------------------------
if ask "Apply recommended settings (disable duplicate Python language server, format-on-save, etc.)?"; then
    SETTINGS_DIR="$HOME/.config/VSCodium/User"
    SETTINGS_FILE="$SETTINGS_DIR/settings.json"
    mkdir -p "$SETTINGS_DIR"

    if [ -f "$SETTINGS_FILE" ]; then
        BACKUP="${SETTINGS_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        cp "$SETTINGS_FILE" "$BACKUP"
        log_info "Existing settings.json backed up to $BACKUP"
    else
        echo "{}" > "$SETTINGS_FILE"
    fi

    if python3 - "$SETTINGS_FILE" << 'PYEOF'
import json, sys

path = sys.argv[1]
with open(path) as f:
    content = f.read().strip()
data = json.loads(content) if content else {}

defaults = {
    # basedpyright replaces Pylance; ms-python.python's own "Pylance" /
    # "Jedi" language server must be turned off or you get duplicate
    # diagnostics (this is basedpyright's own documented requirement).
    "python.languageServer": "None",
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "editor.formatOnSave": True,
    "[python]": {"editor.defaultFormatter": "charliermarsh.ruff"},
    "[cpp]": {"editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"},
    "[c]": {"editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"},
    "clangd.arguments": ["--header-insertion=never"],
}

# Only fill in keys the user doesn't already have; never clobber existing values.
changed = False
for key, value in defaults.items():
    if key not in data:
        data[key] = value
        changed = True
    elif isinstance(value, dict) and isinstance(data.get(key), dict):
        for subkey, subvalue in value.items():
            if subkey not in data[key]:
                data[key][subkey] = subvalue
                changed = True

with open(path, "w") as f:
    json.dump(data, f, indent=4)
    f.write("\n")

print("changed" if changed else "unchanged")
PYEOF
    then
        log_ok "settings.json updated at $SETTINGS_FILE"
    else
        log_err "Failed to update settings.json (backup is safe at ${BACKUP:-N/A})."
    fi
fi

# ---------------------------------------------------------------------------
# 4. Starter project — a working build+debug config for both languages
# ---------------------------------------------------------------------------
if ask "Create a starter project at ~/Projects/vscodium-starter with working build+debug configs?"; then
    PROJ_DIR="$HOME/Projects/vscodium-starter"
    if [ -d "$PROJ_DIR" ]; then
        log_warn "$PROJ_DIR already exists, leaving it untouched."
    else
        mkdir -p "$PROJ_DIR/.vscode"

        cat > "$PROJ_DIR/main.cpp" << 'EOF'
#include <iostream>

int main() {
    std::cout << "Hello from C++ — build with Ctrl+Shift+B, debug with F5\n";
    return 0;
}
EOF

        cat > "$PROJ_DIR/main.py" << 'EOF'
def main():
    print("Hello from Python — debug with F5")


if __name__ == "__main__":
    main()
EOF

        # Lets clangd give correct diagnostics/completion without a full
        # CMake project — just plain flags for a single translation unit.
        cat > "$PROJ_DIR/compile_flags.txt" << 'EOF'
-std=c++17
-Wall
-Wextra
-g
EOF

        cat > "$PROJ_DIR/.vscode/tasks.json" << 'EOF'
{
    "version": "2.0.0",
    "tasks": [
        {
            "label": "build main.cpp",
            "type": "shell",
            "command": "g++",
            "args": ["-std=c++17", "-Wall", "-Wextra", "-g", "main.cpp", "-o", "main"],
            "group": { "kind": "build", "isDefault": true },
            "problemMatcher": ["$gcc"]
        }
    ]
}
EOF

        cat > "$PROJ_DIR/.vscode/launch.json" << 'EOF'
{
    "version": "0.2.0",
    "configurations": [
        {
            "name": "C++: build & debug main.cpp",
            "type": "lldb",
            "request": "launch",
            "program": "${workspaceFolder}/main",
            "args": [],
            "cwd": "${workspaceFolder}",
            "preLaunchTask": "build main.cpp"
        },
        {
            "name": "Python: debug main.py",
            "type": "debugpy",
            "request": "launch",
            "program": "${workspaceFolder}/main.py",
            "console": "integratedTerminal"
        }
    ]
}
EOF

        cat > "$PROJ_DIR/.vscode/settings.json" << 'EOF'
{
    "python.defaultInterpreterPath": "/usr/bin/python3"
}
EOF

        log_ok "Starter project created at $PROJ_DIR"
        log_info "Open it with: codium $PROJ_DIR"
    fi
fi

echo -e "${GREEN}VSCodium C++/Python dev setup complete.${NC}"
log_warn "First launch tip: if basedpyright and ms-python.python's built-in language server both light up, reload the window once (Ctrl+Shift+P > Reload Window) so the 'python.languageServer: None' setting takes effect."
