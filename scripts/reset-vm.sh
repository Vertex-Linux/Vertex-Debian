#!/usr/bin/env bash
# Wipe the QEMU test VM's virtual disk so the next ./scripts/run-vm.sh
# starts a completely fresh install (previous Vertex Linux install,
# partition layout, everything inside that disk — gone). Only touches the
# VM's disk image; the ISO and the rest of this repo are untouched.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DISK="$ROOT/out/vertex-vm-disk.qcow2"

if [[ -f "$DISK" ]]; then
    rm -f "$DISK"
    echo "==> Removed $DISK"
else
    echo "==> No existing disk at $DISK (already clean)"
fi

echo "==> Next ./scripts/run-vm.sh will create a fresh empty disk automatically."
