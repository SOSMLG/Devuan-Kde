#!/usr/bin/env bash
# =======================================================
# build.sh — Devuan KDE ISO builder (live-build wrapper)
# -------------------------------------------------------
# Produces a Devuan Excalibur amd64 ISO with KDE Plasma pre-baked by
# this toolkit, ready for a live session or a permanent install (see
# iso/README.md for the refractainstaller path).
#
#   sudo ./build.sh              build the ISO (uses _build/ scratch dir)
#   sudo ./build.sh --clean      wipe _build/ and any built ISO first
#
# Requires: live-build (Devuan's fork), debootstrap, network, ~10 GB free.
# Status: structurally faithful scaffold, NOT end-to-end verified on this
# machine (no live-build/space here). Iterate once on a real build host.
# =======================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/_build"
ISO_NAME="${ISO_NAME:-devuan-kde-latest}"

OS_DIST="excalibur"
OS_ARCH="amd64"
[ -n "${DEVUAN_MIRROR:-}" ] \
    && export LB_MIRROR_BOOTSTRAP="$DEVUAN_MIRROR" LB_MIRROR_CHROOT="$DEVUAN_MIRROR" LB_MIRROR_BINARY="$DEVUAN_MIRROR"

clean() {
    echo "-> Cleaning $BUILD_DIR ..."
    rm -rf "$BUILD_DIR"
    rm -f "$SCRIPT_DIR"/.build/*.iso 2>/dev/null
}

need_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Run as root (live-build refuses non-root). Try: sudo ./build.sh"
        exit 1
    fi
}

need_cmds() {
    local missing=0 c
    for c in lb debootstrap; do
        command -v "$c" >/dev/null 2>&1 || { echo "Missing: $c — install 'live-build' (Devuan fork)."; missing=1; }
    done
    [ "$missing" -eq 0 ] || exit 1
}

build() {
    need_root
    need_cmds
    mkdir -p "$SCRIPT_DIR/.build"

    echo "=( $OS_DIST / $OS_ARCH — $ISO_NAME )"
    echo "-> Seeding config/ into $BUILD_DIR ..."
    mkdir -p "$BUILD_DIR"
    rsync -a --delete "$SCRIPT_DIR/config/" "$BUILD_DIR/config/"

    # Bake the toolkit itself into the chroot so hooks/live/*
    # can run it at flavor-bake time; DEVMKDE_ISO_BUILD=1 lets its
    # root-only helpers behave inside the chroot.
    echo "-> Injecting toolkit into includes.chroot ..."
    mkdir -p "$BUILD_DIR/config/includes.chroot/root"
    rsync -a --delete \
        --exclude iso/_build --exclude '*.iso' \
        "$REPO_ROOT/" "$BUILD_DIR/config/includes.chroot/root/devuan-kde/"

    echo "-> lb config ..."
    ( cd "$BUILD_DIR" && lb config ) || { echo "lb config failed — see $BUILD_DIR"; exit 1; }

    echo "-> lb build (this is the long step) ..."
    ( cd "$BUILD_DIR" && lb build ) || { echo "lb build failed — see $BUILD_DIR"; exit 1; }

    local iso
    iso="$(ls -1 "$BUILD_DIR"/*.iso 2>/dev/null | head -1)"
    if [ -n "$iso" ]; then
        cp "$iso" "$SCRIPT_DIR/.build/$ISO_NAME.iso"
        echo
        echo "Done: $SCRIPT_DIR/.build/$ISO_NAME.iso"
        echo "Burn via refractainstaller (see iso/README.md) or copy to a USB stick."
    else
        echo "Build finished but no *.iso was found in $BUILD_DIR — inspect it."
        exit 1
    fi
}

case "${1:-}" in
    --clean) clean; exit 0 ;;
    --clean-then-build) clean; build ;;
    help|--help|-h)
        grep -E '^#|^$' "$0" | sed -n '1,20p' 2>/dev/null
        echo
        echo "Options: --clean  --clean-then-build  help"
        ;;
    *) build ;;
esac