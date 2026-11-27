extends RefCounted

## The `level_load` check (#1445, #1480, PRF-7, PRF-8, ARC-1, DEV-6), lane-b's file
## under `acceptance/checks/`, for the m6 perf step of the same name. Its frame
## work (`LevelLoadFrames`) loads the levels `LevelLoadPlan` lists (each run
## seed's deepest level through the busiest shaft, and the stress level) into
## the scene one at a time, each timed with `LevelLoadTiming` up to the frame
## drawn after it. The judge takes the worst `total_s` against the plan's
## `budget_seconds`. A failure names the level and its slowest phase, so the
## next run knows where to look.
##
## Every load is also built once without the clock and its state hash compared,
## so the measurement provably leaves the simulation as it was (ARC-1, ARC-2).
## Headless CI is slower than the headset in some phases and faster in others,
## and draws no frame: there the check reports its times as "skipped", and the
## headset number is a gate check.

const CHECK: String = "level_load"
## Measurements are rounded to this many decimals, enough for milliseconds.
const DECIMALS: float = 0.001


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func frame_work() -> Dictionary[String, Callable]:
	return {CHECK: _start}


static func _start(_step: AcceptanceStep, runner: AcceptanceRunner, frames: AcceptanceFrameHook) -> void:
	frames.results[CHECK] = LevelLoadFrames.start(runner.main, frames)


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var frames: AcceptanceFrameHook = runner.frame_hook() if runner != null else null
	var work: LevelLoadFrames = frames.results.get(CHECK) as LevelLoadFrames if frames != null else null
	if work == null:
		return [AcceptanceReport.RESULT_FAIL, "no level was loaded: the check's frame work did not run"]
	if work.error != "":
		return [AcceptanceReport.RESULT_FAIL, work.error]
	if not work.done:
		return [AcceptanceReport.RESULT_FAIL, "the loads did not finish"]
	return judge_timings(work.timings, work.budget_seconds, measurements)


## [result, message] for `timings` (each with a `label`, the phases and
## `total_s`) against `budget_seconds`, adding them to `measurements`. Fails
## when the worst total is over the budget, naming that load and its slowest phase.
static func judge_timings(timings: Array[Dictionary], budget_seconds: float, measurements: Dictionary) -> Array:
	if timings.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no level was loaded"]
	var worst: Dictionary = timings[0]
	var shown: Array = []
	for timing: Dictionary in timings:
		if float(timing[LevelLoadTiming.TOTAL]) > float(worst[LevelLoadTiming.TOTAL]):
			worst = timing
		var row: Dictionary = {"label": timing["label"]}
		for key: String in LevelLoadTiming.PHASES + [LevelLoadTiming.TOTAL]:
			row[key] = snappedf(float(timing.get(key, 0.0)), DECIMALS)
		shown.append(row)
	var total: float = float(worst[LevelLoadTiming.TOTAL])
	var phase: String = slowest_phase(worst)
	measurements["level_loads"] = shown
	measurements["budget_seconds"] = budget_seconds
	measurements["worst_total_s"] = snappedf(total, DECIMALS)
	var detail: String = "%s: %.3f s, slowest phase %s %.3f s" \
		% [worst["label"], total, phase, float(worst.get(phase, 0.0))]
	var drawn: bool = all_drawn(timings)
	measurements["first_frame_drawn"] = drawn
	if total > budget_seconds:
		return [AcceptanceReport.RESULT_FAIL, "over the %.1f s budget: %s" % [budget_seconds, detail]]
	var within: String = "%d levels within the %.1f s budget; worst %s" % [timings.size(), budget_seconds, detail]
	if not drawn:  # Decision record 0005: a number without its GPU part proves nothing yet.
		return [AcceptanceReport.RESULT_SKIPPED, "%s; no frame was really drawn here, so %s is not the GPU's" \
			% [within, LevelLoadTiming.FIRST_FRAME]]
	return [AcceptanceReport.RESULT_PASS, within]


## True when every load's first frame was really drawn; a timing without `drawn` counts as drawn.
static func all_drawn(timings: Array[Dictionary]) -> bool:
	for timing: Dictionary in timings:
		if not bool(timing.get(LevelLoadTiming.DRAWN, true)):
			return false
	return true


## The phase of `timing` that took longest; the first on a tie.
static func slowest_phase(timing: Dictionary) -> String:
	var slowest: String = LevelLoadTiming.PHASES[0]
	for phase: String in LevelLoadTiming.PHASES:
		if float(timing.get(phase, 0.0)) > float(timing.get(slowest, 0.0)):
			slowest = phase
	return slowest
