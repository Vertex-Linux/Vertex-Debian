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
#
# If this repo is bind-mounted into a container (see scripts/dev-shell.sh)
# and you're building as root in there, output ownership gets handed back
# to uid/gid 1000 at the end. Set HOST_UID/HOST_GID if your host user is
# something else.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Default to Debian's stable release. "testing" tracks whatever GNOME is
# currently newest, but as of GDM 50 that means shipping a confirmed
# upstream regression (GDM's greeter fails to show the user list at all,
# dropping straight into its own internal service account — see
# docs/BUILDING.md's "Known rough edges" for the full investigation and
# links). Set DEBIAN_SUITE=testing to go back to bleeding-edge GNOME (and
# hit that bug), or DEBIAN_SUITE=sid for unstable.
DEBIAN_SUITE="${DEBIAN_SUITE:-trixie}"
ARCH="${ARCH:-amd64}"
ISO_NAME="vertex-linux"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo "1.0")"

if [[ "${1:-}" == "--clean" ]]; then
    echo "==> Cleaning previous live-build state"
    lb clean --purge || true
    rm -rf "$ROOT"/{binary,chroot,cache,.build} 2>/dev/null || true
    # lb clean --purge does NOT reset these — they're lb config's own
    # saved settings from the first time it ever ran here (distribution,
    # architecture, etc.), and lb config treats their existence as "already
    # configured," silently skipping a real reconfiguration even when you
    # pass different flags. Confirmed: switching DEBIAN_SUITE from testing
    # to trixie had zero effect across multiple --clean rebuilds until
    # these were removed too — every one of those builds silently kept
    # using the suite from the very first `lb config` call ever made here.
    rm -f "$ROOT"/config/{bootstrap,chroot,binary,common,source} 2>/dev/null || true
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
    --win32-loader false \
    --bootappend-live "boot=live components splash quiet"

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

# This runs as real root inside a container with no user-namespace
# remapping, so anything it creates through this bind-mounted directory —
# the ISO, regenerated branding assets, live-build's own state — lands
# root-owned on the host too. Hand it all back so run-vm.sh and normal
# editing work without sudo. Override HOST_UID/HOST_GID if your host user
# isn't uid/gid 1000.
chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" "$ROOT"

echo "==> Done: $dest"
