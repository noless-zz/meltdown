class_name AcceptanceRenderScaleStats
extends RefCounted

## The render scale over a frame budget step's measured frames (#1417, GFX-7,
## PRF-2, PRF-3): its minimum, its mean and how many frames were drawn below
## the full 1.0. `AcceptanceFrameBudgetCheck` samples `RenderScaler.in_use`
## on the same frames it times, so the m6 `stress_scene` step reports the
## scale beside its frame times. Reported only, never judged: the frame times
## are the pass mark, and a lowered scale is how they are kept.

## Below this a frame counts as drawn below the full resolution.
const FULL: float = 1.0 - 0.0005

var frames: int = 0
var minimum: float = 1.0
var below_full: int = 0
var _sum: float = 0.0


func add(scale: float) -> void:
	frames += 1
	_sum += scale
	minimum = minf(minimum, scale)
	if scale < FULL:
		below_full += 1


func mean() -> float:
	return _sum / frames if frames > 0 else 1.0


## The numbers under the keys a step's report lists.
func to_measurements() -> Dictionary:
	return {"render_scale_min": snappedf(minimum, 0.001), "render_scale_mean": snappedf(mean(), 0.001),
		"render_scale_frames_below_full": below_full}


## One line for the step's message.
func summary() -> String:
	return "render scale min %.2f, mean %.2f, %d of %d frames below 1.0" % [minimum, mean(), below_full, frames]
