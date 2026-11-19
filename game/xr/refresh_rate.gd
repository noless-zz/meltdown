class_name RefreshRate
extends RefCounted

## Asks the headset for the active comfort preset's refresh rate and reports
## the rate actually in use (#598, CMF-1, PRF-1, GFX-1). View side only: the
## simulation keeps its fixed 60 Hz tick whatever the display runs at (ARC-3).
##
## The rate is chosen when the XR session begins and again on every preset
## change. The rate in use is never the value just requested: on the Quest 3
## `display_refresh_rate` read back 90.0 while the display ran at 72. It is
## taken from the runtime's `refresh_rate_changed` event, or, when no event
## comes (the rate did not change), read back `READ_BACK_FRAMES` later.

const LOG_PREFIX: String = "Meltdown: refresh rate"
## Rates above this need a preset with `allow_120_hz` (CMF-1).
const STANDARD_MAX_HZ: float = 90.0
## How far apart two rates may be and still count as the same; runtimes may
## report 72.00001 for 72.
const SAME_RATE_HZ: float = 0.5
## About one second at 72 Hz: long enough for the runtime to switch.
const READ_BACK_FRAMES: int = 72
const UNKNOWN: float = 0.0

## The rate asked for at the last choice, or UNKNOWN when none was asked for.
var requested_hz: float = UNKNOWN
## The rates the runtime offered at the last choice.
var offered: Array[float] = []
## The rate the display runs at, or UNKNOWN until it has been read back.
var in_use_hz: float = UNKNOWN
## Every line logged, so tests can read them.
var lines: PackedStringArray = PackedStringArray()

## The OpenXR interface, or a test's stand-in with the same members; null
## until the session begins.
var _runtime: Object = null
## Frames until the read-back; below 0 when none is pending.
var _frames_left: int = -1


## The rate a preset asks for: its `refresh_rate_hz`, held to
## `STANDARD_MAX_HZ` unless it allows 120 Hz.
static func target_hz(preset: ComfortPreset) -> float:
	var target: float = float(preset.refresh_rate_hz)
	if target > STANDARD_MAX_HZ and not preset.allow_120_hz:
		target = STANDARD_MAX_HZ
	return target


## The offered rate to ask for: the preset's rate if offered, otherwise the
## highest offered below it; UNKNOWN when nothing offered is at or below it.
static func choose(offered_rates: Array, preset: ComfortPreset) -> float:
	var target: float = target_hz(preset)
	var best: float = UNKNOWN
	for value: Variant in offered_rates:
		var rate: float = float(value)
		if absf(rate - target) < SAME_RATE_HZ:
			return rate
		if rate < target and rate > best:
			best = rate
	return best


## Called when the XR session begins with the OpenXR interface.
func begin(runtime: Object, preset: ComfortPreset) -> void:
	_runtime = runtime
	if runtime.has_signal("refresh_rate_changed") \
			and not runtime.is_connected("refresh_rate_changed", on_runtime_changed):
		runtime.connect("refresh_rate_changed", on_runtime_changed)
	apply(preset)


## Asks for `preset`'s rate; does nothing before the session has begun.
func apply(preset: ComfortPreset) -> void:
	if _runtime == null:
		return
	offered.clear()
	for value: Variant in _runtime.call("get_available_display_refresh_rates"):
		offered.append(float(value))
	requested_hz = choose(offered, preset)
	if requested_hz != UNKNOWN:
		_runtime.set("display_refresh_rate", requested_hz)
	_frames_left = READ_BACK_FRAMES


## The runtime says the display now runs at `rate`.
func on_runtime_changed(rate: float) -> void:
	_frames_left = -1
	_settle(rate)


## One rendered frame; reads the rate back when no change event came in time.
func advance_frame() -> void:
	if _frames_left < 0 or _runtime == null:
		return
	_frames_left -= 1
	if _frames_left <= 0:
		_frames_left = -1
		_settle(float(_runtime.get("display_refresh_rate")))


## Whether the rate in use is known and no choice is waiting to be read back.
func settled() -> bool:
	return _frames_left < 0 and in_use_hz != UNKNOWN


## The text the status panel shows beside the build line: nothing without a
## headset session, "? Hz" until the rate in use is known.
func panel_text() -> String:
	if _runtime == null:
		return ""
	return "? Hz" if in_use_hz == UNKNOWN else "%d Hz" % roundi(in_use_hz)


## `build` with the rate in use beside it, when there is one.
func beside(build: String) -> String:
	var rate: String = panel_text()
	return build if rate == "" else "%s  %s" % [build, rate]


static func format_line(requested: float, offered_rates: Array[float], in_use: float) -> String:
	var asked: String = "none" if requested == UNKNOWN else "%s Hz" % requested
	return "%s requested %s, offered %s, in use %s Hz" % [LOG_PREFIX, asked, offered_rates, in_use]


func _settle(rate: float) -> void:
	in_use_hz = rate
	var line: String = format_line(requested_hz, offered, in_use_hz)
	lines.append(line)
	print(line)
