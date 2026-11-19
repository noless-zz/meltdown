#!/usr/bin/env bash
# Downloads the pinned Godot OpenXR Vendors plugin and unpacks it into
# game/addons/godotopenxrvendors/ (issue #10; PLT-2, GFX-1, PRF-1, ARC-5).
# The plugin's Android libraries are binaries, so they are fetched rather than
# committed (owner's choice on #10) and the folder is git-ignored. Only the
# Quest export needs it; desktop, server and unit tests build without it.
# The download is refused unless its SHA-256 matches the value pinned here.
# Usage: tools/fetch_vendors_plugin.sh
# The MELTDOWN_VENDORS_* variables exist for tools/test_fetch_vendors_plugin.sh;
# CI and local builds leave them unset.
set -euo pipefail

version="5.2.0-stable"
url="https://github.com/GodotVR/godot_openxr_vendors/releases/download/${version}/godotopenxrvendorsaddon.zip"
sha256="2a3958fff0de2dbdc4f1a036b5e4cfcea12ae7e45f8deebf4b45e5e9718c4e35"

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
url="${MELTDOWN_VENDORS_URL:-$url}"
sha256="${MELTDOWN_VENDORS_SHA256:-$sha256}"
dest="${MELTDOWN_VENDORS_DEST:-$root/game/addons/godotopenxrvendors}"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

echo "Fetching Godot OpenXR Vendors plugin ${version}"
curl -fsSL --retry 3 -o "$scratch/plugin.zip" "$url"

actual="$(sha256sum "$scratch/plugin.zip" | cut -d ' ' -f 1)"
echo "SHA-256 of the download: $actual"
if [ "$actual" != "$sha256" ]; then
	echo "Checksum mismatch: expected $sha256. Nothing was unpacked." >&2
	exit 1
fi

unzip -q "$scratch/plugin.zip" -d "$scratch/unpacked"
# The archive nests the addon under one or two folders; find it by its
# extension file instead of assuming the layout.
manifest="$(find "$scratch/unpacked" -path '*/godotopenxrvendors/plugin.gdextension' -print -quit)"
if [ -z "$manifest" ]; then
	echo "The archive has no godotopenxrvendors/plugin.gdextension" >&2
	exit 1
fi

rm -rf "$dest"
mkdir -p "$(dirname "$dest")"
mv "$(dirname "$manifest")" "$dest"
echo "Unpacked to $dest"
