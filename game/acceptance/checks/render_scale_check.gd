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
	return judge_table(RenderScaleTable.DEFAULT_FILE, measurements)


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
