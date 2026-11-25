extends RefCounted

## Draw calls, triangles and memory against their budgets (#1289, PRF-4 to
## PRF-6): the 95th percentile on fed samples, over and under budget, metrics
## that were not read reported as skipped, the budget file checked, and the
## frame_budget check carrying the numbers and failing on them.

const FRAME_90: float = 1.0 / 90.0


## 100 frames: `high` of them at the high values, the rest at the low ones.
func _stats(high: int, low_values: Array[float], high_values: Array[float]) -> RenderStats:
	var stats: RenderStats = RenderStats.new()
	for index: int in 100:
		var values: Array[float] = high_values if index < high else low_values
		stats.add(values[0], values[1], values[2])
	return stats


func _budget() -> RenderBudget:
	return RenderBudget.parse_json("{\"draw_calls\": 150, \"triangles\": 600000, \"memory_mb\": 3584}")


func test_percentile_is_nearest_rank() -> String:
	var stats: RenderStats = RenderStats.new()
	for value: int in range(1, 21):  # 1..20, fed out of order.
		stats.add(float(21 - value), float(value * 1000), 100.0)
	if stats.percentile("draw_calls", 0.95) != 19.0 or stats.percentile("draw_calls", 0.5) != 10.0:
		return "draw call percentiles: p95 %s, p50 %s" % [stats.percentile("draw_calls", 0.95),
			stats.percentile("draw_calls", 0.5)]
	if stats.percentile("triangles", 1.0) != 20000.0 or stats.max_value("triangles") != 20000.0:
		return "triangle max wrong"
	var one: RenderStats = RenderStats.new()
	one.add(7.0, 7.0, 7.0)
	if one.percentile("memory_mb", 0.95) != 7.0 or RenderStats.new().percentile("memory_mb", 0.95) != 0.0:
		return "one sample or none"
	return ""


func test_under_budget_passes_and_reports_every_value() -> String:
	# 5 frames over 150 draw calls stay above the 95th percentile.
	var stats: RenderStats = _stats(5, [120.0, 400000.0, 2000.0], [200.0, 700000.0, 3000.0])
	var measurements: Dictionary = {}
	var outcome: Array = stats.judge(_budget(), measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS:
		return "under budget: %s" % [outcome]
	if measurements["draw_calls_p95"] != 120.0 or measurements["draw_calls_max"] != 200.0 \
			or measurements["triangles_p95"] != 400000.0 or measurements["memory_mb_p95"] != 2000.0:
		return "values wrong: %s" % measurements
	for metric: String in RenderBudget.METRICS:
		if measurements["%s_result" % metric] != AcceptanceReport.RESULT_PASS \
				or measurements["%s_samples" % metric] != 100 or not str(outcome[1]).contains(metric):
			return "%s not reported: %s / %s" % [metric, measurements, outcome[1]]
	return ""


func test_p95_over_budget_fails_naming_the_metric() -> String:
	# 6 frames over budget push the 95th percentile over.
	var stats: RenderStats = _stats(6, [120.0, 400000.0, 2000.0], [120.0, 650000.0, 2000.0])
	var measurements: Dictionary = {}
	var outcome: Array = stats.judge(_budget(), measurements)
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not str(outcome[1]).begins_with("over budget: triangles;"):
		return "triangles over: %s" % [outcome]
	if measurements["triangles_p95"] != 650000.0 or measurements["draw_calls_result"] != AcceptanceReport.RESULT_PASS:
		return "values not reported on failure: %s" % measurements
	var memory: Array = _stats(10, [100.0, 1000.0, 3000.0], [100.0, 1000.0, 3700.0]).judge(_budget(), {})
	if memory[0] != AcceptanceReport.RESULT_FAIL or not str(memory[1]).contains("memory_mb p95 3700"):
		return "memory over: %s" % [memory]
	return ""


func test_missing_data_is_skipped_not_passed() -> String:
	var stats: RenderStats = RenderStats.new()
	for index: int in 50:
		stats.add(100.0, RenderStats.NOT_READ, RenderStats.NOT_READ)
	var measurements: Dictionary = {}
	var outcome: Array = stats.judge(_budget(), measurements)
	if outcome[0] != AcceptanceReport.RESULT_PASS or measurements["triangles_result"] != AcceptanceReport.RESULT_SKIPPED \
			or measurements["memory_mb_result"] != AcceptanceReport.RESULT_SKIPPED \
			or not str(outcome[1]).contains("memory_mb not read (skipped)"):
		return "partly read: %s %s" % [outcome, measurements]
	var none: Array = RenderStats.new().judge(_budget(), {})
	if none[0] != AcceptanceReport.RESULT_SKIPPED:
		return "nothing read must be skipped: %s" % [none]
	return ""


func test_budget_file_is_checked() -> String:
	var shipped: RenderBudget = RenderBudget.load_file()
	if shipped.error != "" or shipped.limits["draw_calls"] != 150.0 or shipped.limits["triangles"] != 600000.0 \
			or shipped.limits["memory_mb"] != 3584.0:
		return "shipped budget: %s %s" % [shipped.error, shipped.limits]
	var cases: Dictionary = {
		"[]": "top level",
		"{\"draw_calls\": 150, \"triangles\": 600000}": "missing key \"memory_mb\"",
		"{\"draw_calls\": 150, \"triangles\": 600000, \"memory_mb\": 3584, \"drawcalls\": 1}": "unknown key",
		"{\"draw_calls\": true, \"triangles\": 600000, \"memory_mb\": 3584}": "\"draw_calls\" must be a number",
		"{\"draw_calls\": 150, \"triangles\": 0, \"memory_mb\": 3584}": "\"triangles\" must be a number above 0",
	}
	for text: String in cases:
		var budget: RenderBudget = RenderBudget.parse_json(text)
		if not budget.error.contains(cases[text]):
			return "%s: got \"%s\"" % [text, budget.error]
		if _stats(0, [1.0, 1.0, 1.0], [1.0, 1.0, 1.0]).judge(budget, {})[0] != AcceptanceReport.RESULT_FAIL:
			return "a broken budget must fail: %s" % text
	if RenderBudget.load_file("res://no_such_budget.json").error == "":
		return "a missing file must be an error"
	return ""


func test_frame_budget_check_reports_and_fails_on_render_numbers() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.id = "stress_scene"
	step.checks.append(AcceptanceStep.CHECK_FRAME_BUDGET)
	step.max_over_budget_share = 0.01
	step.budget_slack_ms = 1.0
	var frames: Array[float] = []
	for index: int in 100:
		frames.append(FRAME_90)
	var under: RenderStats = _stats(0, [120.0, 400000.0, 2000.0], [0.0, 0.0, 0.0])
	var measurements: Dictionary = {}
	var outcome: Array = AcceptanceFrameBudgetCheck.judge(frames, 90.0, step, measurements, FrameStats.BUDGET_PATH,
		under)
	if outcome[0] != AcceptanceReport.RESULT_PASS or not str(outcome[1]).contains("draw_calls p95 120") \
			or not str(outcome[1]).contains("p99") or outcome[1] != measurements["summary"] \
			or not measurements.has("mean_ms") or not measurements.has("memory_mb_p95"):
		return "under budget: %s %s" % [outcome, measurements]
	var over: RenderStats = _stats(100, [0.0, 0.0, 0.0], [300.0, 400000.0, 2000.0])
	outcome = AcceptanceFrameBudgetCheck.judge(frames, 90.0, step, {}, FrameStats.BUDGET_PATH, over)
	if outcome[0] != AcceptanceReport.RESULT_FAIL or not str(outcome[1]).contains("over budget: draw_calls"):
		return "steady frames but too many draw calls: %s" % [outcome]
	return ""


func test_the_check_samples_render_numbers_only_for_counted_frames() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.settle_seconds = 0.5
	step.measure_seconds = 1.0
	var measured: AcceptanceFrameBudgetCheck = AcceptanceFrameBudgetCheck.new(step)
	for index: int in 300:
		measured.add(FRAME_90)
	# Headless, the engine reads nothing: the samples are empty, not zeros.
	for metric: String in RenderBudget.METRICS:
		if measured.render.count(metric) != 0:
			return "%s sampled headless: %d" % [metric, measured.render.count(metric)]
	var not_read: Array[float] = [RenderStats.NOT_READ, RenderStats.NOT_READ, RenderStats.NOT_READ]
	if RenderStats.read_frame() != not_read:
		return "headless read: %s" % [RenderStats.read_frame()]
	return ""
