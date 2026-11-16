extends RefCounted

## Frame time statistics against the refresh-rate budget (PRF-1 to PRF-3, #164).


## Statistics at `hz` with the shipped budget file.
func _stats(hz: float) -> FrameStats:
	return FrameStats.load_budget(hz)


func _add_frames(stats: FrameStats, frame_seconds: float, times: int) -> void:
	for i: int in times:
		stats.add(frame_seconds)


func test_shipped_budget_is_prf_3() -> String:
	var stats: FrameStats = _stats(90.0)
	if stats.error != "":
		return stats.error
	if stats.dropped_factor != 1.5 or stats.max_dropped_fraction != 0.01:
		return "budget factor %s fraction %s" % [stats.dropped_factor, stats.max_dropped_fraction]
	return ""


func test_exact_frames_at_90_hz_drop_nothing_and_pass() -> String:
	var stats: FrameStats = _stats(90.0)
	_add_frames(stats, 1.0 / 90.0, 1000)
	if stats.count() != 1000 or stats.dropped() != 0 or stats.dropped_fraction() != 0.0:
		return "count %d dropped %d" % [stats.count(), stats.dropped()]
	if not is_equal_approx(snappedf(stats.budget_ms(), 0.1), 11.1) or not is_equal_approx(snappedf(stats.mean_ms(), 0.01), 11.11):
		return "budget %s mean %s" % [stats.budget_ms(), stats.mean_ms()]
	return stats.check(0.01)


func test_eleven_slow_frames_in_a_thousand_fail_and_name_the_fraction() -> String:
	var stats: FrameStats = _stats(90.0)
	_add_frames(stats, 1.0 / 90.0, 989)
	_add_frames(stats, 0.025, 11)
	if stats.dropped() != 11:
		return "dropped %d" % stats.dropped()
	var message: String = stats.check(0.01)
	if message == "":
		return "11 dropped frames of 1000 passed at 0.01"
	if not message.contains("1.1%") or not message.contains("1.0%"):
		return "message does not name 1.1%% measured and 1%% allowed: %s" % message
	if stats.check() != message:
		return "the budget file's default did not behave like 0.01"
	if not is_equal_approx(stats.max_ms(), 25.0):
		return "max %s" % stats.max_ms()
	return ""


func test_only_frames_over_the_threshold_are_dropped() -> String:
	var stats: FrameStats = _stats(90.0)
	stats.add(1.5 / 90.0 - 0.000001)
	stats.add(1.5 / 90.0 + 0.000001)
	return "" if stats.dropped() == 1 else "dropped %d" % stats.dropped()


func test_p99_of_a_known_list() -> String:
	var stats: FrameStats = _stats(90.0)
	# 1..100 ms added out of order: the nearest-rank p99 is 99 ms.
	for i: int in range(100, 0, -1):
		stats.add(i / 1000.0)
	if not is_equal_approx(stats.p99_ms(), 99.0):
		return "p99 of 1..100 ms is %s" % stats.p99_ms()
	var few: FrameStats = _stats(90.0)
	few.add(0.005)
	few.add(0.020)
	few.add(0.010)
	if not is_equal_approx(few.p99_ms(), 20.0):
		return "p99 of three frames is %s, not the max" % few.p99_ms()
	return ""


func test_no_frames_fails_with_a_clear_message() -> String:
	var stats: FrameStats = _stats(90.0)
	var message: String = stats.check(0.01)
	if not message.contains("no frame times"):
		return "empty list gave '%s'" % message
	if stats.mean_ms() != 0.0 or stats.p99_ms() != 0.0 or stats.max_ms() != 0.0:
		return "empty statistics are not zero"
	return ""


func test_72_and_120_hz_budgets() -> String:
	var at_72: float = snappedf(_stats(72.0).budget_ms(), 0.1)
	var at_120: float = snappedf(_stats(120.0).budget_ms(), 0.1)
	if not is_equal_approx(at_72, 13.9) or not is_equal_approx(at_120, 8.3):
		return "72 Hz %s ms, 120 Hz %s ms" % [at_72, at_120]
	return ""


func test_measurements_are_rounded_and_fit_a_report() -> String:
	var stats: FrameStats = _stats(90.0)
	_add_frames(stats, 1.0 / 90.0, 99)
	stats.add(0.0123456)
	var m: Dictionary = stats.to_measurements()
	for key: String in ["target_hz", "frame_count", "budget_ms", "dropped_threshold_ms",
			"mean_ms", "p99_ms", "max_ms", "dropped", "dropped_fraction"]:
		if not m.has(key):
			return "measurements lack %s" % key
	if not is_equal_approx(m["budget_ms"], 11.11) or not is_equal_approx(m["dropped_threshold_ms"], 16.67) \
			or not is_equal_approx(m["max_ms"], 12.35):
		return "not rounded to 0.01 ms: %s" % [m]
	if m["frame_count"] != 100 or m["dropped"] != 0:
		return "counts %s" % [m]
	var report: AcceptanceReport = AcceptanceReport.new("m1")
	if not report.add_step("frames", AcceptanceReport.RESULT_PASS, stats.check(), m):
		return "report refused the step"
	if report.steps[0]["measurements"] != m:
		return "report changed the measurements"
	return ""


func test_bad_budgets_are_rejected_with_the_key_named() -> String:
	var cases: Dictionary = {
		"{\"dropped_factor\": 1.0, \"max_dropped_fraction\": 0.01}": "dropped_factor",
		"{\"dropped_factor\": 1.5, \"max_dropped_fraction\": 1.5}": "max_dropped_fraction",
		"{\"dropped_factor\": 1.5, \"max_dropped_fraction\": -0.1}": "max_dropped_fraction",
		"{\"dropped_factor\": 1.5}": "missing key \"max_dropped_fraction\"",
		"{\"dropped_factor\": true, \"max_dropped_fraction\": 0.01}": "must be a number",
		"{\"dropped_factor\": 1.5, \"max_dropped_fraction\": 0.01, \"extra\": 1}": "unknown key \"extra\"",
		"[1.5, 0.01]": "JSON object",
		"{": "invalid JSON",
	}
	for text: String in cases:
		var stats: FrameStats = FrameStats.from_budget_json(90.0, text)
		if not stats.error.contains(cases[text]):
			return "%s gave error '%s'" % [text, stats.error]
		stats.add(1.0 / 90.0)
		if stats.check(0.01) == "":
			return "a rejected budget passed: %s" % text
	return ""


func test_bad_target_rate_and_missing_file_fail() -> String:
	var zero: FrameStats = FrameStats.load_budget(0.0)
	zero.add(0.01)
	if not zero.check().contains("target rate"):
		return "0 Hz gave '%s'" % zero.check()
	var missing: FrameStats = FrameStats.load_budget(90.0, "res://acceptance/no_such_budget.json")
	if not missing.error.contains("cannot open"):
		return "missing file gave '%s'" % missing.error
	var allowed: FrameStats = _stats(90.0)
	allowed.add(0.01)
	if not allowed.check(2.0).contains("must be 0..1"):
		return "an allowed fraction of 2 was accepted"
	return ""
