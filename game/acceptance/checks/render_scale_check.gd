extends RefCounted

## The `render_scale` check (#1417, GFX-7, PRF-2, PRF-3, ARC-4), lane-a's
## file under `acceptance/checks/`. In `suites/m6/perf.json`:
##
##     {"id": "render_scale", "checks": ["no_script_errors", "render_scale"]}
##
## Drives a `RenderScaleController` on the shipped `xr/render_scale.json`
## with a scripted run at 90 Hz: `SLOW_FRAMES` frames whose GPU time is
## `SLOW_SHARE` of the budget, then frames at `FAST_SHARE` until the scale is
## back. It passes when the scale went below 1.0, never below the table's
## floor, changed at most once per `interval_frames`, and came back to
## exactly 1.0 within `MAX_FAST_FRAMES`. The controller is pure, so this runs
## the same on every machine; whether a lowered scale is visible stays a
## headset check.

const CHECK: String = "render_scale"
const HZ: float = 90.0
const SLOW_FRAMES: int = 600
## Well past any `high_water` the table allows (2.0), and well under any `low_water` (0.1).
const SLOW_SHARE: float = 2.5
const FAST_SHARE: float = 0.05
const MAX_FAST_FRAMES: int = 3600


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var scripted: Array = judge_table(RenderScaleTable.DEFAULT_FILE, measurements)
	var live: Array = judge_samples(RenderScaler.recent, RenderScaleTable.load_file(), measurements)
	var failed: bool = scripted[0] == AcceptanceReport.RESULT_FAIL or live[0] == AcceptanceReport.RESULT_FAIL
	return [AcceptanceReport.RESULT_FAIL if failed else scripted[0], "%s; %s" % [scripted[1], live[1]]]


## [result, message] for the headset frames the scaler was fed before the
## step (#1509): in m6 the stress scene's last `RenderScaleSamples.CAPACITY`.
## Reports their mean CPU and GPU time and the scale's min and mean. Fails
## when every frame sat at the floor while both mean times were under
## `high_water` of the budget, the controller's own mark for a frame that is
## not long: the scale should then have climbed (the device's 27 Nov run).
## Off the headset no frame is sampled and this part passes, saying so.
static func judge_samples(samples: RenderScaleSamples, table: RenderScaleTable, measurements: Dictionary) -> Array:
	measurements["headset_frames_sampled"] = samples.count()
	if samples.count() == 0:
		return [AcceptanceReport.RESULT_PASS, "no headset frames sampled"]
	var budget_ms: float = samples.mean_budget_ms()
	measurements["frame_budget_ms"] = snappedf(budget_ms, 0.01)
	measurements["render_cpu_ms_mean"] = snappedf(samples.mean_cpu_ms(), 0.01)
	measurements["render_gpu_ms_mean"] = snappedf(samples.mean_gpu_ms(), 0.01)
	measurements["render_scale_min"] = snappedf(samples.min_scale(), 0.001)
	measurements["render_scale_mean"] = snappedf(samples.mean_scale(), 0.001)
	var summary: String = "%d headset frames: CPU %.2f ms, GPU %.2f ms (budget %.2f), scale min %.2f, mean %.2f" % [
		samples.count(), samples.mean_cpu_ms(), samples.mean_gpu_ms(), budget_ms, samples.min_scale(),
		samples.mean_scale()]
	var limit_ms: float = budget_ms * table.high_water
	if table.enabled and samples.all_at(table.floor_scale) and samples.mean_cpu_ms() < limit_ms \
			and samples.mean_gpu_ms() < limit_ms:
		return [AcceptanceReport.RESULT_FAIL, "the scale sat at its floor %.2f on every frame while CPU and GPU were under %.2f ms; %s" % [
			table.floor_scale, limit_ms, summary]]
	return [AcceptanceReport.RESULT_PASS, summary]


## [result, message] for the scripted run on the table at `path`.
static func judge_table(path: String, measurements: Dictionary) -> Array:
	var table: RenderScaleTable = RenderScaleTable.load_file(path)
	if table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "%s rejected: %s" % [path, table.error]]
	if not table.enabled:
		return [AcceptanceReport.RESULT_FAIL, "scaling is off in %s" % path]
	var controller: RenderScaleController = RenderScaleController.new(table)
	var budget_ms: float = 1000.0 / HZ
	var seen: Dictionary = {"lowest": controller.scale, "changes": 0, "closest": SLOW_FRAMES + MAX_FAST_FRAMES,
		"since": 0, "last": controller.scale}
	for i: int in SLOW_FRAMES:
		_frame(controller, budget_ms * SLOW_SHARE, seen)
	var back_after: int = -1
	for i: int in MAX_FAST_FRAMES:
		_frame(controller, budget_ms * FAST_SHARE, seen)
		if controller.scale == 1.0:
			back_after = i + 1
			break
	measurements["render_scale_lowest"] = snappedf(seen["lowest"], 0.001)
	measurements["render_scale_changes"] = seen["changes"]
	measurements["frames_back_to_full"] = back_after
	if seen["lowest"] >= 1.0:
		return [AcceptanceReport.RESULT_FAIL, "the scale never went below 1.0 in %d slow frames" % SLOW_FRAMES]
	if seen["lowest"] < table.floor_scale:
		return [AcceptanceReport.RESULT_FAIL, "the scale went to %.3f, below the floor %.3f" % [seen["lowest"], table.floor_scale]]
	if seen["closest"] < table.interval_frames:
		return [AcceptanceReport.RESULT_FAIL, "two changes %d frames apart, the interval is %d" % [
			seen["closest"], table.interval_frames]]
	if back_after < 0:
		return [AcceptanceReport.RESULT_FAIL, "the scale stayed at %.3f after %d fast frames" % [controller.scale, MAX_FAST_FRAMES]]
	return [AcceptanceReport.RESULT_PASS, "down to %.2f (floor %.2f) in %d slow frames, back to 1.0 after %d fast frames, %d changes" % [
		seen["lowest"], table.floor_scale, SLOW_FRAMES, back_after, seen["changes"]]]


static func _frame(controller: RenderScaleController, gpu_ms: float, seen: Dictionary) -> void:
	controller.advance(gpu_ms * 0.5, gpu_ms, HZ)
	seen["since"] += 1
	if controller.scale != seen["last"]:
		seen["changes"] += 1
		if seen["changes"] > 1:
			seen["closest"] = mini(seen["closest"], seen["since"])
		seen["since"] = 0
		seen["last"] = controller.scale
	seen["lowest"] = minf(seen["lowest"], controller.scale)
