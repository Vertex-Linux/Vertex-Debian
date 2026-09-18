# Building and testing Vertex Linux

## Prerequisites

Building **must** happen on a Debian (or Debian-derived, e.g. Ubuntu)
machine — `live-build` bootstraps a chroot of the target Debian suite using
`debootstrap` and `apt`, both of which assume a Debian-family host. If
you're on something else (macOS, Arch, Windows), run the build inside a
Debian VM or container.

```sh
sudo apt update
sudo apt install live-build qemu-system-x86 ovmf imagemagick git
```

## 1. Rebrand (optional)

Drop your real logo/wallpapers into `branding/` (see the README's
"Rebranding" section), then:

```sh
cd branding && ./generate-assets.sh && cd ..
```

`scripts/build-iso.sh` also runs this automatically before every build, so
this step is only needed if you want to preview the generated files first.

## 2. Build the ISO

```sh
sudo ./scripts/build-iso.sh
```

What this does:
1. Regenerates branding assets.
2. Runs `lb config` to set up a live-build project targeting Debian
   `testing` (override with `DEBIAN_SUITE=trixie` or `DEBIAN_SUITE=sid`),
   with GNOME's full desktop task, Flatpak, Fastfetch, and Calamares in the
   package list, `iso-hybrid` output (boots from USB or optical media,
   UEFI only for now — see "Known rough edges" below), and no
   `debian-installer` (Calamares replaces it).
3. Runs `lb build`, which debootstraps a chroot, installs packages, applies
   everything under `config/includes.chroot/` (this is how the branding,
   Fastfetch config, dconf defaults, and Calamares config get into the
   image), runs the hooks in `config/hooks/live/`, then squashes it all
   into a bootable hybrid ISO.
4. Moves the result to `out/vertex-linux-<version>-amd64.iso`.

A full build downloads and installs a complete GNOME desktop from Debian's
repositories, so budget for real time and ~8-10GB of disk/network I/O the
first time. Subsequent builds reuse live-build's apt cache and are faster.

Pass `--clean` to wipe previous live-build state first if you've changed
`lb config` options (suite, architecture, etc.) between builds:

```sh
sudo ./scripts/build-iso.sh --clean
```

## 3. Test it in a VM

```sh
./scripts/run-vm.sh --uefi          # UEFI boot (needs ovmf installed)
```

The ISO is UEFI-only for now (see below), so it won't boot with a plain
BIOS QEMU invocation — always pass `--uefi`.

This boots the newest ISO in `out/` against a persistent virtual disk
(`out/vertex-vm-disk.qcow2`, created on first run), so you can actually run
the Calamares installer end-to-end and then reboot into the installed
system. Delete that `.qcow2` file to start over with a fresh disk.

## How the pieces fit together

- **`config/package-lists/vertex.list.chroot`** — every package installed
  into the live filesystem: GNOME (`task-gnome-desktop`), the bootloader,
  Plymouth, Flatpak, Fastfetch, and Calamares.
- **`config/includes.chroot/`** — a literal overlay copied onto the chroot's
  root filesystem after packages are installed (so these files win over any
  package defaults with the same path). This is where all the branding,
  Fastfetch config, GNOME dconf defaults, and Calamares config live.
- **`config/hooks/live/*.hook.chroot`** — shell scripts run inside the
  chroot near the end of the build, in filename order: adding the Flathub
  remote, compiling the dconf database, activating the Plymouth theme and
  rebuilding the initramfs, refreshing icon/desktop caches, and enabling
  core services.
- **`config/includes.chroot/etc/calamares/`** — Calamares installs by
  copying the live squashfs onto the target disk (`unpackfs` module
  pointing at `/run/live/medium/live/filesystem.squashfs`), then runs the
  usual partition/users/bootloader/locale steps. `settings.conf` defines
  the step sequence; `branding/vertex/` defines the installer's look.

## Known rough edges (fine for now, worth revisiting later)

- Calamares's module configuration is inherently something you tune while
  watching a real install run in the VM — the shipped config follows
  standard, well-documented Calamares conventions but hasn't been run
  against a built ISO yet. If a step misbehaves, check
  `/var/log/Calamares.log` inside the live session and compare against
  [Calamares's module documentation](https://github.com/calamares/calamares/tree/calamares/src/modules).
- **UEFI only, no BIOS/legacy boot** — `grub-pc` and `grub-efi-amd64`
  `Conflict:` each other in Debian, so both the live media and anything
  Calamares installs only support UEFI right now. Add BIOS support back
  later by dropping `--bootloaders grub-efi` from `scripts/build-iso.sh`
  (restoring live-build's BIOS+UEFI default) and shipping a separate,
  legacy-only variant, since a single image can't offer both without
  the packaging conflict.
- No Secure Boot support yet (`grub-efi-amd64` only, unsigned) — add
  `grub-efi-amd64-signed` + `shim-signed` to the package list later if you
  need it.
- The Plymouth theme only ships a static watermark logo (no custom
  spinner/progress art) — the `two-step` plugin still animates a default
  throbber; add `throbber-*.png` frames to
  `config/includes.chroot/usr/share/plymouth/themes/vertex/` for a fully
  custom one.
- **Settings → About's OS logo.** This one didn't follow `/etc/os-release`'s
  `LOGO=` key at all — Debian's `gnome-control-center` is built with
  `-Ddistributor_logo`/`-Ddark_mode_distributor_logo` both pointing at
  `/usr/share/icons/vendor/scalable/emblems/emblem-vendor.svg` (see
  `debian/rules` in Debian's packaging at
  salsa.debian.org/gnome-team/gnome-control-center), which
  `cc-about-page.c`'s `setup_os_logo()` loads directly via
  `gtk_picture_set_filename()`, bypassing os-release entirely whenever that
  compile-time constant is set. `0150-remove-debian-branding.hook.chroot`
  overwrites that exact file with Vertex's mark now.
