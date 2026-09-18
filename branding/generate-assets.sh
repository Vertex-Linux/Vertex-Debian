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
#   logo.png          - square logo/mark, transparent bg, >=1024x1024
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

    # Plymouth boot splash logo (two-step theme expects "watermark.png")
    mkdir -p "$CHROOT/usr/share/plymouth/themes/vertex"
    resize "$LOGO" "$CHROOT/usr/share/plymouth/themes/vertex/watermark.png" "256x256"

    # GNOME About / os-logo used by gnome-control-center "About" panel
    mkdir -p "$CHROOT/usr/share/pixmaps"
    resize "$LOGO" "$CHROOT/usr/share/pixmaps/vertex-logo-text.png" "512x512"
else
    echo "==> Skipping logo.png (not found in $SOURCES)"
fi

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
    echo "==> Default background set to $default_wallpaper"
fi

echo "==> Done. Assets staged under config/includes.chroot/."
echo "    Rebuild the ISO with scripts/build-iso.sh to pick up the changes."
