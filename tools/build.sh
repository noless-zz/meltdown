#!/usr/bin/env bash
# Builds one target with the same commands CI uses (ARC-6).
# Usage: tools/build.sh quest
# Needs `godot` (matching export templates installed) on PATH. The quest
# target also needs the Android SDK, JDK 17 and a debug keystore configured
# in Godot's editor settings or the GODOT_ANDROID_KEYSTORE_DEBUG_* variables.
set -euo pipefail

target="${1:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build"

case "$target" in
	quest)
		out="$root/build/meltdown-quest-debug.apk"
		rm -f "$out"
		godot --headless --path "$root/game" --import
		godot --headless --path "$root/game" --install-android-build-template \
			--export-debug "Android Quest" "$out"
		# Godot can exit 0 after a failed export, so check for the file.
		if [ ! -s "$out" ]; then
			echo "Export failed: $out was not produced" >&2
			exit 1
		fi
		ls -lh "$out"
		;;
	*)
		echo "Usage: tools/build.sh quest" >&2
		exit 2
		;;
esac
