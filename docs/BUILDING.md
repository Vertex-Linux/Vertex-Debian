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
   `trixie` (stable) by default — override with `DEBIAN_SUITE=testing` for
   newer GNOME (but see "Known rough edges" below first) or
   `DEBIAN_SUITE=sid` for unstable — with GNOME's full desktop task,
   Flatpak, Fastfetch, and Calamares in the
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
  remote, installing Vertex's own tools (see below), removing Debian
  branding, compiling the dconf database, activating the Plymouth theme
  and rebuilding the initramfs, refreshing icon/desktop caches, and
  enabling core services.
- **`config/includes.chroot/usr/local/sbin/update-vertex-apps.sh`** —
  fetches VPKG, Vertex Updater, and Vertex Driver Downloader straight from
  their GitHub releases (`Vertex-Linux/vertex-tools` for the first two,
  distinguished only by tag naming — `vpkg-<version>` vs `<version>-vu` —
  and `Vertex-Linux/vertex-graphics-installer` for the third), strips the
  Rust target-triple suffix from the downloaded binaries so they run as
  plain `vpkg`/`vertex-update`/`vertex-drivers`, and creates `.desktop`
  launchers for the latter two if they don't already exist. Run once at
  build time by `0120-install-vertex-apps.hook.chroot`, but it also ships
  in the image itself at that same path — since none of these are apt
  packages, re-running it later (by hand, or eventually from within Vertex
  Updater itself) is the actual update mechanism for all three.
- **`config/includes.chroot/etc/calamares/`** — Calamares installs by
  copying the live squashfs onto the target disk (`unpackfs` module
  pointing at `/run/live/medium/live/filesystem.squashfs`), then runs the
  usual partition/users/bootloader/locale steps. `settings.conf` defines
  the step sequence; `branding/vertex/` defines the installer's look.
  Because `unpackfs` clones the *entire* live filesystem verbatim, the
  final `shellprocess` step (`modules/shellprocess.conf`) cleans up
  everything that's only relevant to the live session — the installer
  launcher itself, GDM's live-session autologin config, and the
  calamares/live-boot/live-config packages — so the installed system
  doesn't boot straight past the login screen or keep an "Install Vertex
  Linux" icon around.

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
- **Plymouth boot screen shows an unbranded gray/dots fallback**, on both
  QEMU and real hardware (tested on a Lenovo ThinkPad E14). Everything
  checkable from the outside is confirmed correct: `Theme=vertex` is set
  in `plymouthd.conf` on both the root filesystem *and* baked into the
  initramfs itself; the theme's files (including an `animation-0001.png`
  frame — `two-step`'s primary boot visual, confirmed by comparing against
  Debian's own bundled `spinner` theme, which has no `watermark.png` at all
  and relies solely on `animation-*.png`/`throbber-*.png`) are present in
  the initramfs; the kernel command line correctly has `splash quiet`
  (`/etc/default/grub` and `scripts/build-iso.sh`'s `--bootappend-live`);
  and `plymouthd`/`plymouth show-splash` both exit with `status=0/SUCCESS`
  in the boot log with no errors. So Plymouth is genuinely choosing to
  render in a degraded fallback mode rather than failing outright — likely
  a DRM/KMS renderer availability issue at the point Plymouth actually
  runs (early boot, before the full desktop's graphics stack is up),
  though `/dev/dri/card0` and a real framebuffer (`virtio_gpudrmfb` in the
  VM case) are confirmed present once the system finishes booting, so it's
  specifically a *timing* question, not a missing-driver one. Deliberately
  parked here rather than chased further — it's cosmetic only, and the
  next real step is booting with `plymouth.debug` on the kernel command
  line and reading `/var/log/plymouth-debug.log` for Plymouth's own
  internal reasoning, which needs a full rebuild+boot cycle to get.
- **GDM 50's login screen doesn't show a user list at all** on
  `DEBIAN_SUITE=testing` (this is *why* the default is `trixie` — see
  above). After a fresh Calamares install, instead of a normal login
  prompt you get dropped into a full graphical session under GDM's own
  internal `gdm-greeter` service account (visible via `getent passwd
  60578`-style dynamic UIDs, `/run/gdm3/home/gdm-greeter` as its home,
  and `/sbin/nologin` as its shell) — locking the screen then prompts to
  re-authenticate as "GDM Greeter" itself, which always fails since it
  has no real password. This is a **confirmed upstream GDM 50 regression**
  (see the Arch Linux bug report "[SOLVED] After GNOME 50 Update — GDM
  bypasses login-greeter"), not a bug in this project's config. Ruled out
  before concluding that, in order: `gnome-initial-setup` not being
  purged (it was, no change); a dangling `AutomaticLogin=` target in
  `/etc/gdm3/daemon.conf` *or* `/var/lib/gdm3/.config/gdm/custom.conf`
  (neither file has one; the latter doesn't even exist); our custom
  `org.gnome.login-screen` `logo` dconf key crashing greeter UI
  construction (removed it, no change); `/var/lib/AccountsService/users/`
  being empty even though `busctl call org.freedesktop.Accounts
  /org/freedesktop/Accounts org.freedesktop.Accounts ListCachedUsers`
  correctly lists the account live (pre-seeded the cache file in
  `config/includes.chroot/etc/calamares/modules/shellprocess.conf`
  anyway — cheap and still worth keeping even though it didn't fix this
  — note that module's variable-naming gotcha documented inline: its
  script strings are pre-scanned for any `$word` pattern, including
  positional parameters like `$1`, and treated as an undefined Calamares
  GlobalStorage placeholder unless avoided by using `$(...)` command
  substitution inline instead of storing values in any variable); and
  `/usr/share/gdm/generate-config` (Debian's own greeter-dconf-defaults
  compiler) producing a corrupt result (confirmed fine — it compiles from
  `/usr/share/gdm/dconf`, an entirely separate lockdown-settings mechanism
  from our own `/etc/dconf/db/gdm.d/` customization, and isn't the
  cause). Should GDM ship a fix upstream, `DEBIAN_SUITE=testing` is worth
  retrying.
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
