extends RefCounted

## The update check's URL, timeout and on/off flag are a data file (#646,
## ARC-4); a missing or bad file turns the check off rather than guessing.

const GOOD: String = "{\"enabled\": true, \"url\": \"https://a.example/x\", \"timeout_seconds\": 5}"


func test_the_shipped_file_asks_github_for_main_latest() -> String:
	var settings: UpdateSettings = UpdateSettings.load_file()
	if settings.error != "":
		return "the shipped file was rejected: %s" % settings.error
	if not settings.enabled:
		return "the shipped file turns the check off"
	if settings.url != "https://api.github.com/repos/noless-zz/meltdown/releases/tags/main-latest":
		return "the shipped URL is %s" % settings.url
	if settings.timeout_seconds < UpdateSettings.MIN_TIMEOUT_SECONDS \
			or settings.timeout_seconds > UpdateSettings.MAX_TIMEOUT_SECONDS:
		return "the shipped timeout is %s" % settings.timeout_seconds
	return ""


func test_a_good_text_is_read() -> String:
	var settings: UpdateSettings = UpdateSettings.parse_json(GOOD)
	if settings.error != "" or not settings.enabled:
		return "rejected: %s" % settings.error
	if settings.url != "https://a.example/x" or settings.timeout_seconds != 5.0:
		return "read %s %s" % [settings.url, settings.timeout_seconds]
	return ""


func test_the_flag_can_turn_it_off() -> String:
	var settings: UpdateSettings = UpdateSettings.parse_json(GOOD.replace("true", "false"))
	if settings.error != "":
		return "rejected: %s" % settings.error
	return "" if not settings.enabled else "enabled false read as on"


func test_bad_files_turn_the_check_off() -> String:
	var bad: Dictionary = {
		"not json": "{",
		"array": "[]",
		"unknown key": GOOD.replace("}", ", \"retries\": 3}"),
		"missing key": "{\"enabled\": true, \"url\": \"https://a.example/x\"}",
		"string flag": GOOD.replace("true", "\"yes\""),
		"http url": GOOD.replace("https://", "http://"),
		"bool timeout": GOOD.replace("5}", "true}"),
		"short timeout": GOOD.replace("5}", "0.5}"),
		"long timeout": GOOD.replace("5}", "61}"),
	}
	for label: String in bad:
		var settings: UpdateSettings = UpdateSettings.parse_json(bad[label])
		if settings.error == "" or settings.enabled:
			return "%s was accepted" % label
	var missing: UpdateSettings = UpdateSettings.load_file("res://tests/fixtures/no_such_update_check.json")
	if missing.error == "" or missing.enabled:
		return "a missing file left the check on"
	return ""
