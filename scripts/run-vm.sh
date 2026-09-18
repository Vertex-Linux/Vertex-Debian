#!/usr/bin/env bash
# Boot the built Vertex Linux ISO in QEMU — for testing the live session
# and trying out the Calamares installer against a throwaway virtual disk.
#
# Usage:
#   ./scripts/run-vm.sh                 # boot the newest ISO in out/
#   ./scripts/run-vm.sh path/to.iso      # boot a specific ISO
#   ./scripts/run-vm.sh --uefi           # boot with UEFI (OVMF) firmware
#   RAM=8192 DISK_SIZE=40G ./scripts/run-vm.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RAM="${RAM:-4096}"
CPUS="${CPUS:-2}"
DISK_SIZE="${DISK_SIZE:-20G}"
DISK="$ROOT/out/vertex-vm-disk.qcow2"

UEFI=false
ISO=""
for arg in "$@"; do
    case "$arg" in
        --uefi) UEFI=true ;;
        *) ISO="$arg" ;;
    esac
done

if [[ -z "$ISO" ]]; then
    ISO="$(ls -t "$ROOT"/out/vertex-linux-*.iso 2>/dev/null | head -n1 || true)"
fi
if [[ -z "$ISO" || ! -f "$ISO" ]]; then
    echo "error: no ISO found. Build one first with scripts/build-iso.sh, or pass a path." >&2
    exit 1
fi

if ! command -v qemu-system-x86_64 >/dev/null 2>&1; then
    echo "error: qemu-system-x86_64 not found. Install QEMU first." >&2
    exit 1
fi

mkdir -p "$ROOT/out"
if [[ ! -f "$DISK" ]]; then
    echo "==> Creating $DISK_SIZE virtual disk at $DISK"
    qemu-img create -f qcow2 "$DISK" "$DISK_SIZE" >/dev/null
fi

KVM_ARGS=()
if [[ -e /dev/kvm && -r /dev/kvm && -w /dev/kvm ]]; then
    KVM_ARGS=(-enable-kvm -cpu host)
else
    echo "==> /dev/kvm not available, falling back to software emulation (slow)"
fi

UEFI_ARGS=()
if [[ "$UEFI" == true ]]; then
    OVMF_CODE=""
    for candidate in \
        /usr/share/OVMF/OVMF_CODE.fd \
        /usr/share/edk2/x64/OVMF_CODE.4m.fd \
        /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
        /usr/share/ovmf/OVMF.fd
    do
        [[ -f "$candidate" ]] && OVMF_CODE="$candidate" && break
    done
    if [[ -z "$OVMF_CODE" ]]; then
        echo "error: --uefi requested but no OVMF firmware found (install ovmf/edk2-ovmf)" >&2
        exit 1
    fi
    UEFI_ARGS=(-drive "if=pflash,format=raw,readonly=on,file=$OVMF_CODE")
fi

echo "==> Booting $ISO (ram=${RAM}MB cpus=$CPUS uefi=$UEFI)"
exec qemu-system-x86_64 \
    "${KVM_ARGS[@]}" \
    "${UEFI_ARGS[@]}" \
    -m "$RAM" \
    -smp "$CPUS" \
    -vga virtio \
    -display gtk \
    -device intel-hda -device hda-duplex \
    -drive file="$DISK",if=virtio,format=qcow2 \
    -cdrom "$ISO" \
    -boot d
