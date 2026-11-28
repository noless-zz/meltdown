extends RefCounted

## The scaler's window of recent headset frames (#1509, GFX-7, PRF-2) and
## the m6 `render_scale` step's verdict on it: means and scale bounds are
## right, only the last frames are kept, and the step fails only when the
## scale sat at its floor on every frame while CPU and GPU were under
## `high_water` of the budget.

const CHECK: GDScript = preload("res://acceptance/checks/render_scale_check.gd")
const HZ: float = 120.0
const BUDGET_MS: float = 1000.0 / 120.0


func _table(enabled: bool = true) -> RenderScaleTable:
	var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify({"enabled": enabled, "floor": 0.7,
		"ceiling": 1.0, "step": 0.1, "high_water": 0.9, "low_water": 0.7, "frames_down": 5,
		"frames_up": 45, "interval_frames": 30}))
	assert(table.error == "", table.error)
	return table


static func _filled(frames: int, cpu_ms: float, gpu_ms: float, scale: float) -> RenderScaleSamples:
	var samples: RenderScaleSamples = RenderScaleSamples.new()
	for i: int in frames:
		samples.add(cpu_ms, gpu_ms, scale, HZ)
	return samples


func test_means_and_scale_bounds() -> String:
	var samples: RenderScaleSamples = RenderScaleSamples.new()
	samples.add(2.0, 4.0, 1.0, HZ)
	samples.add(4.0, 6.0, 0.8, HZ)
	if samples.count() != 2 or not is_equal_approx(samples.mean_cpu_ms(), 3.0) \
			or not is_equal_approx(samples.mean_gpu_ms(), 5.0):
		return "count %d, CPU %s, GPU %s" % [samples.count(), samples.mean_cpu_ms(), samples.mean_gpu_ms()]
	if not is_equal_approx(samples.min_scale(), 0.8) or not is_equal_approx(samples.mean_scale(), 0.9):
		return "scale min %s, mean %s" % [samples.min_scale(), samples.mean_scale()]
	if not is_equal_approx(samples.mean_budget_ms(), BUDGET_MS):
		return "budget %s" % samples.mean_budget_ms()
	return ""


func test_only_the_last_frames_are_kept() -> String:
	var samples: RenderScaleSamples = _filled(RenderScaleSamples.CAPACITY, 9.0, 9.0, 0.7)
	for i: int in RenderScaleSamples.CAPACITY:
		samples.add(2.0, 3.0, 1.0, HZ)
	if samples.count() != RenderScaleSamples.CAPACITY:
		return "kept %d" % samples.count()
	if not is_equal_approx(samples.mean_cpu_ms(), 2.0) or samples.min_scale() != 1.0:
		return "old frames left: CPU %s, min scale %s" % [samples.mean_cpu_ms(), samples.min_scale()]
	samples.clear()
	if samples.count() != 0 or samples.all_at(1.0):
		return "clear left %d frames" % samples.count()
	return ""


func test_a_frame_with_no_rate_or_a_bad_time() -> String:
	var samples: RenderScaleSamples = RenderScaleSamples.new()
	samples.add(2.0, 3.0, 1.0, 0.0)
	samples.add(2.0, 3.0, 1.0, NAN)
	if samples.count() != 0:
		return "frames with no rate were kept"
	samples.add(NAN, -1.0, 1.0, HZ)
	if samples.mean_cpu_ms() != 0.0 or samples.mean_gpu_ms() != 0.0:
		return "bad times kept as %s and %s" % [samples.mean_cpu_ms(), samples.mean_gpu_ms()]
	return ""


func test_stuck_at_the_floor_with_time_to_spare_fails() -> String:
	var measured: Dictionary = {}
	var verdict: Array = CHECK.judge_samples(_filled(600, 3.5, 4.0, 0.7), _table(), measured)
	if verdict[0] != AcceptanceReport.RESULT_FAIL:
		return "passed: %s" % verdict[1]
	for key: String in ["render_cpu_ms_mean", "render_gpu_ms_mean", "render_scale_min", "render_scale_mean",
			"frame_budget_ms", "headset_frames_sampled"]:
		if not measured.has(key):
			return "no %s in %s" % [key, measured]
	if not is_equal_approx(measured["render_cpu_ms_mean"], 3.5) or not is_equal_approx(measured["render_gpu_ms_mean"], 4.0) \
			or not is_equal_approx(measured["render_scale_min"], 0.7) or measured["headset_frames_sampled"] != 600:
		return "measured %s" % measured
	return ""


func test_at_the_floor_with_no_time_to_spare_passes() -> String:
	# GPU over high_water at the floor: the floor is where it should be.
	var verdict: Array = CHECK.judge_samples(_filled(600, 3.5, BUDGET_MS * 0.95, 0.7), _table(), {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return verdict[1]
	verdict = CHECK.judge_samples(_filled(600, BUDGET_MS * 0.95, 3.0, 0.7), _table(), {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "a long CPU: %s" % verdict[1]
	return ""


func test_a_scale_that_moved_or_stayed_full_passes() -> String:
	var samples: RenderScaleSamples = _filled(300, 3.5, 4.0, 0.7)
	samples.add(3.5, 4.0, 0.8, HZ)
	var verdict: Array = CHECK.judge_samples(samples, _table(), {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "a scale that climbed: %s" % verdict[1]
	verdict = CHECK.judge_samples(_filled(600, 3.5, 4.0, 1.0), _table(), {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "full scale: %s" % verdict[1]
	return ""


func test_scaling_off_or_no_frames_passes_and_says_so() -> String:
	var verdict: Array = CHECK.judge_samples(_filled(600, 3.5, 4.0, 0.7), _table(false), {})
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "scaling off: %s" % verdict[1]
	var measured: Dictionary = {}
	verdict = CHECK.judge_samples(RenderScaleSamples.new(), _table(), measured)
	if verdict[0] != AcceptanceReport.RESULT_PASS or not String(verdict[1]).contains("no headset frames") \
			or measured.get("headset_frames_sampled", -1) != 0:
		return "no frames: %s %s" % [verdict, measured]
	return ""
