extends RefCounted

## The game can tell from the `main-latest` release whether a newer build
## exists and where its APK and checksum are (DEV-8, PLT-1). The fixture is a
## trimmed copy of a real `releases/tags/main-latest` response.

const FIXTURE: String = "res://tests/fixtures/main_latest_release.json"
## The commit the fixture's body names; its target_commitish is a different one.
const RELEASE_COMMIT: String = "e1b0a77b6477cc25b84e96bf7e7aefdcc6c27ee5"
const TARGET_COMMITISH: String = "be8ad52da332b94f876b7e22f21c0d5829908779"
const OTHER_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
## "Built: 2026-11-15 19:07 UTC".
const RELEASE_BUILT_UNIX: int = 1794769620
const DOWNLOAD: String = "https://github.com/noless-zz/meltdown/releases/download/main-latest/"
## sha256 of the three bytes "abc".
const ABC_SHA256: String = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"


static func _fixture() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))


static func _running(commit: String) -> BuildInfo:
	var info: BuildInfo = BuildInfo.new()
	info.commit = commit
	return info


static func _without_asset(asset_name: String) -> String:
	var release: Dictionary = _fixture()
	var kept: Array = []
	for asset: Dictionary in release["assets"]:
		if asset["name"] != asset_name:
			kept.append(asset)
	release["assets"] = kept
	return JSON.stringify(release)


static func _expect(result: Dictionary, status: String) -> String:
	if result["status"] != status:
		return "status is '%s' (%s), expected '%s'" % [result["status"], result["reason"], status]
	return ""


func test_the_fixture_is_a_release_with_the_quest_assets() -> String:
	var release: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not release is Dictionary:
		return "fixture did not parse"
	if release["tag_name"] != "main-latest":
		return "fixture tag is '%s'" % release["tag_name"]
	return ""


func test_same_commit_is_up_to_date() -> String:
	var json: String = FileAccess.get_file_as_string(FIXTURE)
	var result: Dictionary = UpdateCheck.evaluate(json, _running(RELEASE_COMMIT))
	var message: String = _expect(result, UpdateCheck.STATUS_UP_TO_DATE)
	if message != "":
		return message
	if result["commit"] != RELEASE_COMMIT:
		return "release commit is '%s'" % result["commit"]
	return ""


func test_a_different_commit_has_an_update_with_both_urls() -> String:
	var json: String = FileAccess.get_file_as_string(FIXTURE)
	var result: Dictionary = UpdateCheck.evaluate(json, _running(OTHER_COMMIT))
	var message: String = _expect(result, UpdateCheck.STATUS_UPDATE_AVAILABLE)
	if message != "":
		return message
	if result["apk_url"] != DOWNLOAD + "meltdown-quest-debug.apk":
		return "apk_url is '%s'" % result["apk_url"]
	if result["sha256_url"] != DOWNLOAD + "meltdown-quest-debug.apk.sha256":
		return "sha256_url is '%s'" % result["sha256_url"]
	if result["built_unix"] != RELEASE_BUILT_UNIX:
		return "built_unix is %d, expected %d" % [result["built_unix"], RELEASE_BUILT_UNIX]
	return ""


func test_the_body_commit_wins_over_target_commitish() -> String:
	var json: String = FileAccess.get_file_as_string(FIXTURE)
	var result: Dictionary = UpdateCheck.evaluate(json, _running(TARGET_COMMITISH))
	return _expect(result, UpdateCheck.STATUS_UPDATE_AVAILABLE)


func test_target_commitish_is_used_when_the_body_names_no_commit() -> String:
	var release: Dictionary = _fixture()
	release["body"] = "Built: 2026-11-15 19:07 UTC"
	var result: Dictionary = UpdateCheck.evaluate(JSON.stringify(release),
			_running(TARGET_COMMITISH))
	var message: String = _expect(result, UpdateCheck.STATUS_UP_TO_DATE)
	if message != "":
		return message
	if result["built_unix"] != RELEASE_BUILT_UNIX:
		return "built_unix is %d" % result["built_unix"]
	return ""


func test_no_commit_anywhere_is_unknown() -> String:
	var release: Dictionary = _fixture()
	release["body"] = "Some notes"
	release["target_commitish"] = "main"
	var result: Dictionary = UpdateCheck.evaluate(JSON.stringify(release),
			_running(OTHER_COMMIT))
	var message: String = _expect(result, UpdateCheck.STATUS_UNKNOWN)
	if message != "":
		return message
	if result["built_unix"] != 0:
		return "built_unix is %d without a Built line" % result["built_unix"]
	return ""


func test_an_unknown_running_commit_is_never_an_update() -> String:
	var json: String = FileAccess.get_file_as_string(FIXTURE)
	var editor_run: BuildInfo = BuildInfo.new()
	var message: String = _expect(UpdateCheck.evaluate(json, editor_run),
			UpdateCheck.STATUS_UNKNOWN)
	if message != "":
		return message
	return _expect(UpdateCheck.evaluate(json, null), UpdateCheck.STATUS_UNKNOWN)


func test_a_missing_apk_is_an_error() -> String:
	var result: Dictionary = UpdateCheck.evaluate(
			_without_asset(UpdateCheck.APK_ASSET), _running(OTHER_COMMIT))
	var message: String = _expect(result, UpdateCheck.STATUS_ERROR)
	if message != "":
		return message
	if not String(result["reason"]).contains(UpdateCheck.APK_ASSET):
		return "reason '%s' does not name the APK" % result["reason"]
	return ""


func test_a_missing_checksum_is_an_error() -> String:
	var result: Dictionary = UpdateCheck.evaluate(
			_without_asset(UpdateCheck.SHA256_ASSET), _running(OTHER_COMMIT))
	var message: String = _expect(result, UpdateCheck.STATUS_ERROR)
	if message != "":
		return message
	if not String(result["reason"]).contains(UpdateCheck.SHA256_ASSET):
		return "reason '%s' does not name the checksum" % result["reason"]
	return ""


func test_malformed_json_is_an_error() -> String:
	for text: String in ["", "{\"assets\": [", "[]", "\"main-latest\"", "{\"body\": \"x\"}"]:
		var result: Dictionary = UpdateCheck.evaluate(text, _running(OTHER_COMMIT))
		if result["status"] != UpdateCheck.STATUS_ERROR:
			return "'%s' gave '%s'" % [text, result["status"]]
		if String(result["reason"]) == "":
			return "'%s' gave no reason" % text
	return ""


func test_parse_sha256_reads_a_sha256sum_line() -> String:
	var line: String = ABC_SHA256.to_upper() + "  meltdown-quest-debug.apk\n"
	if UpdateCheck.parse_sha256(line) != ABC_SHA256:
		return "parsed '%s'" % UpdateCheck.parse_sha256(line)
	if UpdateCheck.parse_sha256("\n" + ABC_SHA256 + " *file.apk") != ABC_SHA256:
		return "binary-mode line did not parse"
	for bad: String in ["", "not a digest  file", ABC_SHA256.substr(1) + "  file"]:
		if UpdateCheck.parse_sha256(bad) != "":
			return "'%s' parsed as a digest" % bad
	return ""


func test_matches_sha256_accepts_the_right_digest_only() -> String:
	var bytes: PackedByteArray = "abc".to_utf8_buffer()
	if not UpdateCheck.matches_sha256(bytes, ABC_SHA256):
		return "the right digest did not match"
	if not UpdateCheck.matches_sha256(bytes, ABC_SHA256.to_upper()):
		return "an uppercase digest did not match"
	if UpdateCheck.matches_sha256("abd".to_utf8_buffer(), ABC_SHA256):
		return "different bytes matched"
	if UpdateCheck.matches_sha256(bytes, ""):
		return "an empty digest matched"
	return ""
