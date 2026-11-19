#!/usr/bin/env bash
# Checks tools/fetch_vendors_plugin.sh (#10) against a small local archive:
# the right checksum unpacks the addon, a wrong one fails and unpacks nothing.
# No network: the archive is served as a file:// URL.
# Usage: tools/test_fetch_vendors_plugin.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/tools/fetch_vendors_plugin.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failures=0

fail() {
	echo "FAIL $1" >&2
	failures=$((failures + 1))
}

# Same nesting as the release archive is assumed to have; the script must not
# depend on it.
mkdir -p "$scratch/src/asset/addons/godotopenxrvendors/.bin"
echo '[configuration]' > "$scratch/src/asset/addons/godotopenxrvendors/plugin.gdextension"
echo 'stub' > "$scratch/src/asset/addons/godotopenxrvendors/.bin/lib.so"
(cd "$scratch/src" && zip -qr "$scratch/plugin.zip" asset)
good="$(sha256sum "$scratch/plugin.zip" | cut -d ' ' -f 1)"
bad="$(printf '0%.0s' $(seq 64))"

run_fetch() {
	MELTDOWN_VENDORS_URL="file://$scratch/plugin.zip" \
		MELTDOWN_VENDORS_SHA256="$1" \
		MELTDOWN_VENDORS_DEST="$2" \
		"$script"
}

dest="$scratch/game/addons/godotopenxrvendors"
if run_fetch "$good" "$dest" > "$scratch/good.log" 2>&1 \
	&& [ -f "$dest/plugin.gdextension" ] && [ -f "$dest/.bin/lib.so" ]; then
	echo "ok   matching checksum unpacks the addon"
else
	fail "matching checksum: addon not unpacked"
	cat "$scratch/good.log" >&2
fi

if run_fetch "$good" "$dest" > /dev/null 2>&1 && [ -f "$dest/plugin.gdextension" ] \
	&& [ ! -e "$dest/godotopenxrvendors" ]; then
	echo "ok   a second run replaces the addon in place"
else
	fail "second run: addon missing or nested"
fi

dest="$scratch/wrong/godotopenxrvendors"
if run_fetch "$bad" "$dest" > "$scratch/bad.log" 2>&1; then
	fail "wrong checksum: the script succeeded"
elif [ -e "$dest" ]; then
	fail "wrong checksum: something was unpacked"
elif ! grep -q "Checksum mismatch" "$scratch/bad.log"; then
	fail "wrong checksum: no mismatch message"
	cat "$scratch/bad.log" >&2
else
	echo "ok   wrong checksum fails and unpacks nothing"
fi

if MELTDOWN_VENDORS_URL="file://$scratch/missing.zip" MELTDOWN_VENDORS_SHA256="$good" \
	MELTDOWN_VENDORS_DEST="$scratch/missing/godotopenxrvendors" "$script" > /dev/null 2>&1; then
	fail "missing download: the script succeeded"
else
	echo "ok   failed download fails"
fi

if grep -q '^sha256="[0-9a-f]\{64\}"$' "$script"; then
	echo "ok   the script pins a full SHA-256"
else
	fail "the script does not pin a 64-digit SHA-256"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures vendors plugin fetch check(s) failed" >&2
	exit 1
fi
echo "All vendors plugin fetch checks passed"
