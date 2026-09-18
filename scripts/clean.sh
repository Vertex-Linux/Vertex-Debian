#!/usr/bin/env bash
# Wipe live-build's build state and generated output.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if command -v lb >/dev/null 2>&1; then
    lb clean --purge || true
fi

rm -rf "$ROOT"/{binary,chroot,cache,.build,live-image-*.hybrid.iso}
echo "==> Cleaned. (out/ was left alone — remove it manually if you also want to drop built ISOs/VM disks.)"
