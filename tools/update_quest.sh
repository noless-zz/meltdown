#!/usr/bin/env bash
# Updates every connected Quest headset to the newest `main` build in one step
# (DEV-8, playtest #104). Reads only the checksum from the rolling
# `main-latest` release first and skips each headset whose installed APK
# already has it (#1437). If any headset needs the build, downloads the APK
# once (kept per checksum under the temp folder, so a rerun does not download
# it again), refuses to install on a checksum mismatch, and runs
# `adb install -r` on each headset that needs it among those adb lists as
# `device` (USB or ADB over Wi-Fi). The builds are signed with a stable debug
# key, so `install -r` updates in place and keeps saved data.
#
# Usage: tools/update_quest.sh [--launch] [--uninstall-first] [--force]
#   --launch           start the game on each headset after updating
#   --uninstall-first  if a headset holds a copy signed with another key,
#                      uninstall it and install again (its saved data is lost)
#   --force            install even where the headset already has the build
#                      (also MELTDOWN_FORCE_INSTALL=1)
#
# Needs bash, curl, adb and sha256sum (or shasum on macOS).
set -euo pipefail

# Overridable so tools/test_update_quest.sh can run without the network.
release_url="${MELTDOWN_RELEASE_URL:-https://github.com/noless-zz/meltdown/releases/download/main-latest}"
release_api="${MELTDOWN_RELEASE_API:-https://api.github.com/repos/noless-zz/meltdown/releases/tags/main-latest}"
# How long to wait for a headset to (re)appear on adb before an install
# attempt (#589). A headset just plugged in or woken drops off adb for a few
# seconds; 20 s covers that without hanging on one that is really gone.
device_wait_seconds="${MELTDOWN_DEVICE_WAIT_SECONDS:-20}"
# Retries after a failure with no reason, `not found` or `offline` (#589).
install_retries=2

apk_name="meltdown-quest-debug.apk"
package="io.github.nolesszz.meltdown"
launch=0
uninstall_first=0
force="${MELTDOWN_FORCE_INSTALL:-0}"
[ "$force" = "1" ] || force=0

usage() {
	echo "Usage: $0 [--launch] [--uninstall-first] [--force]"
}

for arg in "$@"; do
	case "$arg" in
		--launch) launch=1 ;;
		--uninstall-first) uninstall_first=1 ;;
		--force) force=1 ;;
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
trap 'rm -rf "$work"' EXIT
# One verified APK per checksum, kept between runs (#1437).
tmp_base="${TMPDIR:-/tmp}"
cache_root="${tmp_base%/}/meltdown-apk-cache"

# The digest from the first non-empty line of `sha256sum` output on stdin,
# lowercase, or nothing when that line does not start with one.
sha_from_text() {
	local line field
	while IFS= read -r line || [ -n "$line" ]; do
		line="${line//$'\r'/}"
		read -r field _ <<< "$line" || true
		if [ -z "$field" ]; then
			continue
		fi
		# sha256sum prefixes the line with a backslash when it escapes the file name.
		field="$(tr 'A-F' 'a-f' <<< "${field#\\}")"
		if [[ "$field" =~ ^[0-9a-f]{64}$ ]]; then
			echo "$field"
		fi
		return 0
	done
}

# Only the checksum first: a few bytes, not the APK. Unreadable means every
# headset is installed, as before.
expected=""
if curl -fsSL -o "$work/release.sha256" "$release_url/$apk_name.sha256" 2> /dev/null; then
	expected="$(sha_from_text < "$work/release.sha256")"
fi

# The release body (tools/release_notes.sh) names the commit and build time.
# The API is only for these lines, so a failure there does not stop the
# update.
commit="unknown"
built="Built: unknown"
if curl -fsSL -o "$work/release.json" "$release_api" 2> /dev/null; then
	commit="$(grep -oE 'commit [0-9a-f]{40}' "$work/release.json" | head -n 1 | cut -d' ' -f2 || true)"
	built="$(grep -oE 'Built: [^"\\]*' "$work/release.json" | head -n 1 || true)"
	commit="${commit:-unknown}"
	built="${built:-Built: unknown}"
fi

# The checksum of the build installed on the headset, or nothing when the
# package is missing or anything about the answer is unclear.
headset_sha() {
	local serial="$1" paths base sum
	paths="$(adb -s "$serial" shell pm path "$package" 2> /dev/null)" || return 0
	base="$(tr -d '\r' <<< "$paths" | grep -E '^package:/[^[:space:]]*/base\.apk$' | head -n 1 || true)"
	base="${base#package:}"
	if [ -z "$base" ]; then
		return 0
	fi
	sum="$(adb -s "$serial" shell sha256sum "$base" 2> /dev/null)" || return 0
	sha_from_text <<< "$sum"
}

# Whether the headset holds exactly the release's build. Never true on doubt.
has_build() {
	local installed
	[ -n "$expected" ] || return 1
	installed="$(headset_sha "$1")"
	[ -n "$installed" ] && [ "$installed" = "$expected" ]
}

skip_line() {
	local build="this build"
	if [[ "$commit" =~ ^[0-9a-f]{7,}$ ]]; then
		build="build ${commit:0:7}"
	fi
	echo "Headset $1 already has $build (checksum ${expected:0:12} matches); skipping download and install."
}

# Sets $apk to the release APK, verified, at <cache>/<checksum>/. A cached copy
# with the release's checksum is used without downloading. Older builds are
# deleted, and so are downloads left over from a run over an hour ago.
fetch_apk() {
	local partial actual entry name
	if [ -n "$expected" ] && [ -f "$cache_root/$expected/$apk_name" ] \
		&& [ "$(sha256_of "$cache_root/$expected/$apk_name")" = "$expected" ]; then
		echo "Using the copy already downloaded (${expected:0:12})."
		actual="$expected"
	else
		mkdir -p "$cache_root"
		partial="$(mktemp -d "$cache_root/partial-XXXXXX")"
		echo "Downloading $apk_name from the main-latest release..."
		if ! curl -fsSL -o "$partial/$apk_name" "$release_url/$apk_name" \
			|| ! curl -fsSL -o "$partial/$apk_name.sha256" "$release_url/$apk_name.sha256"; then
			rm -rf "$partial"
			echo "Could not download the build. Nothing was installed." >&2
			exit 1
		fi
		local release_sha
		release_sha="$(cut -d' ' -f1 < "$partial/$apk_name.sha256" | tr 'A-F' 'a-f')"
		actual="$(sha256_of "$partial/$apk_name")"
		if [ "$release_sha" != "$actual" ]; then
			rm -rf "$partial"
			echo "Checksum mismatch: the release says $release_sha but the download is $actual." >&2
			echo "Nothing was installed. Try again in a few minutes; the release may be mid-upload." >&2
			exit 1
		fi
		echo "Checksum verified: $actual"
		# Named by what was downloaded: the release may have moved on since
		# $expected was read.
		rm -rf "${cache_root:?}/$actual"
		mv "$partial" "$cache_root/$actual"
	fi
	apk="$cache_root/$actual/$apk_name"
	for entry in "$cache_root"/*/; do
		[ -d "$entry" ] || continue
		name="$(basename "$entry")"
		if [ "$name" = "$actual" ]; then
			continue
		fi
		if [[ "$name" == partial-* ]] && [ -n "$(find "$entry" -maxdepth 0 -mmin -60)" ]; then
			continue
		fi
		rm -rf "$entry"
	done
}

# Waits up to $device_wait_seconds for adb to list the headset again, then
# runs a trivial shell command to wake the connection (#589). `adb
# wait-for-device` has no timeout of its own, and macOS has no `timeout`, so
# it runs in the background and is stopped when time is up.
wait_for_device() {
	local serial="$1"
	local ticks=$((device_wait_seconds * 5))
	local pid
	adb -s "$serial" wait-for-device > /dev/null 2>&1 &
	pid=$!
	while kill -0 "$pid" 2> /dev/null; do
		if [ "$ticks" -le 0 ]; then
			kill "$pid" 2> /dev/null || true
			wait "$pid" 2> /dev/null || true
			return 1
		fi
		sleep 0.2
		ticks=$((ticks - 1))
	done
	wait "$pid" || return 1
	adb -s "$serial" shell true > /dev/null 2>&1
}

# adb's text when the headset was not on adb at that moment (#589).
dropped_off() {
	grep -qE "device( '[^']*')? not found|device offline|did not come back" <<< "$1"
}

# A failure with no `Failure [...]` part (#210), or with the headset `not
# found` or `offline` (#589), is the headset dropping off adb for a moment
# after being plugged in or woken. So the script waits for the headset and
# retries without streaming, up to $install_retries times. A failure with a
# reason is not retried: the reason will not change. Sets $output to the last
# attempt's text.
install_apk() {
	local serial="$1"
	local attempt=0
	if output="$(adb -s "$serial" install -r "$apk" 2>&1)"; then
		return 0
	fi
	while [ "$attempt" -lt "$install_retries" ]; do
		if grep -q 'Failure \[' <<< "$output"; then
			return 1
		fi
		attempt=$((attempt + 1))
		if dropped_off "$output"; then
			echo "  The headset dropped off USB for a moment; waiting for it, then trying again with --no-streaming..."
		else
			echo "  adb gave no reason; waiting for the headset, then trying again with --no-streaming..."
		fi
		if ! wait_for_device "$serial"; then
			output="$output"$'\n'"The headset did not come back within $device_wait_seconds s."
			return 1
		fi
		if output="$(adb -s "$serial" install -r --no-streaming "$apk" 2>&1)"; then
			return 0
		fi
	done
	return 1
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
	elif dropped_off "$output"; then
		echo "  Reason: the headset dropped off USB for a moment and was not back in time." >&2
		echo "  Check the cable and that the headset is awake, then run this again." >&2
	else
		echo "  adb gave no reason." >&2
	fi
	echo "  To try by hand: adb -s $serial install -r \"$apk\"" >&2
}

failed=0
ready=()
needed=()
# Decided per headset; the APK is fetched once, and only if one needs it.
for serial in "${serials[@]}"; do
	# Wakes the connection first: the first adb call after plugging in or
	# waking the headset used to land in its drop-off gap (#589).
	wait_for_device "$serial" || true
	if [ "$force" -eq 0 ] && has_build "$serial"; then
		skip_line "$serial"
		ready+=("$serial")
	else
		needed+=("$serial")
	fi
done

apk=""
if [ "${#needed[@]}" -gt 0 ]; then
	if [ "$force" -eq 1 ]; then
		echo "Installing whatever the headsets hold (--force or MELTDOWN_FORCE_INSTALL=1)."
	fi
	fetch_apk
fi

for serial in ${needed[@]+"${needed[@]}"}; do
	echo "Installing on $serial..."
	# Woken again: the download may have taken long enough for it to doze. A
	# headset that does not answer still gets the install attempt and its
	# retries.
	wait_for_device "$serial" || true
	if install_apk "$serial"; then
		ready+=("$serial")
		echo "  Installed."
		continue
	fi
	if grep -q "INSTALL_FAILED_UPDATE_INCOMPATIBLE" <<< "$output"; then
		echo "  The copy on $serial has a different signature, so it cannot be updated in place."
		if [ "$uninstall_first" -eq 1 ]; then
			echo "  Uninstalling it first; its saved data is lost."
			adb -s "$serial" uninstall "$package" > /dev/null 2>&1 || true
			if install_apk "$serial"; then
				ready+=("$serial")
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

if [ "$failed" -eq 1 ] && [ -n "$apk" ]; then
	echo "The download is kept at $apk; the next run uses it without downloading again." >&2
fi

echo
echo "Build: commit $commit"
echo "$built"

if [ "$launch" -eq 1 ]; then
	# The expansion guards an empty list under `set -u` in macOS's bash 3.2.
	for serial in ${ready[@]+"${ready[@]}"}; do
		echo "Starting the game on $serial..."
		adb -s "$serial" shell monkey -p "$package" -c android.intent.category.LAUNCHER 1 > /dev/null
	done
fi

exit "$failed"
