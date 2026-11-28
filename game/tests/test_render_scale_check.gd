extends RefCounted

## The m6 `render_scale` check and the render scale beside the frame times
## (#1417, GFX-7, PRF-2, PRF-3, DEV-6): the shipped table has scaling off
## and the scripted run leaves the scale at 1.0 (#1503); with scaling on, a
## scripted run of slow then fast frames takes the scale down and back to
## 1.0; a refused table fails with the reason; the step is in the m6 perf part; and
## the frame budget report carries the scale's minimum, mean and frames below
## 1.0 without changing its result.

const CHECK: GDScript = preload("res://acceptance/checks/render_scale_check.gd")
const SCRATCH: String = "user://t1417_render_scale_check.json"
const PERF_PART: String = "res://acceptance/suites/m6/perf.json"


func _write(changes: Dictionary) -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(RenderScaleTable.DEFAULT_FILE))
	data.merge(changes, true)
	var file: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func test_the_shipped_table_is_off_and_holds_full_scale() -> String:
	var measurements: Dictionary = {}
	var verdict: Array = CHECK.judge_table(RenderScaleTable.DEFAULT_FILE, measurements)
	if verdict[0] != AcceptanceReport.RESULT_PASS or not str(verdict[1]).contains("scaling off"):
		return "the check said %s" % [verdict]
	if measurements["render_scale_enabled"] != false or float(measurements["render_scale_lowest"]) != 1.0 \
			or int(measurements["render_scale_changes"]) != 0:
		return "measured %s" % measurements
	return ""


func test_an_on_table_goes_down_and_comes_back() -> String:
	_write({"enabled": true})
	var measurements: Dictionary = {}
	var verdict: Array = CHECK.judge_table(SCRATCH, measurements)
	DirAccess.remove_absolute(SCRATCH)
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "the check said %s" % [verdict]
	if float(measurements["render_scale_lowest"]) >= 1.0 or int(measurements["frames_back_to_full"]) <= 0:
		return "measured %s" % measurements
	return ""


func test_a_refused_or_stuck_table_fails_with_the_reason() -> String:
	_write({"enabled": true, "step": 9.0})
	var refused: Array = CHECK.judge_table(SCRATCH, {})
	_write({"enabled": true, "ceiling": 0.9})
	var low_ceiling: Array = CHECK.judge_table(SCRATCH, {})
	DirAccess.remove_absolute(SCRATCH)
	if refused[0] != AcceptanceReport.RESULT_FAIL or not str(refused[1]).contains("\"step\""):
		return "a refused table: %s" % [refused]
	if low_ceiling[0] != AcceptanceReport.RESULT_FAIL or not str(low_ceiling[1]).contains("stayed"):
		return "a 0.9 ceiling never reaches 1.0, yet: %s" % [low_ceiling]
	return ""


func test_the_m6_perf_part_lists_the_step() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PERF_PART))
	for step: Dictionary in data["steps"]:
		if step["id"] == "render_scale":
			return "" if (step["checks"] as Array).has("render_scale") else "the step does not list the check"
	return "the perf part has no render_scale step"


func test_the_frame_budget_reports_the_scale_beside_the_times() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.checks.append(AcceptanceStep.CHECK_FRAME_BUDGET)
	step.max_over_budget_share = 0.01
	step.budget_slack_ms = 1.0
	var frames: Array[float] = []
	var scales: AcceptanceRenderScaleStats = AcceptanceRenderScaleStats.new()
	for i: int in 900:
		frames.append(1.0 / 90.0)
		scales.add(0.8 if i < 100 else 1.0)
	var without: Array = AcceptanceFrameBudgetCheck.judge(frames, 90.0, step, {})
	var measurements: Dictionary = {}
	var verdict: Array = AcceptanceFrameBudgetCheck.judge(frames, 90.0, step, measurements,
		FrameStats.BUDGET_PATH, null, RenderBudget.BUDGET_PATH, scales)
	if verdict[0] != without[0]:
		return "the scale changed the result: %s against %s" % [verdict[0], without[0]]
	if measurements.get("render_scale_min") != 0.8 or measurements.get("render_scale_frames_below_full") != 100 \
			or absf(float(measurements.get("render_scale_mean", 0.0)) - 0.978) > 0.001:
		return "measured %s" % measurements
	if not str(verdict[1]).contains("render scale min 0.80, mean 0.98, 100 of 900 frames below 1.0") \
			or not str(verdict[1]).contains("mean 11.11"):
		return "the message is \"%s\"" % verdict[1]
	return ""


func test_the_frame_budget_sampler_reads_the_scale_in_use() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.settle_seconds = 0.0
	step.measure_seconds = 1.0
	var sampler: AcceptanceFrameBudgetCheck = AcceptanceFrameBudgetCheck.new(step)
	RenderScaler.in_use = 0.9
	sampler.add(0.5)
	RenderScaler.in_use = 1.0
	sampler.add(0.5)
	if sampler.scales.frames != 2 or sampler.scales.minimum != 0.9 or sampler.scales.below_full != 1:
		return "sampled %d frames, min %s, %d below" % [sampler.scales.frames, sampler.scales.minimum,
			sampler.scales.below_full]
	return ""
