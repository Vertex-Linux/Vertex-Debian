#!/bin/sh
# Downloads/updates Vertex Linux's own custom tools straight from their
# GitHub releases: VPKG (CLI package manager), Vertex Updater, and Vertex
# Driver Downloader (the latter two are launcher-accessible GUI apps).
# Safe to re-run anytime on an installed system too — it always fetches
# whatever the current latest matching release is and replaces what's
# there, which is what makes this the actual update mechanism for these
# tools (they aren't apt packages).
#
# vertex-tools' releases are shared across several of that repo's tools,
# distinguished only by tag naming convention (confirmed against the real
# repo's release history):
#   vpkg-<version>       -> vpkg          (e.g. vpkg-1.11.0)
#   <version>-vu         -> Vertex Updater (e.g. 1.9.0-vu)
# Each release ships one asset per architecture, named
# "<binary-name>-<arch>-unknown-linux-gnu" (Rust target triples) — we grab
# the x86_64 one and strip that suffix so users just run "vpkg", not
# "vpkg-x86_64-unknown-linux-gnu".
#
# vertex-graphics-installer is a dedicated repo for just the one app, so
# its plain /releases/latest endpoint is used directly instead of tag
# pattern matching, and its single release asset ("vertex-drivers", no
# architecture suffix) needs no renaming.
set -e

BIN_DIR="/usr/local/bin"
APPS_DIR="/usr/share/applications"
VERTEX_TOOLS_REPO="Vertex-Linux/vertex-tools"
GRAPHICS_INSTALLER_REPO="Vertex-Linux/vertex-graphics-installer"

mkdir -p "$BIN_DIR" "$APPS_DIR"

# fetch_release_by_tag_pattern <owner/repo> <regex-for-tag_name>
# Prints the JSON of the newest release (releases are listed newest-first)
# whose tag_name matches the given regex, or nothing if none match.
fetch_release_by_tag_pattern() {
    curl -fsSL "https://api.github.com/repos/$1/releases?per_page=100" 2>/dev/null | python3 -c '
import json, re, sys
pattern = re.compile(sys.argv[1])
try:
    releases = json.load(sys.stdin)
except Exception:
    releases = []
for r in releases:
    if pattern.search(r.get("tag_name", "")):
        print(json.dumps(r))
        break
' "$2"
}

# pick_asset_url <release-json> <substring-to-prefer>
# Prints the browser_download_url of the asset whose name contains the
# given substring (case-insensitive), falling back to the first asset if
# none match (covers single-asset releases with no arch suffix at all).
pick_asset_url() {
    printf '%s' "$1" | python3 -c '
import json, sys
try:
    r = json.load(sys.stdin)
except Exception:
    r = {}
needle = sys.argv[1].lower()
assets = r.get("assets", [])
match = next((a for a in assets if needle in a["name"].lower()), None)
if match is None and assets:
    match = assets[0]
print(match["browser_download_url"] if match else "")
' "$2"
}

# install_binary <download-url> <dest-name>
install_binary() {
    if [ -z "$1" ]; then
        echo "==> No asset URL given, skipping $2" >&2
        return 1
    fi
    echo "==> Downloading $2: $1"
    curl -fsSL "$1" -o "$BIN_DIR/$2.new"
    chmod +x "$BIN_DIR/$2.new"
    mv -f "$BIN_DIR/$2.new" "$BIN_DIR/$2"
    echo "==> Installed $BIN_DIR/$2"
}

# create_desktop_file_if_missing <path> <name> <comment> <exec> <icon>
create_desktop_file_if_missing() {
    if [ -f "$1" ]; then
        return 0
    fi
    cat > "$1" <<DESKTOPEOF
[Desktop Entry]
Type=Application
Name=$2
Comment=$3
Exec=$4
Icon=$5
Terminal=false
StartupNotify=true
Categories=System;Settings;
DESKTOPEOF
    echo "==> Created $1"
}

echo "==> Checking $VERTEX_TOOLS_REPO for the latest vpkg release..."
vpkg_release="$(fetch_release_by_tag_pattern "$VERTEX_TOOLS_REPO" '^vpkg-')"
if [ -n "$vpkg_release" ]; then
    install_binary "$(pick_asset_url "$vpkg_release" x86_64)" vpkg || true
else
    echo "==> No vpkg-* release found, skipping" >&2
fi

echo "==> Checking $VERTEX_TOOLS_REPO for the latest Vertex Updater release..."
vu_release="$(fetch_release_by_tag_pattern "$VERTEX_TOOLS_REPO" '\-vu$')"
if [ -n "$vu_release" ]; then
    install_binary "$(pick_asset_url "$vu_release" x86_64)" vertex-update || true
else
    echo "==> No *-vu release found, skipping" >&2
fi
create_desktop_file_if_missing "$APPS_DIR/vertex-updater.desktop" \
    "Vertex Updater" "Check for and install Vertex Linux updates" \
    "$BIN_DIR/vertex-update" "vertex-update"

echo "==> Checking $GRAPHICS_INSTALLER_REPO for its latest release..."
gd_release="$(curl -fsSL "https://api.github.com/repos/$GRAPHICS_INSTALLER_REPO/releases/latest" 2>/dev/null || true)"
if [ -n "$gd_release" ] && printf '%s' "$gd_release" | python3 -c 'import json,sys; sys.exit(0 if "tag_name" in json.load(sys.stdin) else 1)' 2>/dev/null; then
    install_binary "$(pick_asset_url "$gd_release" x86_64)" vertex-drivers || true
else
    echo "==> No releases found for $GRAPHICS_INSTALLER_REPO, skipping" >&2
fi
create_desktop_file_if_missing "$APPS_DIR/vertex-driver-downloader.desktop" \
    "Vertex Driver Downloader" "Download and install graphics drivers for Vertex Linux" \
    "$BIN_DIR/vertex-drivers" "vertex-driver"

echo "==> Done."
