#!/usr/bin/env bash
# Enter (or create) the Debian build container used for live-build.
#
# Deliberately does NOT use --privileged. That flag implies sharing the
# host's own cgroup namespace rather than giving the container an isolated
# one — the working theory for why a previous --privileged container
# (created via `distrobox create --root`) twice corrupted this machine's
# own systemd/cgroup state on stop, breaking sudo and every terminal
# emulator until a reboot. Instead this grants a private cgroup namespace
# plus only the specific capabilities live-build's debootstrap/chroot/mount
# steps need.
#
set -euo pipefail

NAME="vertex-build2"
IMAGE="debian:trixie"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! sudo podman container exists "$NAME" 2>/dev/null; then
    echo "==> Creating $NAME"
    sudo podman run -d --name "$NAME" \
        --runtime runc \
        --cgroupns=private \
        --cap-add SYS_ADMIN \
        --cap-add MKNOD \
        --cap-add SYS_CHROOT \
        --cap-add SETUID \
        --cap-add SETGID \
        --cap-add SYS_PTRACE \
        --security-opt seccomp=unconfined \
        --security-opt apparmor=unconfined \
        --device /dev/loop-control \
        -v "$ROOT":/build \
        -w /build \
        "$IMAGE" sleep infinity
fi

status="$(sudo podman inspect -f '{{.State.Status}}' "$NAME")"
if [[ "$status" != "running" ]]; then
    echo "==> Starting $NAME"
    sudo podman start "$NAME"
fi

echo "==> Entering $NAME (run: apt update && apt install -y live-build imagemagick git)"
exec sudo podman exec -it "$NAME" bash
