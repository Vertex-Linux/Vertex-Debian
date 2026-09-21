#!/usr/bin/env bash
# Vertex Linux — branding asset pipeline.
#
# Drop full-size PNGs into THIS folder (branding/) using the filenames
# below, then run this script from inside it (./generate-assets.sh). It
# resizes/converts everything into every format and location the OS
# actually needs, under config/includes.chroot/, ready to be picked up by
# scripts/build-iso.sh.
#
# Expected source files (all PNG, transparent background where noted):
#   logo.png           - square logo/mark, transparent bg, >=1024x1024
#   pfp.png            - square user avatar/profile picture, >=512x512
#   vertex-update.png  - Vertex Updater app icon, transparent bg, >=512x512
#   vertex-driver.png  - Vertex Driver Downloader app icon, ditto
#   wallpaper-1.png    - desktop background, >=1920x1080 (becomes the default)
#   wallpaper-2.png    - desktop background, >=1920x1080
#   wallpaper-3.png    - desktop background, >=1920x1080
#
# You can add wallpaper-4.png, wallpaper-5.png, etc. — every wallpaper-*.png
# found here is picked up automatically and added to the GNOME background
# picker. Missing optional wallpapers are simply skipped.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES="$SCRIPT_DIR"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CHROOT="$ROOT/config/includes.chroot"

if command -v magick >/dev/null 2>&1; then
    CONVERT=(magick)
elif command -v convert >/dev/null 2>&1; then
    CONVERT=(convert)
else
    echo "error: ImageMagick is required (install the 'imagemagick' package)" >&2
    exit 1
fi

resize() {
    # resize <src> <dest> <WxH>
    "${CONVERT[@]}" "$1" -resize "$3" -strip "$2"
}

echo "==> Vertex Linux branding pipeline"
echo "    sources: $SOURCES"
echo "    output:  $CHROOT"

# ---------------------------------------------------------------------------
# Logo -> hicolor icon theme, pixmaps, Calamares branding, Plymouth boot logo
# ---------------------------------------------------------------------------
LOGO="$SOURCES/logo.png"
if [[ -f "$LOGO" ]]; then
    echo "==> Processing logo.png"

    ICON_SIZES=(16 22 24 32 48 64 128 256 512)
    for size in "${ICON_SIZES[@]}"; do
        dest_dir="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
        mkdir -p "$dest_dir"
        resize "$LOGO" "$dest_dir/vertex-logo.png" "${size}x${size}"
    done

    mkdir -p "$CHROOT/usr/share/pixmaps"
    resize "$LOGO" "$CHROOT/usr/share/pixmaps/vertex-logo.png" "256x256"

    # Calamares branding (installer): window icon + sidebar logo
    mkdir -p "$CHROOT/etc/calamares/branding/vertex/images"
    resize "$LOGO" "$CHROOT/etc/calamares/branding/vertex/images/logo.png" "200x200"
    resize "$LOGO" "$CHROOT/etc/calamares/branding/vertex/images/icon.png" "64x64"

    # Plymouth boot splash logo. two-step's *primary* boot visual is the
    # animation-NNNN.png sequence (confirmed against Debian's own bundled
    # "spinner" theme, which has no watermark.png at all and relies solely
    # on animation-*.png + throbber-*.png) — watermark.png alone, which is
    # what we originally shipped, left two-step with nothing to show during
    # the main boot phase, hence the unbranded gray/dots fallback. A single
    # frame is enough since we're not animating.
    mkdir -p "$CHROOT/usr/share/plymouth/themes/vertex"
    resize "$LOGO" "$CHROOT/usr/share/plymouth/themes/vertex/watermark.png" "256x256"
    resize "$LOGO" "$CHROOT/usr/share/plymouth/themes/vertex/animation-0001.png" "256x256"

    # GNOME About / os-logo used by gnome-control-center "About" panel
    mkdir -p "$CHROOT/usr/share/pixmaps"
    resize "$LOGO" "$CHROOT/usr/share/pixmaps/vertex-logo-text.png" "512x512"

    # A couple of spots need an actual .svg file (Settings > About's logo,
    # the GRUB boot menu background). We don't have vector source art, so
    # wrap a downscaled copy of logo.png as embedded base64 image data —
    # that keeps them pixel-matched to logo.png instead of a hand-drawn
    # approximation, and they regenerate automatically whenever you replace
    # logo.png and rerun this script.
    #
    # The SVG's declared width/height is set to 192 (not the embedded PNG's
    # actual resolution) to match the AdwClamp maximum-size gnome-control-
    # center's cc-about-page.ui wraps this logo in — its GtkPicture has
    # can-shrink="false", so it refuses to shrink below whatever size the
    # SVG itself declares, ignoring the clamp entirely if the SVG claims to
    # be bigger. The embedded PNG stays rendered at 512x512 internally for
    # crispness on HiDPI displays; only the outer <svg>/<image> tags' stated
    # size changed.
    mkdir -p "$CHROOT/usr/share/vertex"
    tmp_mark="$(mktemp --suffix=.png)"
    "${CONVERT[@]}" "$LOGO" -resize "512x512" -strip "$tmp_mark"
    b64_mark="$(base64 -w0 "$tmp_mark")"
    cat > "$CHROOT/usr/share/vertex/vertex-mark.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="192" height="192" viewBox="0 0 192 192">
  <image width="192" height="192" href="data:image/png;base64,${b64_mark}"/>
</svg>
EOF
    rm -f "$tmp_mark"
    echo "==> Generated vertex-mark.svg from logo.png"

    mkdir -p "$ROOT/config/bootloaders"
    tmp_splash="$(mktemp --suffix=.png)"
    "${CONVERT[@]}" "$LOGO" -resize "480x480" -strip "$tmp_splash"
    b64_splash="$(base64 -w0 "$tmp_splash")"
    cat > "$ROOT/config/bootloaders/splash.svg" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080" viewBox="0 0 1920 1080">
  <defs>
    <linearGradient id="bg" x1="0%" y1="0%" x2="0%" y2="100%">
      <stop offset="0%" stop-color="#110c22"/>
      <stop offset="100%" stop-color="#2e1065"/>
    </linearGradient>
  </defs>
  <rect width="1920" height="1080" fill="url(#bg)"/>
  <image x="720" y="300" width="480" height="480" href="data:image/png;base64,${b64_splash}"/>
</svg>
EOF
    rm -f "$tmp_splash"
    echo "==> Generated GRUB splash.svg from logo.png"
else
    echo "==> Skipping logo.png (not found in $SOURCES)"
fi

# ---------------------------------------------------------------------------
# Profile picture -> default user avatar (seeded once via /etc/skel/.face,
# so new accounts start with it but can freely change it afterward — never
# re-applied after account creation) + AccountsService's icon cache (so
# GDM's greeter avatar picker shows it immediately too, not just apps that
# read ~/.face directly).
# ---------------------------------------------------------------------------
PFP="$SOURCES/pfp.png"
if [[ -f "$PFP" ]]; then
    echo "==> Processing pfp.png"
    mkdir -p "$CHROOT/etc/skel" "$CHROOT/usr/share/vertex"
    resize "$PFP" "$CHROOT/etc/skel/.face" "512x512"
    cp "$CHROOT/etc/skel/.face" "$CHROOT/usr/share/vertex/face.png"
else
    echo "==> Skipping pfp.png (not found in $SOURCES)"
fi

# ---------------------------------------------------------------------------
# App icons for the two launcher-accessible custom apps (VPKG is CLI-only,
# no icon needed) -> hicolor icon theme, so their .desktop files' Icon=
# resolves by name like any other installed app. update-vertex-apps.sh
# references these exact icon names.
# ---------------------------------------------------------------------------
ICON_SIZES=(16 22 24 32 48 64 128 256 512)
for pair in "vertex-update.png:vertex-update" "vertex-driver.png:vertex-driver"; do
    src_name="${pair%%:*}"
    icon_name="${pair##*:}"
    src="$SOURCES/$src_name"
    if [[ -f "$src" ]]; then
        echo "==> Processing $src_name"
        for size in "${ICON_SIZES[@]}"; do
            dest_dir="$CHROOT/usr/share/icons/hicolor/${size}x${size}/apps"
            mkdir -p "$dest_dir"
            resize "$src" "$dest_dir/$icon_name.png" "${size}x${size}"
        done
    else
        echo "==> Skipping $src_name (not found in $SOURCES)"
    fi
done

# ---------------------------------------------------------------------------
# Wallpapers -> /usr/share/backgrounds/vertex + GNOME background picker XML
# ---------------------------------------------------------------------------
BG_DIR="$CHROOT/usr/share/backgrounds/vertex"
XML_DIR="$CHROOT/usr/share/gnome-background-properties"
mkdir -p "$BG_DIR" "$XML_DIR"

XML_FILE="$XML_DIR/vertex.xml"
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$XML_FILE"
echo '<!DOCTYPE wallpapers SYSTEM "gnome-wp-list.dtd">' >> "$XML_FILE"
echo '<wallpapers>' >> "$XML_FILE"

count=0
default_wallpaper=""
shopt -s nullglob
for src in "$SOURCES"/wallpaper-*.png; do
    name="$(basename "$src" .png)"                # e.g. wallpaper-1
    n="${name#wallpaper-}"                          # e.g. 1
    dest="$BG_DIR/${name}.png"

    # Cap huge source images at 4K to keep the ISO size sane; leave smaller ones as-is.
    dims="$("${CONVERT[@]}" identify -format '%wx%h' "$src" 2>/dev/null || echo "0x0")"
    w="${dims%x*}"
    if [[ "$w" -gt 3840 ]]; then
        resize "$src" "$dest" "3840x2160>"
    else
        cp -f "$src" "$dest"
    fi

    echo "  <wallpaper deleted=\"false\">" >> "$XML_FILE"
    echo "    <name>Vertex ${n}</name>" >> "$XML_FILE"
    echo "    <filename>/usr/share/backgrounds/vertex/${name}.png</filename>" >> "$XML_FILE"
    echo "    <options>zoom</options>" >> "$XML_FILE"
    echo "    <shade_type>solid</shade_type>" >> "$XML_FILE"
    echo "    <pcolor>#4C1D95</pcolor>" >> "$XML_FILE"
    echo "    <scolor>#4C1D95</scolor>" >> "$XML_FILE"
    echo "  </wallpaper>" >> "$XML_FILE"

    [[ -z "$default_wallpaper" ]] && default_wallpaper="/usr/share/backgrounds/vertex/${name}.png"
    count=$((count + 1))
    echo "==> Processed $name.png"
done
echo '</wallpapers>' >> "$XML_FILE"

if [[ "$count" -eq 0 ]]; then
    echo "==> No wallpaper-*.png files found in $SOURCES — skipping backgrounds"
else
    # Wire up the default desktop background via dconf so a fresh install
    # boots straight into one of the presets (still changeable any time from
    # Settings > Background, since all presets are listed in vertex.xml).
    mkdir -p "$CHROOT/etc/dconf/db/local.d"
    cat > "$CHROOT/etc/dconf/db/local.d/01-vertex-background" <<EOF
[org/gnome/desktop/background]
picture-uri='file://${default_wallpaper}'
picture-uri-dark='file://${default_wallpaper}'
picture-options='zoom'

[org/gnome/desktop/screensaver]
picture-uri='file://${default_wallpaper}'
EOF

    # The GDM greeter (login screen) and lock/shutdown dialogs run as the
    # "gdm" user with their own separate dconf profile/database — gdm3
    # ships /etc/dconf/profile/gdm pointing at system-db:gdm by default, so
    # our override just needs to land in /etc/dconf/db/gdm.d/.
    mkdir -p "$CHROOT/etc/dconf/profile" "$CHROOT/etc/dconf/db/gdm.d"
    cat > "$CHROOT/etc/dconf/profile/gdm" <<EOF
user-db:user
system-db:gdm
EOF
    # NOTE: org.gnome.login-screen's "logo" key was removed here — the
    # installed system's login screen never showed a login prompt at all
    # (just the background + top bar), and this custom key is the prime
    # suspect: it's a far less commonly used/battle-tested customization
    # than the background override, and a JS exception while gnome-shell's
    # greeter tries to load it could plausibly crash just the login-form
    # widget construction while the rest of the shell keeps running.
    # Testing with it removed before considering it confirmed.
    cat > "$CHROOT/etc/dconf/db/gdm.d/00-vertex-greeter" <<EOF
[org/gnome/desktop/background]
picture-uri='file://${default_wallpaper}'
picture-uri-dark='file://${default_wallpaper}'
picture-options='zoom'
EOF
    echo "==> Default background set to $default_wallpaper (desktop + GDM greeter)"
fi

echo "==> Done. Assets staged under config/includes.chroot/."
echo "    Rebuild the ISO with scripts/build-iso.sh to pick up the changes."
