#!/usr/bin/env bash
# Updates every connected Quest headset to the newest `main` build in one step
# (DEV-8, playtest #104): downloads the APK and its checksum from the rolling
# `main-latest` release, refuses to install on a checksum mismatch, and runs
# `adb install -r` on each headset adb lists as `device` (USB or ADB over
# Wi-Fi). The builds are signed with a stable debug key, so `install -r`
# updates in place and keeps saved data.
#
# Usage: tools/update_quest.sh [--launch] [--uninstall-first]
#   --launch           start the game on each headset after installing
#   --uninstall-first  if a headset holds a copy signed with another key,
#                      uninstall it and install again (its saved data is lost)
#
# Needs bash, curl, adb and sha256sum (or shasum on macOS).
set -euo pipefail

# Overridable so tools/test_update_quest.sh can run without the network.
release_url="${MELTDOWN_RELEASE_URL:-https://github.com/noless-zz/meltdown/releases/download/main-latest}"
release_api="${MELTDOWN_RELEASE_API:-https://api.github.com/repos/noless-zz/meltdown/releases/tags/main-latest}"

apk_name="meltdown-quest-debug.apk"
package="io.github.nolesszz.meltdown"
launch=0
uninstall_first=0

usage() {
	echo "Usage: $0 [--launch] [--uninstall-first]"
}

for arg in "$@"; do
	case "$arg" in
		--launch) launch=1 ;;
		--uninstall-first) uninstall_first=1 ;;
		-h|--help) usage; exit 0 ;;
		*) usage >&2; exit 2 ;;
	esac
done

for tool in curl adb; do
	if ! command -v "$tool" > /dev/null; then
		echo "Missing required tool: $tool" >&2
		exit 1
	fi
done

sha256_of() {
	if command -v sha256sum > /dev/null; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum > /dev/null; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		echo "Missing required tool: sha256sum or shasum" >&2
		exit 1
	fi
}

# Checked before downloading so a forgotten cable fails in a second, not
# after a large download.
serials=()
while read -r serial state _; do
	if [ "$state" = "device" ]; then
		serials+=("$serial")
	fi
done < <(adb devices | tail -n +2)

if [ "${#serials[@]}" -eq 0 ]; then
	echo "No headset found. Connect one by USB (and allow USB debugging in the headset)," >&2
	echo "or over Wi-Fi with 'adb connect <headset-ip>:5555', then check 'adb devices'." >&2
	exit 1
fi

work="$(mktemp -d)"
keep_download=0
# Kept after a failed install so the printed manual command has a file to use.
trap '[ "$keep_download" -eq 1 ] || rm -rf "$work"' EXIT

echo "Downloading $apk_name from the main-latest release..."
curl -fsSL -o "$work/$apk_name" "$release_url/$apk_name"
curl -fsSL -o "$work/$apk_name.sha256" "$release_url/$apk_name.sha256"

expected="$(cut -d' ' -f1 < "$work/$apk_name.sha256" | tr 'A-F' 'a-f')"
actual="$(sha256_of "$work/$apk_name")"
if [ "$expected" != "$actual" ]; then
	echo "Checksum mismatch: the release says $expected but the download is $actual." >&2
	echo "Nothing was installed. Try again in a few minutes; the release may be mid-upload." >&2
	exit 1
fi
echo "Checksum verified: $actual"

# The release body (tools/release_notes.sh) names the commit and build time.
# The API is only for these two lines, so a failure there does not stop the
# update.
commit="unknown"
built="Built: unknown"
if curl -fsSL -o "$work/release.json" "$release_api" 2> /dev/null; then
	commit="$(grep -oE 'commit [0-9a-f]{40}' "$work/release.json" | head -n 1 | cut -d' ' -f2 || true)"
	built="$(grep -oE 'Built: [^"\\]*' "$work/release.json" | head -n 1 || true)"
	commit="${commit:-unknown}"
	built="${built:-Built: unknown}"
fi

# A failure with no `Failure [...]` part has been seen once on a headset that
# then took the same APK by hand (#210), so it is retried once without
# streaming. A failure with a reason is not retried: the reason will not
# change. Sets $output to the last attempt's text.
install_apk() {
	local serial="$1"
	if output="$(adb -s "$serial" install -r "$work/$apk_name" 2>&1)"; then
		return 0
	fi
	if grep -q 'Failure \[' <<< "$output"; then
		return 1
	fi
	echo "  adb gave no reason; trying once more with --no-streaming..."
	output="$(adb -s "$serial" install -r --no-streaming "$work/$apk_name" 2>&1)"
}

# Always ends with adb's reason, or a plain statement that it gave none, and
# the command to try by hand.
report_failure() {
	local serial="$1"
	local reason line
	echo "  Install failed on $serial:" >&2
	while IFS= read -r line; do
		echo "    $line" >&2
	done <<< "$output"
	reason="$(grep -o 'Failure \[.*\]' <<< "$output" | head -n 1 || true)"
	if [ -n "$reason" ]; then
		echo "  Reason: $reason" >&2
	else
		echo "  adb gave no reason." >&2
	fi
	echo "  To try by hand: adb -s $serial install -r \"$work/$apk_name\"" >&2
	keep_download=1
}

failed=0
installed=()
for serial in "${serials[@]}"; do
	echo "Installing on $serial..."
	if install_apk "$serial"; then
		installed+=("$serial")
		echo "  Installed."
		continue
	fi
	if grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE" <<< "$output"; then
		echo "  The copy on $serial has a different signature, so it cannot be updated in place."
		if [ "$uninstall_first" -eq 1 ]; then
			echo "  Uninstalling it first; its saved data is lost."
			adb -s "$serial" uninstall "$package" > /dev/null 2>&1 || true
			if install_apk "$serial"; then
				installed+=("$serial")
				echo "  Installed."
				continue
			fi
		else
			echo "  Run again with --uninstall-first to remove it and install (saved data is lost)."
			failed=1
			continue
		fi
	fi
	report_failure "$serial"
	failed=1
done

if [ "$keep_download" -eq 1 ]; then
	echo "The download is kept in $work for that; delete the folder when done." >&2
fi

echo
echo "Build: commit $commit"
echo "$built"

if [ "$launch" -eq 1 ]; then
	# The expansion guards an empty list under `set -u` in macOS's bash 3.2.
	for serial in ${installed[@]+"${installed[@]}"}; do
		echo "Starting the game on $serial..."
		adb -s "$serial" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 > /dev/null
	done
fi

exit "$failed"
