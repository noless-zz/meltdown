extends RefCounted

## Acceptance suite files and the report they produce (DEV-6, #163).

const M1_PATH: String = "res://acceptance/suites/m1.json"


## A valid one-step suite with `step_json` as its only step.
func _suite_text(step_json: String) -> String:
	return "{\"name\": \"x\", \"steps\": [%s]}" % step_json


## "" if `text` is rejected with a message containing `field`.
func _expect_rejected(text: String, field: String) -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(text)
	if suite.error == "":
		return "accepted %s" % text
	if not suite.error.contains(field):
		return "error '%s' does not name %s" % [suite.error, field]
	if not suite.steps.is_empty():
		return "a rejected suite kept %d steps" % suite.steps.size()
	return ""


func test_every_shipped_suite_loads() -> String:
	for suite_name: String in ["m0", "m1", "m2"]:
		var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named(suite_name)
		if found.size() != 1:
			return "%s gave %d suites" % [suite_name, found.size()]
		if found[0].error != "":
			return found[0].error
		if found[0].name != suite_name or found[0].steps.is_empty():
			return "%s loaded as '%s' with %d steps" % [suite_name, found[0].name, found[0].steps.size()]
	var m0: AcceptanceStep = AcceptanceSuite.load_named("m0")[0].steps[0]
	if m0.checks != [AcceptanceStep.CHECK_XR_SESSION]:
		return "m0 checks %s" % [m0.checks]
	return ""


## The replay copied for export must still end with the hash the m1 suite
## expects; otherwise the suite would fail on every device for a stale file.
func test_m1_replay_flies_to_its_expected_hash() -> String:
	var step: AcceptanceStep = AcceptanceSuite.load_file(M1_PATH).steps[0]
	if not step.has_check(AcceptanceStep.CHECK_FINAL_HASH):
		return "m1 does not check the final hash"
	if not step.replay_path.begins_with("res://acceptance/"):
		return "m1 flies %s, which is not exported" % step.replay_path
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "":
		return replay.error
	var actual: int = replay.run().state_hash()
	if actual != step.expected_hash or actual != replay.expected_hash:
		return "flew to %d; suite expects %d, replay %d" % [actual, step.expected_hash, replay.expected_hash]
	return ""


func test_all_returns_every_suite_in_name_order() -> String:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named(AcceptanceSuite.ALL)
	var names: Array[String] = []
	for suite: AcceptanceSuite in found:
		if suite.error != "":
			return suite.error
		names.append(suite.name)
	if names != ["m0", "m1", "m2", "m3"]:
		return "all gave %s" % [names]
	return ""


func test_an_unknown_or_unsafe_suite_name_is_an_error() -> String:
	for suite_name: String in ["m9", "../tests/x", ""]:
		var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named(suite_name)
		if found.size() != 1 or found[0].error == "":
			return "'%s' did not give one failed suite" % suite_name
	return ""


func test_a_bad_check_name_is_rejected_with_the_field() -> String:
	return _expect_rejected(_suite_text("{\"id\": \"a\", \"checks\": [\"no_script_errors\", \"xr_sesion\"]}"),
		"steps[0].checks[1]")


func test_a_missing_id_is_rejected_with_the_field() -> String:
	return _expect_rejected(_suite_text("{\"checks\": [\"xr_session\"]}"), "steps[0].id")


func test_a_preset_of_five_is_rejected_with_the_field() -> String:
	return _expect_rejected(_suite_text("{\"id\": \"a\", \"preset\": 5, \"checks\": [\"xr_session\"]}"),
		"steps[0].preset")


func test_other_bad_values_are_rejected_with_the_field() -> String:
	var cases: Dictionary[String, String] = {
		"{\"name\": \"x\", \"steps\": [], \"extra\": 1}": "extra",
		"{\"name\": \"x\", \"steps\": []}": "steps",
		"{\"steps\": [{\"id\": \"a\", \"checks\": [\"xr_session\"]}]}": "name",
		_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"], \"replays\": \"r\"}"): "steps[0].replays",
		_suite_text("{\"id\": \"a\", \"checks\": []}"): "steps[0].checks",
		_suite_text("{\"id\": \"a\", \"preset\": 1.5, \"checks\": [\"xr_session\"]}"): "steps[0].preset",
		_suite_text("{\"id\": \"a\", \"preset\": true, \"checks\": [\"xr_session\"]}"): "steps[0].preset",
		_suite_text("{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"final_hash\"]}"): "steps[0].expected_hash",
		_suite_text("{\"id\": \"a\", \"checks\": [\"final_hash\"], \"expected_hash\": 3}"): "steps[0].replay",
		_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"], \"expected_hash\": 3}"): "steps[0].expected_hash",
		_suite_text("{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"final_hash\"], \"expected_hash\": -1}"):
			"steps[0].expected_hash",
		_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"]}, {\"id\": \"a\", \"checks\": [\"xr_session\"]}"):
			"steps[1].id",
	}
	for text: String in cases:
		var problem: String = _expect_rejected(text, cases[text])
		if problem != "":
			return problem
	return ""


func test_a_full_step_keeps_every_value() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(
		"{\"id\": \"fly\", \"replay\": \"res://r.replay\", \"preset\": 4, "
		+ "\"checks\": [\"final_hash\", \"no_script_errors\"], \"expected_hash\": 4294967295}"))
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = suite.steps[0]
	if step.id != "fly" or step.replay_path != "res://r.replay" or step.preset != 4:
		return "read id %s, replay %s, preset %d" % [step.id, step.replay_path, step.preset]
	if step.checks != [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		return "checks %s" % [step.checks]
	if step.expected_hash != 4294967295:
		return "hash %d" % step.expected_hash
	return ""


func test_a_report_with_one_failed_step_has_not_passed() -> String:
	var report: AcceptanceReport = AcceptanceReport.new("m1", "abc123", "Quest 3")
	report.add_step("one", AcceptanceReport.RESULT_PASS)
	if not report.passed():
		return "a report with one passing step has not passed"
	report.add_step("two", AcceptanceReport.RESULT_FAIL, "hash differs")
	report.add_step("three", AcceptanceReport.RESULT_PASS)
	if report.passed():
		return "a report with a failed step has passed"
	return ""


func test_a_report_in_which_no_step_ran_has_not_passed() -> String:
	var report: AcceptanceReport = AcceptanceReport.new("m0")
	if report.passed():
		return "an empty report has passed"
	report.add_step("one", AcceptanceReport.RESULT_SKIPPED, "no headset")
	if report.passed():
		return "a report of skipped steps has passed"
	if report.add_step("two", "ok"):
		return "an unknown result was recorded"
	return ""


func test_log_lines_hold_the_markers_and_parse_back_as_json() -> String:
	var report: AcceptanceReport = AcceptanceReport.new("m1", "abc123", "Quest 3")
	report.add_step("fly", AcceptanceReport.RESULT_FAIL, "hash differs", {"ticks": 600, "hash": 12})
	var lines: PackedStringArray = report.to_log_lines()
	if lines.size() < 3:
		return "only %d lines" % lines.size()
	if lines[0] != AcceptanceReport.LOG_BEGIN or lines[lines.size() - 1] != AcceptanceReport.LOG_END:
		return "markers missing: %s" % [lines]
	var body: String = "\n".join(lines.slice(1, lines.size() - 1))
	var parsed: Variant = JSON.parse_string(body)
	if typeof(parsed) != TYPE_DICTIONARY:
		return "the lines between the markers are not a JSON object: %s" % body
	var data: Dictionary = parsed
	if data["suite"] != "m1" or data["build_commit"] != "abc123" or data["device"] != "Quest 3":
		return "header read back as %s" % [data]
	if data["passed"] != false or (data["steps"] as Array).size() != 1:
		return "result read back as %s" % [data]
	var step: Dictionary = data["steps"][0]
	if step["id"] != "fly" or step["result"] != "fail" or step["message"] != "hash differs":
		return "step read back as %s" % [step]
	if int(step["measurements"]["ticks"]) != 600:
		return "measurements read back as %s" % [step["measurements"]]
	return ""


func test_json_key_order_does_not_depend_on_insertion_order() -> String:
	var first: AcceptanceReport = AcceptanceReport.new("m1", "c", "d")
	first.add_step("fly", AcceptanceReport.RESULT_PASS, "", {"a": 1, "b": 2})
	var second: AcceptanceReport = AcceptanceReport.new("m1", "c", "d")
	second.add_step("fly", AcceptanceReport.RESULT_PASS, "", {"b": 2, "a": 1})
	if first.to_json() != second.to_json():
		return "reports differ:\n%s\n%s" % [first.to_json(), second.to_json()]
	return ""


func test_required_flag_is_read_and_checked() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
		_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"], \"required\": true}"))
	if suite.error != "" or not suite.steps[0].required:
		return "required: true was not read: %s" % suite.error
	suite = AcceptanceSuite.parse_json(_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"]}"))
	if suite.error != "" or suite.steps[0].required:
		return "a step without the key is required"
	return _expect_rejected(_suite_text("{\"id\": \"a\", \"checks\": [\"xr_session\"], \"required\": 1}"),
		"steps[0].required")
