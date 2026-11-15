class_name BuildInfo
extends RefCounted

## The commit and time a build was made from, written by
## `tools/write_build_info.sh` during `tools/build.sh` (DEV-8, ARC-6). A later
## step compares it with the `main-latest` release. A local editor run has no
## file, so anything missing or malformed reads as unknown instead of stopping
## the game.

## Where `tools/build.sh` writes the file. Generated and never committed.
const DEFAULT_PATH: String = "res://meta/build_info.tres"
const UNKNOWN: String = "unknown"
const COMMIT_LENGTH: int = 40
const SHORT_LENGTH: int = 7
const HEX_DIGITS: String = "0123456789abcdef"

## Lowercase 40-character commit hash, or `UNKNOWN`.
var commit: String = UNKNOWN
## Build time in Unix seconds, or 0 when unknown.
var built_unix: int = 0


static func load_from(path: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	# ResourceLoader rather than FileAccess: an export may convert the text
	# resource to binary and remap its path.
	if not ResourceLoader.exists(path):
		return info
	var resource: Resource = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
	if resource == null:
		return info
	var commit_value: Variant = resource.get_meta(&"commit", null)
	if commit_value is String and is_full_commit(commit_value):
		info.commit = String(commit_value).to_lower()
	var time_value: Variant = resource.get_meta(&"built_unix", null)
	if time_value is int and int(time_value) > 0:
		info.built_unix = int(time_value)
	return info


static func is_full_commit(text: String) -> bool:
	if text.length() != COMMIT_LENGTH:
		return false
	for c: String in text.to_lower():
		if not HEX_DIGITS.contains(c):
			return false
	return true


func short_commit() -> String:
	if commit == UNKNOWN:
		return UNKNOWN
	return commit.substr(0, SHORT_LENGTH)


## For example `"1a2b3c4, built 2026-11-15 16:00 UTC"`.
func describe() -> String:
	if built_unix <= 0:
		return "%s, build time unknown" % short_commit()
	# Unix time has no zone, so this is UTC whatever the device's zone is.
	var stamp: String = Time.get_datetime_string_from_unix_time(built_unix, true)
	return "%s, built %s UTC" % [short_commit(), stamp.substr(0, 16)]
