#!/usr/bin/env bash
# ==========================================
# install.sh — One command, everything, unattended.
# -------------------------------------------------------
# The "I don't want to press y every time" entry point.
# Runs the full toolkit with every prompt taking its default
# (core + sysmgmt + optional), then verifies the end state.
#
#   ./install.sh             everything, unattended, then verify
#   ./install.sh --core      core setup only (skips sysmgmt + optional)
#   ./install.sh --no-verify skip the post-run audit
#   ./install.sh --only a,b  just those steps (unattended)
#   ./install.sh --list      show what's included, then exit
#
# Anything else is passed through to run.sh, so the full runner's flags work
# here too — notably --list-utilities, --phase and --no-update. Try --help
# here for the common subset, or ./run.sh --help for everything. You run this as
# your NORMAL user; the scripts escalate themselves (priv() — sudo first,
# doas fallback) as needed.
# ==========================================

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Flags ---------------------------------------------------------------
CORE=0
NO_VERIFY=0
PASSTHRU=()
RUN_EXTRA=()

while [ $# -gt 0 ]; do
    case "$1" in
        --core) CORE=1 ;;
        --no-verify) NO_VERIFY=1 ;;
        --help|-h)
            cat <<'EOF'
install.sh — one command, everything, unattended (Devuan/Debian + KDE Plasma toolkit).

  ./install.sh             everything, unattended, then verify
  ./install.sh --core      core setup only (skips sysmgmt + optional)
  ./install.sh --no-verify skip the post-run audit
  ./install.sh --only a,b  just those steps (unattended)
  ./install.sh --list            show what's included, then exit
  ./install.sh --list-utilities  show the standalone utilities, then exit
  ./install.sh --phase optional  unattended, one phase only
  ./install.sh --no-update       unattended, skip every apt-get update

  Anything not listed above is passed straight to run.sh; see ./run.sh --help.

  Escalation is sudo-first (doas fallback); set DEVMKDE_PRIV=doas to force doas.
  Other env vars: DEVMKDE_SKIP_APT_UPDATE=1, DEVMKDE_ISO_BUILD=1.
EOF
            exit 0
            ;;
        *) PASSTHRU+=("$1") ;;
    esac
    shift
done

# Unattended: every ask() takes its default.
export DEVMKDE_ASSUME_YES=1
# Everything on by default EXCEPT when --core trims to the core section.
if [ "$CORE" -eq 1 ]; then
    PASSTHRU+=(--phase core --yes)
else
    PASSTHRU+=(--full)
fi
[ "$NO_VERIFY" -eq 0 ] && RUN_EXTRA+=(--verify)

exec bash "$SCRIPT_DIR/run.sh" "${PASSTHRU[@]}" "${RUN_EXTRA[@]}"