# Vertex Linux

A Debian-based Linux distribution built with [live-build](https://wiki.debian.org/LiveBuild):
latest available GNOME desktop, Flatpak, a themed Fastfetch, and a Calamares
installer — with a placeholder purple-triangle brand identity you can swap
out for real art whenever it's ready.

## What's in here

| Path | Purpose |
|---|---|
| [`branding/`](branding/) | Drop your full-size PNG logo/wallpapers here and run [`generate-assets.sh`](branding/generate-assets.sh) |
| [`config/`](config/) | The live-build project config (package lists, file overlays, hooks) |
| [`scripts/build-iso.sh`](scripts/build-iso.sh) | Builds the installable ISO |
| [`scripts/run-vm.sh`](scripts/run-vm.sh) | Boots the ISO in QEMU |
| [`scripts/clean.sh`](scripts/clean.sh) | Wipes live-build's build state |
| [`docs/BUILDING.md`](docs/BUILDING.md) | Full build/test walkthrough and how each piece fits together |

## Quick start

Building requires a **Debian (or Debian-derived) host** — `live-build` shells
out to `debootstrap`/`apt` for the target suite, so it can't run on
non-Debian systems (this doesn't need to be your daily driver; a throwaway
Debian VM or container works fine).

```sh
# 1. On a Debian box:
sudo apt install live-build qemu-system-x86 ovmf imagemagick

# 2. Build the ISO (defaults to Debian testing, for the newest GNOME)
sudo ./scripts/build-iso.sh

# 3. Boot it in a VM
./scripts/run-vm.sh
```

The finished ISO lands in `out/vertex-linux-<version>-amd64.iso`.

## Rebranding

Replace `branding/logo.png` and/or `branding/wallpaper-{1,2,3}.png` with
your real art (any resolution, PNG), then, from inside `branding/`:

```sh
./generate-assets.sh
```

This resizes/converts everything into every size and format the OS actually
needs (app icons, the Calamares installer branding, the Plymouth boot logo,
desktop wallpapers) and writes it straight into `config/includes.chroot/`.
Rebuild the ISO afterwards to pick up the changes. See
[`branding/generate-assets.sh`](branding/generate-assets.sh) for the exact
file naming convention, and drop in `wallpaper-4.png`, `wallpaper-5.png`,
etc. to add more presets to the GNOME background picker.

## Design choices worth knowing about

- **Base suite**: `DEBIAN_SUITE=testing` by default (tracks the newest GNOME
  Debian packages); set `DEBIAN_SUITE=trixie` for the stable release or
  `sid` for unstable. See [`scripts/build-iso.sh`](scripts/build-iso.sh).
- **Installer**: [Calamares](https://calamares.io/) — the de facto standard
  independent Linux installer today (used by KDE neon, EndeavourOS,
  Manjaro, and many others); it installs by copying the live squashfs
  filesystem onto the target disk, then configures the bootloader/users/
  locale. Its config lives under `config/includes.chroot/etc/calamares/`.
- **Fastfetch theme**: a purple ASCII triangle logo defined in
  `config/includes.chroot/usr/share/vertex/fastfetch-logo.txt`, wired up via
  `config/includes.chroot/etc/fastfetch/config.jsonc`.
- Kept intentionally minimal — no extra apps beyond GNOME, Flatpak,
  Fastfetch, and Calamares. Iterate from here.
