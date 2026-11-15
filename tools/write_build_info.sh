#!/usr/bin/env bash
# Writes the commit and build time into a text resource that every export
# carries, so a build can later be compared with the `main-latest` release
# (DEV-8, ARC-6). The file is a plain Resource with metadata, so it needs no
# script and the export filter already takes it. Read by game/meta/build_info.gd.
# Usage: tools/write_build_info.sh <commit-sha> <unix-time> <output>
set -euo pipefail

if [ "$#" -ne 3 ]; then
	echo "Usage: $0 <commit-sha> <unix-time> <output>" >&2
	exit 2
fi

commit="$1"
built_unix="$2"
out="$3"

if ! [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]]; then
	echo "The commit must be 40 hexadecimal characters, got '$commit'" >&2
	exit 2
fi
if ! [[ "$built_unix" =~ ^[0-9]+$ ]]; then
	echo "The build time must be a Unix time in seconds, got '$built_unix'" >&2
	exit 2
fi
commit="$(tr 'A-F' 'a-f' <<< "$commit")"
# Strip leading zeros so the value is a plain integer, not an octal-looking one.
built_unix="$((10#$built_unix))"

# Write next to the target and rename, so a failed write never leaves half a file.
tmp="$(mktemp "${out}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
cat > "$tmp" <<RESOURCE
[gd_resource type="Resource" format=3]

[resource]
metadata/commit = "${commit}"
metadata/built_unix = ${built_unix}
RESOURCE
mv "$tmp" "$out"
trap - EXIT
