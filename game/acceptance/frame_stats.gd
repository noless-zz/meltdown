class_name FrameStats
extends RefCounted

## Frame time statistics against a refresh-rate budget (PRF-1 to PRF-3, #164).
##
## Pure arithmetic: whoever measures frames (the acceptance runner, the device
## workflow) only has to call `add` once per frame and then `check`. The
## threshold factor and the default allowed fraction come from BUDGET_PATH, so
## the pass mark can be tuned without code changes (ARC-4), and they are
## checked like `ShipTuning`: a bad file is reported, never silently replaced.
##
## Budget file format:
##
##     {"dropped_factor": 1.5, "max_dropped_fraction": 0.01}

const BUDGET_PATH: String = "res://acceptance/frame_budget.json"
const BUDGET_KEYS: Array[String] = ["dropped_factor", "max_dropped_fraction"]
## Passed to `check` to use the budget file's fraction (0.01 for PRF-3).
const USE_BUDGET: float = -1.0

var target_hz: float = 0.0
## A frame longer than this many target frame times counts as dropped.
var dropped_factor: float = 0.0
## The fraction of dropped frames `check` allows by default.
var max_dropped_fraction: float = 0.0
## Set when the target rate or the budget was rejected; `check` then fails
## with it, so a broken budget can never turn into a pass.
var error: String = ""

var _frames_ms: Array[float] = []
var _sum_ms: float = 0.0


func _init(p_target_hz: float, p_dropped_factor: float, p_max_dropped_fraction: float) -> void:
	target_hz = p_target_hz
	dropped_factor = p_dropped_factor
	max_dropped_fraction = p_max_dropped_fraction
	error = _budget_error()


## Statistics for `p_target_hz` with the factor and fraction read from `path`.
static func load_budget(p_target_hz: float, path: String = BUDGET_PATH) -> FrameStats:
	if not FileAccess.file_exists(path):
		return _failed(p_target_hz, "cannot open %s" % path)
	var stats: FrameStats = from_budget_json(p_target_hz, FileAccess.get_file_as_string(path))
	if stats.error != "":
		stats.error = "%s: %s" % [path, stats.error]
	return stats


## Statistics for `p_target_hz` with the factor and fraction parsed from the
## text of a budget file. Every key must be present, numeric and in range;
## unknown keys are rejected so a typo cannot switch the budget off.
static func from_budget_json(p_target_hz: float, text: String) -> FrameStats:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed(p_target_hz, "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed(p_target_hz, "top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not BUDGET_KEYS.has(key):
			return _failed(p_target_hz, "unknown key \"%s\"" % str(key))
	for key: String in BUDGET_KEYS:
		if not data.has(key):
			return _failed(p_target_hz, "missing key \"%s\"" % key)
		# A bool must not pass as 0 or 1.
		if typeof(data[key]) != TYPE_FLOAT and typeof(data[key]) != TYPE_INT:
			return _failed(p_target_hz, "key \"%s\" must be a number" % key)
	return FrameStats.new(p_target_hz, float(data["dropped_factor"]), float(data["max_dropped_fraction"]))


static func _failed(p_target_hz: float, message: String) -> FrameStats:
	var stats: FrameStats = FrameStats.new(p_target_hz, 0.0, 0.0)
	stats.error = message
	return stats


func _budget_error() -> String:
	if not target_hz > 0.0:
		return "target rate is %s Hz, must be above 0" % target_hz
	if not dropped_factor > 1.0:
		return "key \"dropped_factor\" is %s, must be above 1" % dropped_factor
	if not (max_dropped_fraction >= 0.0 and max_dropped_fraction <= 1.0):
		return "key \"max_dropped_fraction\" is %s, must be 0..1" % max_dropped_fraction
	return ""


## Records one frame's duration in seconds.
func add(frame_seconds: float) -> void:
	var ms: float = frame_seconds * 1000.0
	_frames_ms.append(ms)
	_sum_ms += ms


func count() -> int:
	return _frames_ms.size()


## The target frame time: 11.1 ms at 90 Hz (PRF-2).
func budget_ms() -> float:
	return 1000.0 / target_hz if target_hz > 0.0 else 0.0


## Frames longer than this count as dropped.
func dropped_threshold_ms() -> float:
	return budget_ms() * dropped_factor


func mean_ms() -> float:
	return _sum_ms / count() if count() > 0 else 0.0


## The 99th percentile by nearest rank: the smallest frame time that at least
## 99% of frames are no longer than. With fewer than 100 frames it is the max.
func p99_ms() -> float:
	if count() == 0:
		return 0.0
	var sorted: Array[float] = _frames_ms.duplicate()
	sorted.sort()
	var rank: int = ceili(0.99 * count())
	return sorted[clampi(rank, 1, count()) - 1]


func max_ms() -> float:
	return _frames_ms.max() if count() > 0 else 0.0


func dropped() -> int:
	var threshold: float = dropped_threshold_ms()
	var total: int = 0
	for ms: float in _frames_ms:
		if ms > threshold:
			total += 1
	return total


func dropped_fraction() -> float:
	return float(dropped()) / count() if count() > 0 else 0.0


## "" when the dropped fraction is within `max_dropped_fraction`, otherwise a
## message naming the measured and allowed values. USE_BUDGET takes the
## fraction from the budget file. No frames is a failure: it measured nothing.
func check(p_max_dropped_fraction: float = USE_BUDGET) -> String:
	if error != "":
		return error
	var allowed: float = max_dropped_fraction if p_max_dropped_fraction == USE_BUDGET else p_max_dropped_fraction
	if not (allowed >= 0.0 and allowed <= 1.0):
		return "allowed dropped fraction is %s, must be 0..1" % allowed
	if count() == 0:
		return "no frame times were recorded"
	if dropped_fraction() > allowed:
		return "dropped %s of frames (%d of %d over %.2f ms at %s Hz), allowed %s" % [
			_percent(dropped_fraction()), dropped(), count(), dropped_threshold_ms(), target_hz, _percent(allowed)]
	return ""


## The numbers in the shape `AcceptanceReport.add_step` stores, times rounded
## to 0.01 ms so two runs' reports differ only where the frames did.
func to_measurements() -> Dictionary:
	return {
		"target_hz": target_hz,
		"frame_count": count(),
		"budget_ms": snappedf(budget_ms(), 0.01),
		"dropped_threshold_ms": snappedf(dropped_threshold_ms(), 0.01),
		"mean_ms": snappedf(mean_ms(), 0.01),
		"p99_ms": snappedf(p99_ms(), 0.01),
		"max_ms": snappedf(max_ms(), 0.01),
		"dropped": dropped(),
		"dropped_fraction": snappedf(dropped_fraction(), 0.0001),
	}


## 0.011 as "1.1%": one decimal is enough to tell a 1% budget apart.
static func _percent(fraction: float) -> String:
	return "%s%%" % snappedf(fraction * 100.0, 0.1)
