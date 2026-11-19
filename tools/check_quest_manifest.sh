#!/usr/bin/env bash
# Prints the built Quest APK's Android manifest into the log and fails unless
# it declares com.oculus.supportedDevices with quest3 (issue #10, #598;
# PRF-1, PLT-2). Without that entry the Quest runtime offers the app only
# 72 Hz. The Meta vendor options of the export preset write it.
# Usage: tools/check_quest_manifest.sh <apk>
# Uses $AAPT2 if set, otherwise the newest aapt2 under $ANDROID_HOME.
set -euo pipefail

apk="${1:-}"
if [ -z "$apk" ] || [ ! -f "$apk" ]; then
	echo "Usage: tools/check_quest_manifest.sh <apk>" >&2
	exit 2
fi

aapt2="${AAPT2:-}"
if [ -z "$aapt2" ]; then
	aapt2="$(find "${ANDROID_HOME:?ANDROID_HOME is not set}/build-tools" -name aapt2 -type f | sort -V | tail -n 1)"
fi
if [ -z "$aapt2" ]; then
	echo "aapt2 not found; set AAPT2 or ANDROID_HOME" >&2
	exit 2
fi

dump="$("$aapt2" dump xmltree --file AndroidManifest.xml "$apk")"
echo "$dump"

# aapt2 prints each attribute on its own line; the value of a meta-data
# element follows its name within the same element.
devices="$(echo "$dump" | awk '
	/E: meta-data/ { in_meta = 1; name = ""; next }
	/E: / { in_meta = 0 }
	in_meta && /android:name\(/ && /"com\.oculus\.supportedDevices"/ { name = "devices"; next }
	in_meta && name == "devices" && /android:value\(/ {
		match($0, /="[^"]*"/)
		print substr($0, RSTART + 2, RLENGTH - 3)
		exit
	}
')"

if [ -z "$devices" ]; then
	echo "::error::The APK manifest has no com.oculus.supportedDevices entry" >&2
	exit 1
fi
echo "com.oculus.supportedDevices = $devices"
if ! echo "|$devices|" | grep -q '|quest3|'; then
	echo "::error::com.oculus.supportedDevices does not list quest3" >&2
	exit 1
fi
echo "Manifest declares Quest 3 support"
