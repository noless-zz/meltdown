extends RefCounted

## Every build knows its commit and build time (DEV-8, ARC-6), and a missing or
## broken build file reads as unknown instead of stopping the game.

const VALID: String = "res://tests/fixtures/build_info_valid.tres"
const MALFORMED: String = "res://tests/fixtures/build_info_malformed.tres"
const MISSING: String = "res://tests/fixtures/no_such_build_info.tres"
const FIXTURE_COMMIT: String = "0123456789abcdef0123456789abcdef01234567"
## 2026-01-15 10:00 UTC, which is 12:00 in Israel: a local-time format would show it.
const FIXTURE_TIME: int = 1768471200


static func _expect_unknown(info: BuildInfo, label: String) -> String:
	if info == null:
		return "%s: load_from returned null" % label
	if info.commit != BuildInfo.UNKNOWN:
		return "%s: commit is '%s', expected unknown" % [label, info.commit]
	if info.built_unix != 0:
		return "%s: built_unix is %d, expected 0" % [label, info.built_unix]
	if info.short_commit() != BuildInfo.UNKNOWN:
		return "%s: short commit is '%s'" % [label, info.short_commit()]
	return ""


func test_the_generated_file_loads_its_commit_and_time() -> String:
	var info: BuildInfo = BuildInfo.load_from(VALID)
	if info.commit != FIXTURE_COMMIT:
		return "commit is '%s'" % info.commit
	if info.built_unix != FIXTURE_TIME:
		return "built_unix is %d" % info.built_unix
	if info.short_commit() != "0123456":
		return "short commit is '%s'" % info.short_commit()
	return ""


func test_describe_formats_in_utc() -> String:
	var got: String = BuildInfo.load_from(VALID).describe()
	var want: String = "0123456, built 2026-01-15 10:00 UTC"
	if got != want:
		return "describe() gave '%s', expected '%s'" % [got, want]
	return ""


func test_a_missing_file_is_unknown() -> String:
	var message: String = _expect_unknown(BuildInfo.load_from(MISSING), "missing file")
	if message != "":
		return message
	var got: String = BuildInfo.load_from(MISSING).describe()
	if got != "unknown, build time unknown":
		return "describe() of a missing file gave '%s'" % got
	return ""


func test_malformed_values_are_unknown() -> String:
	return _expect_unknown(BuildInfo.load_from(MALFORMED), "malformed file")


func test_an_editor_run_without_a_build_file_does_not_fail() -> String:
	var info: BuildInfo = BuildInfo.load_from(BuildInfo.DEFAULT_PATH)
	if info == null:
		return "load_from the default path returned null"
	return ""


func test_only_forty_hex_characters_are_a_commit() -> String:
	var cases: Dictionary[String, bool] = {
		FIXTURE_COMMIT: true,
		FIXTURE_COMMIT.to_upper(): true,
		FIXTURE_COMMIT.substr(0, 39): false,
		FIXTURE_COMMIT + "0": false,
		"g123456789abcdef0123456789abcdef01234567": false,
		"-123456789abcdef0123456789abcdef01234567": false,
		"": false,
	}
	for text: String in cases:
		if BuildInfo.is_full_commit(text) != cases[text]:
			return "is_full_commit('%s') should be %s" % [text, cases[text]]
	return ""
