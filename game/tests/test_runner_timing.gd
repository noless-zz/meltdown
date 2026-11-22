extends RefCounted

## The runner times each file and lists the slowest, so the costly test files
## can be found and cut (issue #1138, DEV-3).

const RunnerCore := preload("res://tests/runner_core.gd")
const FIXTURE: String = "res://tests/fixtures/runner/takes_time.gd"


func test_a_file_result_carries_its_time() -> String:
	var result: Dictionary = RunnerCore.run_file(FIXTURE, "takes_time.gd")
	if not result.has("ms"):
		return "no ms in %s" % str(result)
	if typeof(result["ms"]) != TYPE_INT or result["ms"] < 0:
		return "ms is %s, expected an int of at least zero" % str(result["ms"])
	# The fixture waits 20 ms; a timer that missed the test calls would read less.
	if result["ms"] < 15:
		return "ms is %d, expected at least the fixture's 20 ms wait" % result["ms"]
	if result["count"] != 1 or result["failures"] != 0:
		return "timing changed the outcome: %s" % str(result)
	return ""


func test_a_file_that_does_not_load_still_has_a_time() -> String:
	var result: Dictionary = RunnerCore.run_file("res://tests/fixtures/runner/does_not_parse.gd", "x")
	if not result.has("ms") or result["ms"] < 0:
		return "no time for a file that failed to load: %s" % str(result)
	return ""


func test_the_slow_list_is_longest_first() -> String:
	var times: Dictionary = {"test_a.gd": 5, "test_b.gd": 900, "test_c.gd": 40, "test_d.gd": 900}
	var lines: Array[String] = RunnerCore.slow_lines(times, 15)
	var expected: Array[String] = [
		"SLOW 900 test_b.gd", "SLOW 900 test_d.gd", "SLOW 40 test_c.gd", "SLOW 5 test_a.gd",
	]
	if lines != expected:
		return "got %s, expected %s" % [str(lines), str(expected)]
	return ""


func test_the_slow_list_stops_at_the_limit() -> String:
	var times: Dictionary = {}
	for i: int in 20:
		times["test_%02d.gd" % i] = i
	var lines: Array[String] = RunnerCore.slow_lines(times, 15)
	if lines.size() != 15:
		return "%d lines, expected 15" % lines.size()
	if lines[0] != "SLOW 19 test_19.gd" or lines[14] != "SLOW 5 test_05.gd":
		return "wrong first or last line: %s" % str(lines)
	return ""


func test_an_empty_run_has_no_slow_lines() -> String:
	if not RunnerCore.slow_lines({}, 15).is_empty():
		return "slow lines for no files"
	return ""
