class_name RenderScaleSamples
extends RefCounted

## The scaler's last frames on the headset (#1509, GFX-7, PRF-2): each
## frame's CPU and GPU time as fed to the controller, the refresh interval
## and the scale the frame was drawn at. `RenderScaler.recent` keeps them so
## the m6 `render_scale` step can report what the scaler saw on the frames
## before it (the stress scene's) and fail when the scale sat at its floor
## while the frames had time to spare. Only `CAPACITY` frames are kept; the
## oldest goes first. View only (ARC-3).

const CAPACITY: int = 600
## A scale this close to another counts as the same (the controller rounds
## to thousandths).
const SAME_SCALE: float = 0.0005

var _cpu_ms: PackedFloat64Array = PackedFloat64Array()
var _gpu_ms: PackedFloat64Array = PackedFloat64Array()
var _budget_ms: PackedFloat64Array = PackedFloat64Array()
var _scales: PackedFloat64Array = PackedFloat64Array()
var _next: int = 0


## One frame. A frame with no usable rate is not kept.
func add(cpu_ms: float, gpu_ms: float, scale: float, refresh_hz: float) -> void:
	if not (refresh_hz > 0.0 and is_finite(refresh_hz)):
		return
	var values: Array[float] = [_finite(cpu_ms), _finite(gpu_ms), 1000.0 / refresh_hz, scale]
	if _scales.size() < CAPACITY:
		_cpu_ms.append(values[0])
		_gpu_ms.append(values[1])
		_budget_ms.append(values[2])
		_scales.append(values[3])
	else:
		_cpu_ms[_next] = values[0]
		_gpu_ms[_next] = values[1]
		_budget_ms[_next] = values[2]
		_scales[_next] = values[3]
	_next = (_next + 1) % CAPACITY


func count() -> int:
	return _scales.size()


func clear() -> void:
	_cpu_ms.clear()
	_gpu_ms.clear()
	_budget_ms.clear()
	_scales.clear()
	_next = 0


func mean_cpu_ms() -> float:
	return _mean(_cpu_ms)


func mean_gpu_ms() -> float:
	return _mean(_gpu_ms)


## The mean refresh interval, the frame budget.
func mean_budget_ms() -> float:
	return _mean(_budget_ms)


func min_scale() -> float:
	return Array(_scales).min() if count() > 0 else 1.0


func mean_scale() -> float:
	return _mean(_scales) if count() > 0 else 1.0


## Whether every kept frame was drawn at `scale`; false with none kept.
func all_at(scale: float) -> bool:
	if count() == 0:
		return false
	for drawn: float in _scales:
		if absf(drawn - scale) > SAME_SCALE:
			return false
	return true


static func _mean(values: PackedFloat64Array) -> float:
	if values.is_empty():
		return 0.0
	var total: float = 0.0
	for value: float in values:
		total += value
	return total / values.size()


static func _finite(value: float) -> float:
	return value if is_finite(value) and value > 0.0 else 0.0
