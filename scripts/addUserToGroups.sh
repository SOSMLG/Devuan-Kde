#!/usr/bin/env bash
# Add the real (non-root) user to groups needed by the rest of this toolkit:
#   input  -> required for some touchpad/trackpoint tools & libinput debugging
#   video  -> GPU/brightness access
#   render -> GPU compute/accel access (DRI render nodes)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "$SCRIPT_DIR/lib/common.sh"

# Get actual user even when this was invoked with sudo somewhere upstream
ACTUAL_USER="${SUDO_USER:-$USER}"

if [ -z "$ACTUAL_USER" ] || [ "$ACTUAL_USER" = "root" ]; then
    echo -e "${RED}Could not determine a non-root user to modify. Aborting.${NC}"
    exit 1
fi

echo -e "Adding ${YELLOW}${ACTUAL_USER}${NC} to input, video, render groups..."

status=0
for grp in input video render; do
    if ! getent group "$grp" >/dev/null 2>&1; then
        echo -e "${YELLOW}  Group '$grp' does not exist on this system, skipping.${NC}"
        continue
    fi
    if id -nG "$ACTUAL_USER" 2>/dev/null | tr ' ' '\n' | grep -qx "$grp"; then
        echo -e "${GREEN}  Already in '$grp'${NC}"
        continue
    fi
    if sudo usermod -aG "$grp" "$ACTUAL_USER"; then
        echo -e "${GREEN}  ✓ Added to '$grp'${NC}"
    else
        echo -e "${RED}  ✗ Failed to add to '$grp'${NC}"
        status=1
    fi
done

echo -e "${YELLOW}⚠ You need to log out and back in (or reboot) for new group membership to take effect.${NC}"
exit "$status"
