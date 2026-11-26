class_name RenderScaleController
extends RefCounted

## Dynamic resolution scaling's decision, apart from any node (#1417, GFX-7,
## PRF-2, PRF-3): fed each frame's CPU and GPU time and the refresh rate in
## use, it answers the render scale, a share of the full eye resolution.
##
## The frame budget is one refresh interval. A frame whose longer time (CPU or
## GPU, whichever bound it) runs over `high_water` of the budget counts as
## long, one under `low_water` as having headroom, anything between resets
## both runs. `frames_down` long frames in a row lower the scale by `step`;
## `frames_up` frames with headroom in a row raise it by `step`. At most one
## change per `interval_frames`, so the picture does not pump, and the scale
## stays within `floor` and `ceiling` (never above 1.0). Off in the table, it
## is always 1.0. A frame with no rate or no usable time changes nothing.
##
## View only: the scale goes to the render target (`RenderScaler`); the
## simulation never hears of it (ARC-3, MP-2). The values are data
## (`RenderScaleTable`, ARC-4).

var table: RenderScaleTable
## The scale for the next frame.
var scale: float = 1.0
## Long frames, and frames with headroom, in the current run.
var long_frames: int = 0
var headroom_frames: int = 0
## Frames since the last change, counted from the start too.
var frames_since_change: int = 0


func _init(p_table: RenderScaleTable = RenderScaleTable.new()) -> void:
	table = p_table
	scale = table.ceiling if table.enabled else 1.0
	frames_since_change = table.interval_frames


## The controller on the file at `path` (`RenderScaleTable.load_file`).
static func load_file(path: String = RenderScaleTable.DEFAULT_FILE) -> RenderScaleController:
	return RenderScaleController.new(RenderScaleTable.load_file(path))


## One rendered frame: its CPU and GPU time in milliseconds and the refresh
## rate in use. Returns the scale for the next frame.
func advance(cpu_ms: float, gpu_ms: float, refresh_hz: float) -> float:
	if not table.enabled:
		scale = 1.0
		return scale
	var frame_ms: float = maxf(cpu_ms if is_finite(cpu_ms) else 0.0, gpu_ms if is_finite(gpu_ms) else 0.0)
	if not (refresh_hz > 0.0 and is_finite(refresh_hz)) or frame_ms <= 0.0:
		return scale
	frames_since_change += 1
	var share: float = frame_ms / (1000.0 / refresh_hz)
	if share > table.high_water:
		long_frames += 1
		headroom_frames = 0
	elif share < table.low_water:
		headroom_frames += 1
		long_frames = 0
	else:
		long_frames = 0
		headroom_frames = 0
	if frames_since_change < table.interval_frames:
		return scale
	if long_frames >= table.frames_down and scale > table.floor_scale:
		_change(maxf(table.floor_scale, scale - table.step))
	elif headroom_frames >= table.frames_up and scale < table.ceiling:
		_change(minf(table.ceiling, scale + table.step))
	return scale


func _change(to: float) -> void:
	# Rounded to thousandths by division, which lands on the same double as the
	# file's 0.7 or 1.0, so steps down and back up reach the bounds exactly.
	scale = clampf(roundf(to * 1000.0) / 1000.0, table.floor_scale, table.ceiling)
	long_frames = 0
	headroom_frames = 0
	frames_since_change = 0
