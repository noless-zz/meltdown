class_name UpdateCheck
extends RefCounted

## Decides from the `main-latest` release, as the GitHub API returns it, whether
## a newer build than the running one exists and where its APK and checksum are
## (DEV-8, PLT-1). Pure logic: the request and the panel are separate steps, so
## this can be tested without a network.

const STATUS_UPDATE_AVAILABLE: String = "update_available"
const STATUS_UP_TO_DATE: String = "up_to_date"
const STATUS_UNKNOWN: String = "unknown"
const STATUS_ERROR: String = "error"

const APK_ASSET: String = "meltdown-quest-debug.apk"
const SHA256_ASSET: String = "meltdown-quest-debug.apk.sha256"
const SHA256_LENGTH: int = 64

## `tools/release_notes.sh` writes "..., commit <sha>. ..." and
## "Built: YYYY-MM-DD HH:MM UTC (...)".
const COMMIT_PATTERN: String = "\\bcommit ([0-9a-fA-F]{40})\\b"
const BUILT_PATTERN: String = "(?m)^Built: (\\d{4}-\\d{2}-\\d{2}) (\\d{2}:\\d{2}) UTC"


## Returns `status`, `reason`, `commit` (or "unknown"), `built_unix` (0 when
## unknown), `apk_url` and `sha256_url` (empty when missing).
static func evaluate(release_json: String, running: BuildInfo) -> Dictionary:
	var result: Dictionary = {
		"status": STATUS_ERROR,
		"reason": "",
		"commit": BuildInfo.UNKNOWN,
		"built_unix": 0,
		"apk_url": "",
		"sha256_url": "",
	}
	# JSON.new().parse rather than JSON.parse_string: a bad response is an
	# expected case here and should not print an engine error.
	var json: JSON = JSON.new()
	var parsed: Variant = json.data if json.parse(release_json) == OK else null
	if not parsed is Dictionary:
		result["reason"] = "the release is not a JSON object"
		return result
	var release: Dictionary = parsed
	var body: String = _string_field(release, "body")
	result["commit"] = _release_commit(body, _string_field(release, "target_commitish"))
	result["built_unix"] = _release_built_unix(body)
	var assets: Variant = release.get("assets", null)
	if not assets is Array:
		result["reason"] = "the release has no asset list"
		return result
	result["apk_url"] = _asset_url(assets, APK_ASSET)
	result["sha256_url"] = _asset_url(assets, SHA256_ASSET)
	if result["apk_url"] == "":
		result["reason"] = "the release has no %s" % APK_ASSET
		return result
	if result["sha256_url"] == "":
		result["reason"] = "the release has no %s" % SHA256_ASSET
		return result
	# An editor run has no commit, so it cannot know whether it is behind.
	if running == null or running.commit == BuildInfo.UNKNOWN:
		result["status"] = STATUS_UNKNOWN
		result["reason"] = "the running build's commit is unknown"
		return result
	if result["commit"] == BuildInfo.UNKNOWN:
		result["status"] = STATUS_UNKNOWN
		result["reason"] = "the release does not name its commit"
		return result
	if result["commit"] == running.commit:
		result["status"] = STATUS_UP_TO_DATE
	else:
		result["status"] = STATUS_UPDATE_AVAILABLE
	return result


## The digest from a `sha256sum` line ("<digest>  <file>"), lowercase, or ""
## when the text holds none.
static func parse_sha256(text: String) -> String:
	for line: String in text.split("\n", false):
		var fields: PackedStringArray = line.strip_edges().split(" ", false)
		if fields.is_empty():
			continue
		# sha256sum prefixes the line with a backslash when it escapes the file name.
		var digest: String = fields[0].trim_prefix("\\").to_lower()
		return digest if _is_hex(digest, SHA256_LENGTH) else ""
	return ""


static func matches_sha256(bytes: PackedByteArray, digest: String) -> bool:
	if not _is_hex(digest.to_lower(), SHA256_LENGTH):
		return false
	var context: HashingContext = HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return false
	if not bytes.is_empty() and context.update(bytes) != OK:
		return false
	return context.finish().hex_encode() == digest.to_lower()


static func _string_field(release: Dictionary, key: String) -> String:
	var value: Variant = release.get(key, "")
	return value if value is String else ""


## The body is preferred: on the real release `target_commitish` has named a
## different commit from the one the body says the build was made from.
static func _release_commit(body: String, target_commitish: String) -> String:
	var found: RegExMatch = RegEx.create_from_string(COMMIT_PATTERN).search(body)
	if found != null:
		return found.get_string(1).to_lower()
	if BuildInfo.is_full_commit(target_commitish):
		return target_commitish.to_lower()
	return BuildInfo.UNKNOWN


static func _release_built_unix(body: String) -> int:
	var found: RegExMatch = RegEx.create_from_string(BUILT_PATTERN).search(body)
	if found == null:
		return 0
	var stamp: String = "%sT%s:00" % [found.get_string(1), found.get_string(2)]
	# A datetime string without a zone is read as UTC, which the line states.
	var unix: int = Time.get_unix_time_from_datetime_string(stamp)
	return unix if unix > 0 else 0


static func _asset_url(assets: Array, asset_name: String) -> String:
	for asset: Variant in assets:
		if not asset is Dictionary:
			continue
		var entry: Dictionary = asset
		if entry.get("name", "") != asset_name:
			continue
		var url: Variant = entry.get("browser_download_url", "")
		if url is String and String(url).begins_with("https://"):
			return url
	return ""


static func _is_hex(text: String, length: int) -> bool:
	if text.length() != length:
		return false
	for c: String in text:
		if not BuildInfo.HEX_DIGITS.contains(c):
			return false
	return true
