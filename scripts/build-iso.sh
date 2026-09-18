#!/usr/bin/env bash
# Build the Vertex Linux ISO with Debian's live-build.
#
# Must be run as root, on a Debian (or Debian-derived) host, with
# `live-build` installed (`apt install live-build`). It cannot be run on
# a non-Debian system since it invokes debootstrap/apt against the target
# suite's own package tooling.
#
# Usage:
#   sudo ./scripts/build-iso.sh              # build with defaults
#   sudo DEBIAN_SUITE=trixie ./scripts/build-iso.sh   # pin to stable instead
#   ./scripts/build-iso.sh --clean           # wipe previous build state first
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# "testing" tracks whatever GNOME release is currently newest in Debian;
# switch to "trixie" for the stable release instead, or "sid" for unstable.
DEBIAN_SUITE="${DEBIAN_SUITE:-testing}"
ARCH="${ARCH:-amd64}"
ISO_NAME="vertex-linux"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "1.0")"

if [[ "${1:-}" == "--clean" ]]; then
    echo "==> Cleaning previous live-build state"
    lb clean --purge || true
    rm -rf "$ROOT"/{binary,chroot,cache,.build} 2>/dev/null || true
    shift
fi

if [[ "$EUID" -ne 0 ]]; then
    echo "error: this script must be run as root (live-build needs it for chroot/debootstrap)" >&2
    exit 1
fi

if ! command -v lb >/dev/null 2>&1; then
    echo "error: live-build is not installed. Run: apt install live-build" >&2
    exit 1
fi

# Make sure branding assets are up to date before every build.
if [[ -x "$ROOT/branding/generate-assets.sh" ]]; then
    echo "==> Refreshing branding assets"
    "$ROOT/branding/generate-assets.sh"
fi

echo "==> Configuring live-build (suite=$DEBIAN_SUITE arch=$ARCH)"
lb config \
    --mode debian \
    --distribution "$DEBIAN_SUITE" \
    --architectures "$ARCH" \
    --archive-areas "main contrib non-free non-free-firmware" \
    --updates true \
    --security true \
    --bootloaders grub-efi \
    --binary-images iso-hybrid \
    --iso-application "Vertex Linux" \
    --iso-publisher "Vertex Linux Project" \
    --iso-volume "VERTEX" \
    --debian-installer none \
    --firmware-chroot true \
    --firmware-binary true \
    --memtest none \
    --win32-loader false

echo "==> Building the ISO (this takes a while and needs network access)"
lb build

mkdir -p "$ROOT/out"
built_iso="$(find "$ROOT" -maxdepth 1 -name 'live-image-*.hybrid.iso' -print -quit)"
if [[ -z "$built_iso" ]]; then
    echo "error: build finished but no output ISO was found" >&2
    exit 1
fi

dest="$ROOT/out/${ISO_NAME}-${VERSION}-${ARCH}.iso"
mv "$built_iso" "$dest"
echo "==> Done: $dest"
