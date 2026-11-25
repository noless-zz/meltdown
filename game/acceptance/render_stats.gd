class_name RenderStats
extends RefCounted

## Draw calls, triangles and memory per measured frame, judged on their 95th
## percentile against a `RenderBudget` (#1289, PRF-4 to PRF-6). Kept beside
## `FrameStats` so the frame_budget check reports both from the same frames
## and one device run of the stress scene answers PRF-1 to PRF-6.
##
## The arithmetic takes fed samples, so it is tested without a renderer;
## `read_frame` is the only part that asks the engine. A value below zero
## means "not read" and is left out of that metric: a metric with no samples
## is reported as skipped, never as passed.

const NOT_READ: float = -1.0
const MIB: float = 1048576.0
const PERCENTILE: float = 0.95

## Samples per metric, by `RenderBudget.METRICS` name.
var samples: Dictionary[String, Array] = {}


func _init() -> void:
	for metric: String in RenderBudget.METRICS:
		samples[metric] = [] as Array[float]


## Records one frame's values, in `RenderBudget.METRICS` order.
func add(draw_calls: float, triangles: float, memory_mb: float) -> void:
	var values: Array[float] = [draw_calls, triangles, memory_mb]
	for index: int in values.size():
		if values[index] >= 0.0 and is_finite(values[index]):
			(samples[RenderBudget.METRICS[index]] as Array).append(values[index])


## Records the frame just rendered, as `read_frame` reads it.
func add_frame() -> void:
	var values: Array[float] = read_frame()
	add(values[0], values[1], values[2])


func count(metric: String) -> int:
	return (samples[metric] as Array).size()


## The smallest value that at least `fraction` of samples are no larger than
## (nearest rank, as `FrameStats.percentile_ms`); 0 with no samples.
func percentile(metric: String, fraction: float) -> float:
	var sorted: Array = (samples[metric] as Array).duplicate()
	if sorted.is_empty():
		return 0.0
	sorted.sort()
	var rank: int = ceili(fraction * sorted.size())
	return float(sorted[clampi(rank, 1, sorted.size()) - 1])


func max_value(metric: String) -> float:
	var values: Array = samples[metric]
	return float(values.max()) if not values.is_empty() else 0.0


## [result, message] for the samples against `budget`, adding every metric's
## numbers to `measurements` whether it passed or not. Fails when a metric's
## p95 is over its limit; skipped when no metric was read at all.
func judge(budget: RenderBudget, measurements: Dictionary) -> Array:
	if budget.error != "":
		return [AcceptanceReport.RESULT_FAIL, budget.error]
	var parts: PackedStringArray = PackedStringArray()
	var over: PackedStringArray = PackedStringArray()
	var read: int = 0
	for metric: String in RenderBudget.METRICS:
		var limit: float = budget.limits[metric]
		measurements["%s_budget" % metric] = limit
		measurements["%s_samples" % metric] = count(metric)
		if count(metric) == 0:
			measurements["%s_result" % metric] = AcceptanceReport.RESULT_SKIPPED
			parts.append("%s not read (skipped)" % metric)
			continue
		read += 1
		var p95: float = snappedf(percentile(metric, PERCENTILE), 0.1)
		measurements["%s_p95" % metric] = p95
		measurements["%s_max" % metric] = snappedf(max_value(metric), 0.1)
		var fails: bool = p95 > limit
		measurements["%s_result" % metric] = AcceptanceReport.RESULT_FAIL if fails else AcceptanceReport.RESULT_PASS
		parts.append("%s p95 %s (budget %s)" % [metric, _number(p95), _number(limit)])
		if fails:
			over.append(metric)
	var summary: String = ", ".join(parts)
	measurements["render_summary"] = summary
	if not over.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "over budget: %s; %s" % [", ".join(over), summary]]
	if read == 0:
		return [AcceptanceReport.RESULT_SKIPPED, summary]
	return [AcceptanceReport.RESULT_PASS, summary]


## The frame just rendered: draw calls, triangles for both eyes, and memory in
## use (CPU static plus video) in MiB, each NOT_READ where the engine has no
## number. View layer only (ARC-1): nothing here is simulation state.
##
## The mobile renderer draws both eyes in one multiview pass and counts each
## draw's primitives once, so the triangle count is multiplied by the views.
static func read_frame() -> Array[float]:
	if DisplayServer.get_name() == "headless":
		return [NOT_READ, NOT_READ, NOT_READ] as Array[float]
	var draw_calls: float = float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var triangles: float = float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)) * view_count()
	var static_bytes: float = Performance.get_monitor(Performance.MEMORY_STATIC)
	var video_bytes: float = float(RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED))
	# Static memory is only tracked in debug builds; without it the total would understate.
	var memory_mb: float = (static_bytes + video_bytes) / MIB if static_bytes > 0.0 else NOT_READ
	return [draw_calls, triangles, memory_mb] as Array[float]


## Views drawn per frame: 2 on a headset with an active OpenXR session, else 1.
static func view_count() -> int:
	var xr: XRInterface = XRServer.primary_interface
	if xr == null or not xr.is_initialized():
		return 1
	return maxi(1, xr.get_view_count())


## Whole numbers without ".0"; others with one decimal.
static func _number(value: float) -> String:
	return str(int(value)) if value == floorf(value) else "%.1f" % value
