class_name UpdateSettings
extends RefCounted

## Where the in-app update check asks, how long it waits, and whether it runs
## at all (#646, DEV-8, PLT-1). Data, not code (ARC-4), so the owner can turn
## the check off or give it longer on a slow network without a new build. A
## missing or rejected file turns the check off: no file, no network.

const DEFAULT_FILE: String = "res://data/update_check.json"
const KEY_ENABLED: String = "enabled"
const KEY_URL: String = "url"
const KEY_TIMEOUT: String = "timeout_seconds"
const KEYS: Array[String] = [KEY_ENABLED, KEY_URL, KEY_TIMEOUT]
const DEFAULT_URL: String = "https://api.github.com/repos/noless-zz/meltdown/releases/tags/main-latest"
## Inclusive range of `timeout_seconds`. Under a second fails on any headset
## Wi-Fi; over a minute leaves the pilot wondering whether anything happened.
const MIN_TIMEOUT_SECONDS: float = 1.0
const MAX_TIMEOUT_SECONDS: float = 60.0

var enabled: bool = false
var url: String = DEFAULT_URL
var timeout_seconds: float = 10.0
## Set when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of the data file: one JSON object with exactly `KEYS`.
## A rejected text gives settings with `enabled` false and `error` set.
static func parse_json(text: String) -> UpdateSettings:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	if typeof(data[KEY_ENABLED]) != TYPE_BOOL:
		return _rejected("key \"%s\" must be true or false" % KEY_ENABLED)
	if typeof(data[KEY_URL]) != TYPE_STRING or not String(data[KEY_URL]).begins_with("https://"):
		return _rejected("key \"%s\" must be an https:// address" % KEY_URL)
	var timeout: Variant = data[KEY_TIMEOUT]
	# A bool must not pass as 0 or 1.
	if typeof(timeout) != TYPE_FLOAT and typeof(timeout) != TYPE_INT:
		return _rejected("key \"%s\" must be a number" % KEY_TIMEOUT)
	if float(timeout) < MIN_TIMEOUT_SECONDS or float(timeout) > MAX_TIMEOUT_SECONDS:
		return _rejected("key \"%s\" is %s, must be within %s..%s" % [
			KEY_TIMEOUT, timeout, MIN_TIMEOUT_SECONDS, MAX_TIMEOUT_SECONDS])
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = data[KEY_ENABLED]
	settings.url = data[KEY_URL]
	settings.timeout_seconds = float(timeout)
	return settings


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> UpdateSettings:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	return parse_json(FileAccess.get_file_as_string(path))


static func _rejected(reason: String) -> UpdateSettings:
	var settings: UpdateSettings = UpdateSettings.new()
	settings.enabled = false
	settings.error = reason
	return settings
