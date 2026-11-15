extends RefCounted

## The runner must not read a script error as a pass (issue #140, DEV-1, DEV-3).
## The broken examples live in `fixtures/runner/`, which the normal run skips,
## and go through `runner_core.gd`, the same per-file logic `run_tests.gd` uses.
## Their deliberate errors still print to the output; that is expected.

const RunnerCore := preload("res://tests/runner_core.gd")
const FIXTURES: String = "res://tests/fixtures/runner/"


static func _run(file: String) -> Dictionary:
	return RunnerCore.run_file(FIXTURES + file, file)


## Checks that `file` ran one test, counted it failed, and said "script error".
static func _expect_script_error(file: String, method_name: String) -> String:
	var result: Dictionary = _run(file)
	var lines: Array[String] = result["lines"]
	var expected: String = "FAIL %s::%s - script error: " % [file, method_name]
	if result["count"] != 1 or result["failures"] != 1:
		return "%s: %d tests, %d failed, expected 1 and 1" % [file, result["count"], result["failures"]]
	if lines.size() != 1 or not lines[0].begins_with(expected):
		return "%s: expected a line starting %q, got %s" % [file, expected, str(lines)]
	return ""


func test_a_method_call_on_null_fails() -> String:
	return _expect_script_error("calls_on_null.gd", "test_calls_a_method_on_null")


func test_an_index_past_the_end_fails() -> String:
	return _expect_script_error("indexes_past_end.gd", "test_indexes_past_the_end")


func test_an_error_in_a_helper_fails() -> String:
	return _expect_script_error("errors_in_helper.gd", "test_errors_in_a_helper")


func test_the_error_message_is_reported() -> String:
	var lines: Array[String] = _run("calls_on_null.gd")["lines"]
	if lines.is_empty() or not "set_name" in lines[0]:
		return "the failure does not name the error: %s" % str(lines)
	return ""


func test_a_file_that_does_not_parse_fails() -> String:
	var result: Dictionary = _run("does_not_parse.gd")
	var lines: Array[String] = result["lines"]
	if result["count"] != 0 or result["failures"] != 1:
		return "%d tests, %d failed, expected 0 and 1" % [result["count"], result["failures"]]
	if lines != ["FAIL does_not_parse.gd - could not load script"]:
		return "unexpected report %s" % str(lines)
	return ""


func test_correct_tests_pass_and_messages_fail() -> String:
	var result: Dictionary = _run("returns_results.gd")
	var lines: Array[String] = result["lines"]
	lines.sort()
	var expected: Array[String] = [
		"FAIL returns_results.gd::test_fails_by_message - expected message",
		"PASS returns_results.gd::test_passes",
		"PASS returns_results.gd::test_passes_with_a_warning",
	]
	if result["count"] != 3 or result["failures"] != 1 or lines != expected:
		return "expected %s, got %s" % [str(expected), str(lines)]
	return ""


func test_the_error_logger_is_removed_after_a_file() -> String:
	_run("calls_on_null.gd")
	# This test itself runs inside the outer capture, so one level stays open.
	var logger: RunnerCore.ScriptErrorLogger = RunnerCore._logger
	if logger == null or logger.depth() != 1:
		return "the capture did not unwind to the outer run"
	return ""
