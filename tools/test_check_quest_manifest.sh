#!/usr/bin/env bash
# Checks tools/check_quest_manifest.sh (#10) with a stub aapt2 that prints
# manifests in aapt2's `dump xmltree` format, so no Android SDK is needed.
# Usage: tools/test_check_quest_manifest.sh
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
script="$root/tools/check_quest_manifest.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
failures=0

fail() {
	echo "FAIL $1" >&2
	failures=$((failures + 1))
}

cat > "$scratch/aapt2" << 'EOF'
#!/usr/bin/env bash
cat "$STUB_MANIFEST"
EOF
chmod +x "$scratch/aapt2"
touch "$scratch/app.apk"

ns="http://schemas.android.com/apk/res/android"

# manifest_with <supportedDevices value, or empty for no entry>
manifest_with() {
	echo "N: android=$ns (line=2)"
	echo "  E: manifest (line=2)"
	echo "    A: $ns:versionCode(0x0101021b)=1"
	echo "      E: application (line=20)"
	echo "        E: meta-data (line=30)"
	echo "          A: $ns:name(0x01010003)=\"org.godotengine.editor.version\" (Raw: \"org.godotengine.editor.version\")"
	echo "          A: $ns:value(0x01010024)=\"4.7.2.stable\" (Raw: \"4.7.2.stable\")"
	if [ -n "$1" ]; then
		echo "        E: meta-data (line=31)"
		echo "          A: $ns:name(0x01010003)=\"com.oculus.supportedDevices\" (Raw: \"com.oculus.supportedDevices\")"
		echo "          A: $ns:value(0x01010024)=\"$1\" (Raw: \"$1\")"
	fi
	echo "        E: activity (line=40)"
	echo "          A: $ns:name(0x01010003)=\"com.godot.game.GodotApp\" (Raw: \"com.godot.game.GodotApp\")"
}

check() {
	local name="$1" devices="$2" want="$3"
	manifest_with "$devices" > "$scratch/manifest.txt"
	if STUB_MANIFEST="$scratch/manifest.txt" AAPT2="$scratch/aapt2" "$script" "$scratch/app.apk" \
		> "$scratch/out.log" 2>&1; then
		got=pass
	else
		got=fail
	fi
	if [ "$got" != "$want" ]; then
		fail "$name: expected $want, got $got"
		cat "$scratch/out.log" >&2
	elif ! grep -q 'E: manifest' "$scratch/out.log"; then
		fail "$name: the manifest was not printed to the log"
	else
		echo "ok   $name"
	fi
}

check "Quest 2, Pro, 3 and 3S pass" "quest2|quest3|quest3s|questpro" pass
check "quest3 alone passes" "quest3" pass
check "no supportedDevices entry fails" "" fail
check "only quest3s fails" "quest2|quest3s" fail

if "$script" "$scratch/none.apk" > /dev/null 2>&1; then
	fail "missing APK: the script succeeded"
else
	echo "ok   missing APK fails"
fi

if [ "$failures" -gt 0 ]; then
	echo "$failures Quest manifest check(s) failed" >&2
	exit 1
fi
echo "All Quest manifest checks passed"
