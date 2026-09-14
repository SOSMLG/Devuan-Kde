#!/usr/bin/env bash
# =======================================================
# Hotkeys — Plasma custom keyboard shortcuts
# -------------------------------------------------------
# Plasma's own defaults (Super opens the launcher, Alt+Tab to switch,
# Ctrl+Alt+T for Konsole, Meta+E for Dolphin, screenshot keys, etc.) are
# left alone — this only *adds* a small set of bindings for one-key
# access to terminal, file manager, editor, and system monitor.
#
# Idempotent: each binding is keyed by a fixed UUID, so re-running this
# merges into your existing config rather than stacking duplicates. If a
# UUID already exists in ~/.config/khotkeysrc it is left untouched.
#
# Mechanism (two files KHotkeys keeps in sync):
#   ~/.config/khotkeysrc          — the action definitions (what the
#                                    trigger runs) + the trigger UUID.
#   ~/.config/kglobalshortcutsrc  — the assigned key for each UUID under
#                                    the [khotkeys] group.
# Both are written here with kwriteconfig, exactly like System Settings >
# Shortcuts > Custom Shortcuts would save them. Note: the KHotkeys daemon
# is unmaintained upstream after Plasma 5.27, so on a (future) Plasma 6
# box the entries may be inert until Plasma's replacement picks them up —
# this toolkit targets Devuan's Plasma 5.27, where it works.
# =======================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

require_not_root
log_head "Hotkeys"

# name|command|key|fixed-uuid
BINDINGS=(
    "Terminal|konsole|Meta+Return|d0ab0217-5a06-4e7f-9f1d-0f27c14b8d01"
    "File Manager|dolphin|Meta+f|d0ab0217-5a06-4e7f-9f1d-0f27c14b8d02"
    "Text Editor|kate|Ctrl+Meta+e|d0ab0217-5a06-4e7f-9f1d-0f27c14b8d03"
    "System Monitor|ksysguard|Ctrl+Shift+Escape|d0ab0217-5a06-4e7f-9f1d-0f27c14b8d04"
)

log_info "This will add ${#BINDINGS[@]} custom shortcuts to your Plasma session:"
for b in "${BINDINGS[@]}"; do
    IFS='|' read -r name cmd key uuid <<< "$b"
    echo -e "   ${CYAN}${key}${NC} -> ${name} (${cmd})"
done
echo

if ! ask "Apply these shortcuts now?"; then
    log_warn "Skipped."
    exit 0
fi

# kwriteconfig binary — kwriteconfig6 on Plasma 6, kwriteconfig5 elsewhere.
if command_exists kwriteconfig6; then
    KC=kwriteconfig6
    KR=kreadconfig6
elif command_exists kwriteconfig5; then
    KC=kwriteconfig5
    KR=kreadconfig5
else
    log_err "kwriteconfig not found — is this a KDE Plasma session?"
    exit 1
fi

ADDED=0
KHOT="$HOME/.config/khotkeysrc"

# KHotkeys only parses top-level groups named Data_<n>, tracked by the
# [Data] group's DataCount. Take the first free numeric slot so we never
# collide with existing/leftover groups, and bump DataCount so the parser
# reaches ours.
G_NUM=0
for n in $(seq 1 64); do
    if [ "$("$KR" --file khotkeysrc --group "Data_${n}" --key "Name" 2>/dev/null)" = "" ]; then
        G_NUM=$n
        break
    fi
done
if [ "$G_NUM" -eq 0 ]; then
    log_err "Could not find a free Data_<n> slot in khotkeysrc."
    exit 1
fi
G="Data_${G_NUM}"

"$KC" --file khotkeysrc --group "Data" --key "DataCount" "$G_NUM"
log_info "Using group '$G' in khotkeysrc for devuan-kde-setup shortcuts."

# ---------------------------------------------- one shared top-level group
"$KC" --file khotkeysrc --group "$G" --key "Type" "ACTION_DATA_GROUP"
"$KC" --file khotkeysrc --group "$G" --key "Comment" "Shortcuts added by devuan-kde-setup"
"$KC" --file khotkeysrc --group "$G" --key "Enabled" "true"
"$KC" --file khotkeysrc --group "$G" --key "SystemGroup" "0"
"$KC" --file khotkeysrc --group "$G" --key "ImportId" "devuan-kde-setup"
"$KC" --file khotkeysrc --group "${G}Conditions" --key "ConditionsCount" "0"

slot=0
for b in "${BINDINGS[@]}"; do
    slot=$((slot+1))
    IFS='|' read -r name cmd key uuid <<< "$b"
    id="{${uuid}}"

    # Idempotence: this binding's fixed UUID already recorded → untouched.
    if grep -qF "$id" "$KHOT" 2>/dev/null; then
        log_warn "  $name: already present, leaving untouched."
        continue
    fi

    # ------------------------------------------------ action definition
    # Each binding owns the child slot matching its position in BINDINGS,
    # so re-runs never create duplicates and slots never collide.
    local_idx="$slot"
    A="$G"_"$local_idx"

    "$KC" --file khotkeysrc --group "$A" --key "Type" "SIMPLE_ACTION_DATA"
    "$KC" --file khotkeysrc --group "$A" --key "Name" "$name"
    "$KC" --file khotkeysrc --group "$A" --key "Comment" "devuan-kde-setup: $name"
    "$KC" --file khotkeysrc --group "$A" --key "Enabled" "true"
    "$KC" --file khotkeysrc --group "${A}Actions" --key "ActionsCount" "1"
    "$KC" --file khotkeysrc --group "${A}Actions0" --key "CommandURL" "$cmd"
    "$KC" --file khotkeysrc --group "${A}Actions0" --key "Type" "COMMAND_URL"
    "$KC" --file khotkeysrc --group "${A}Conditions" --key "ConditionsCount" "0"
    "$KC" --file khotkeysrc --group "${A}Triggers" --key "TriggersCount" "1"
    "$KC" --file khotkeysrc --group "${A}Triggers0" --key "Key" "$key"
    "$KC" --file khotkeysrc --group "${A}Triggers0" --key "Type" "SHORTCUT"
    "$KC" --file khotkeysrc --group "${A}Triggers0" --key "Uuid" "$id"

    # --------------------------------------------- assigned key binding
    "$KC" --file kglobalshortcutsrc --group "khotkeys" --key "$id" "$key,none,$name"

    # keep the parent group's child counter in sync
    "$KC" --file khotkeysrc --group "$G" --key "DataCount" "$local_idx"

    log_ok "  Added $key -> $name ($cmd)"
    ADDED=$((ADDED+1))
done

if [ "$ADDED" -eq 0 ]; then
    log_warn "Nothing new to add — all bindings already present."
else
    # KHotkeys picks up khotkeysrc changes by restarting the daemon; if
    # there's no running session it simply applies at next login.
    if pgrep -x khotkeys >/dev/null 2>&1; then
        if command_exists kquitapp6 && kquitapp6 khotkeys 2>/dev/null; then
            :
        elif command_exists kquitapp5; then
            kquitapp5 khotkeys 2>/dev/null || log_warn "Could not restart the KHotkeys daemon cleanly."
        fi
        sleep 1
        kstart5 khotkeys >/dev/null 2>&1 || kstart6 khotkeys >/dev/null 2>&1 || true
        log_ok "KHotkeys daemon restarted — shortcuts should be live now."
    else
        log_warn "No running Plasma session detected — shortcuts will apply at your next login."
    fi
fi

echo -e "${GREEN}Hotkeys step complete.${NC}"
log_warn "Review/edit these any time in System Settings > Shortcuts > Custom Shortcuts."
log_warn "If a binding doesn't fire, log out and back in (global shortcuts are cached per-session)."