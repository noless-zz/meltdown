#!/usr/bin/env bash
# Builds one target with the same commands CI uses (ARC-6).
# Usage: tools/build.sh quest|server|desktop
# Needs `godot` (matching export templates installed) on PATH. The quest
# target also needs the Android SDK, JDK 17 and a debug keystore configured
# in Godot's editor settings or the GODOT_ANDROID_KEYSTORE_DEBUG_* variables.
set -euo pipefail

target="${1:-}"
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$root/build"

# export_preset <preset name> <output file> [extra godot arguments...]
export_preset() {
	local preset="$1" out="$2"
	shift 2
	rm -f "$out"
	godot --headless --path "$root/game" --import
	godot --headless --path "$root/game" "$@" --export-debug "$preset" "$out"
	# Godot can exit 0 after a failed export, so check for the file.
	if [ ! -s "$out" ]; then
		echo "Export failed: $out was not produced" >&2
		exit 1
	fi
	ls -lh "$out"
}

case "$target" in
	quest)
		export_preset "Android Quest" "$root/build/meltdown-quest-debug.apk" \
			--install-android-build-template
		;;
	server)
		export_preset "Linux Server" "$root/build/meltdown-server.x86_64"
		;;
	desktop)
		export_preset "Linux Desktop" "$root/build/meltdown-desktop.x86_64"
		;;
	*)
		echo "Usage: tools/build.sh quest|server|desktop" >&2
		exit 2
		;;
esac
