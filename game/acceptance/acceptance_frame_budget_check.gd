class_name AcceptanceFrameBudgetCheck
extends RefCounted

## The `frame_budget` acceptance check (#643, PRF-1, CMF-1, DEV-6, gate G1):
## on the headset, the frame times of a gentle flight through the empty test
## tunnel must hold the refresh rate in use, and that rate must be at least
## 90 Hz. Kept out of `AcceptanceRunner` so that file stays short.
##
## The runner hands every frame's duration to `add` while the step runs. The
## first `settle_seconds` are not counted (the scene and the runtime are still
## settling after the step switch); the next `measure_seconds` are. The rate
## is read back from the scene's `RefreshRate` when the step is judged, the
## same value the `refresh_rate` check reads, never the rate requested.
##
## A frame counts as over budget when it is longer than the rate's frame time
## plus `budget_slack_ms`. The slack is there because a frame's measured
## duration jitters around the display interval even when no frame is missed;
## it is stated in the suite file so the pass mark is visible and tunable
## (ARC-4). Frames longer than `FrameStats`'s dropped threshold (1.5 frame
## times, a missed display refresh) are reported as well.
##
## The same frames also sample draw calls, triangles and memory (`RenderStats`,
## #1289, PRF-4 to PRF-6). The step fails when one's 95th percentile is over
## its limit in `RenderBudget`, and reports the values either way.

## PRF-1: the rate the headset must hold.
const REQUIRED_HZ: float = 90.0
## The suite keys only a frame_budget step may list, and must list all of.
const STEP_KEYS: Array[String] = ["settle_seconds", "measure_seconds", "max_over_budget_share",
	"budget_slack_ms"]
## Longer than this is a mistyped suite, not a benchmark. Room for the
## 25-minute soak PRF-3 names (#788) and its settling.
const MAX_SECONDS: float = 1800.0
## Above this the slack would hide a missed frame (half a 90 Hz frame time).
const MAX_SLACK_MS: float = 5.5

var settle_seconds: float = 0.0
var measure_seconds: float = 0.0
## Durations in seconds of the frames counted, in order.
var frames: Array[float] = []
## Draw calls, triangles and memory of the frames counted (#1289).
var render: RenderStats = RenderStats.new()

var _seen_seconds: float = 0.0


func _init(step: AcceptanceStep) -> void:
	settle_seconds = step.settle_seconds
	measure_seconds = step.measure_seconds


## Records one frame, with its render numbers read from the engine. Frames
## inside the settle period are not kept.
func add(frame_seconds: float) -> void:
	if done() or not frame_seconds > 0.0:
		return
	_seen_seconds += frame_seconds
	if _seen_seconds > settle_seconds:
		frames.append(frame_seconds)
		render.add_frame()


## Whether the measured period is over, so the step may be judged.
func done() -> bool:
	return _seen_seconds >= settle_seconds + measure_seconds


## Whether frame times taken here count: only on the headset itself. Monado,
## the simulator and the desktop run OpenXR too, but say nothing about the
## Quest's frame times (PRF-1, decision record 0005).
static func measures_here(xr_available: bool, on_headset: bool) -> bool:
	return xr_available and on_headset


## Why the step was not measured here, for the skipped message.
static func not_measured_reason(xr_available: bool) -> String:
	return "not on the headset: no OpenXR runtime" if not xr_available \
		else "not on the headset: frame times count only on the Quest"


## Reads the frame_budget keys of one suite step. Returns the problem, or "".
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wanted: bool = step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET)
	for key: String in STEP_KEYS:
		if not data.has(key):
			if wanted:
				return "%s.%s: needed by the frame_budget check" % [field, key]
			continue
		if not wanted:
			return "%s.%s: only used by the frame_budget check, which the step does not list" % [field, key]
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if (typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT) or not is_finite(float(value)):
			return "%s.%s: must be a number" % [field, key]
	if not wanted:
		return ""
	step.settle_seconds = float(data["settle_seconds"])
	step.measure_seconds = float(data["measure_seconds"])
	step.max_over_budget_share = float(data["max_over_budget_share"])
	step.budget_slack_ms = float(data["budget_slack_ms"])
	if step.settle_seconds < 0.0 or step.settle_seconds > MAX_SECONDS:
		return "%s.settle_seconds: must be 0 to %s" % [field, MAX_SECONDS]
	if not step.measure_seconds > 0.0 or step.measure_seconds > MAX_SECONDS:
		return "%s.measure_seconds: must be above 0 and at most %s" % [field, MAX_SECONDS]
	if step.max_over_budget_share < 0.0 or step.max_over_budget_share > 1.0:
		return "%s.max_over_budget_share: must be 0 to 1" % field
	if step.budget_slack_ms < 0.0 or step.budget_slack_ms > MAX_SLACK_MS:
		return "%s.budget_slack_ms: must be 0 to %s" % [field, MAX_SLACK_MS]
	return ""


## [result, message] for the check in `main`, adding the numbers to `measurements`.
static func run(main: Node, xr_available: bool, on_headset: bool, step: AcceptanceStep,
		measured: AcceptanceFrameBudgetCheck, measurements: Dictionary) -> Array:
	if not measures_here(xr_available, on_headset) or measured == null:
		return [AcceptanceReport.RESULT_FAIL if step.required else AcceptanceReport.RESULT_SKIPPED,
			not_measured_reason(xr_available)]
	var rate: RefreshRate = main.get("refresh_rate") as RefreshRate
	if rate == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no refresh rate"]
	# A 120 Hz step where 120 is not offered would only measure 90 again (#851).
	var reason: String = AcceptanceRefresh120.not_offered_reason(rate) if step.refresh_120 else ""
	if reason != "":
		return [AcceptanceReport.RESULT_FAIL if step.required else AcceptanceReport.RESULT_SKIPPED, reason]
	return judge(measured.frames, rate.in_use_hz, step, measurements, FrameStats.BUDGET_PATH, measured.render)


## [result, message] for `frames` (seconds each) flown at `in_use_hz`, and for
## `render`'s samples when given (#1289): the frame times and the render
## numbers are both in the message and `measurements`, and either over its
## budget fails the step.
static func judge(frames: Array[float], in_use_hz: float, step: AcceptanceStep, measurements: Dictionary,
		budget_path: String = FrameStats.BUDGET_PATH, render: RenderStats = null,
		render_budget_path: String = RenderBudget.BUDGET_PATH) -> Array:
	var timed: Array = _judge_times(frames, in_use_hz, step, measurements, budget_path)
	if render == null:
		return timed
	var drawn: Array = render.judge(RenderBudget.load_file(render_budget_path), measurements)
	var summary: String = "%s; %s" % [timed[1], drawn[1]]
	measurements["summary"] = summary
	if timed[0] == AcceptanceReport.RESULT_FAIL or drawn[0] == AcceptanceReport.RESULT_FAIL:
		return [AcceptanceReport.RESULT_FAIL, summary]
	return [timed[0], summary]


static func _judge_times(frames: Array[float], in_use_hz: float, step: AcceptanceStep, measurements: Dictionary,
		budget_path: String) -> Array:
	measurements["refresh_rate_in_use_hz"] = in_use_hz
	if in_use_hz == RefreshRate.UNKNOWN:
		return [AcceptanceReport.RESULT_FAIL, "the rate in use was not read back"]
	if in_use_hz < REQUIRED_HZ - RefreshRate.SAME_RATE_HZ:
		return [AcceptanceReport.RESULT_FAIL, "%s Hz in use, below the %s Hz the headset must hold"
			% [in_use_hz, REQUIRED_HZ]]
	var stats: FrameStats = FrameStats.load_budget(in_use_hz, budget_path)
	if stats.error != "":
		return [AcceptanceReport.RESULT_FAIL, stats.error]
	for seconds: float in frames:
		stats.add(seconds)
	if stats.count() == 0:
		return [AcceptanceReport.RESULT_FAIL, "no frame times were recorded"]
	var limit_ms: float = stats.budget_ms() + step.budget_slack_ms
	var over: int = stats.count_over(limit_ms)
	var share: float = float(over) / stats.count()
	measurements.merge(stats.to_measurements(), true)
	measurements["budget_slack_ms"] = step.budget_slack_ms
	measurements["over_budget"] = over
	measurements["over_budget_share"] = snappedf(share, 0.0001)
	measurements["max_over_budget_share"] = step.max_over_budget_share
	var summary: String = "%s Hz, %d frames: mean %.2f, p95 %.2f, p99 %.2f ms (budget %.2f + %.2f); over budget %d (%s, allowed %s); dropped %d" % [
		in_use_hz, stats.count(), stats.mean_ms(), stats.p95_ms(), stats.p99_ms(), stats.budget_ms(),
		step.budget_slack_ms, over, _percent(share), _percent(step.max_over_budget_share), stats.dropped()]
	measurements["summary"] = summary
	if stats.p99_ms() > limit_ms:
		return [AcceptanceReport.RESULT_FAIL, "p99 %.2f ms over the %.2f ms limit; %s" % [
			stats.p99_ms(), limit_ms, summary]]
	if share > step.max_over_budget_share:
		return [AcceptanceReport.RESULT_FAIL, "%s of frames over budget, allowed %s; %s" % [
			_percent(share), _percent(step.max_over_budget_share), summary]]
	return [AcceptanceReport.RESULT_PASS, summary]


static func _percent(fraction: float) -> String:
	return "%s%%" % snappedf(fraction * 100.0, 0.1)
