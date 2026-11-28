class_name FoveationKeepSpec
extends RefCounted

## The keep-or-revert timings, tones and pulses for a foveation change made in
## the dev menu (#1523, part 4 of #734; CMF-8, PRF-1, ARC-4), read from
## `res://xr/foveation_keep.json` so they can be tuned after a headset session.
##
## A rejected file is not a reason to drop the revert: the setting it guards
## can leave the picture unreadable. So a bad file keeps the built-in values
## (the shipped file's), and `error` names the field for the log.

const DEFAULT_FILE: String = "res://xr/foveation_keep.json"
const CUE_START: String = "start"
const CUE_KEPT: String = "kept"
const CUE_REVERTED: String = "reverted"
const CUES: Array[String] = [CUE_START, CUE_KEPT, CUE_REVERTED]

## Allowed ranges. The owner asked for the revert within 30 seconds (#734).
const KEEP_RANGE: Vector2 = Vector2(5.0, 30.0)
const HOLD_RANGE: Vector2 = Vector2(0.5, 3.0)
const TONE_RANGES: Dictionary[String, Vector2] = {
	"from_hz": Vector2(100.0, 2000.0),
	"to_hz": Vector2(100.0, 2000.0),
	"duration_s": Vector2(0.05, 1.0),
	"volume_db": Vector2(-30.0, 0.0),
}
const PULSE_RANGES: Dictionary[String, Vector2] = {
	"frequency_hz": Vector2(0.0, 500.0),
	"amplitude": Vector2(0.0, 1.0),
	"duration_s": Vector2(0.02, 0.5),
}
const BUILT_IN: Dictionary = {
	"keep_seconds": 15.0,
	"hold_seconds": 1.5,
	"tones": {
		CUE_START: {"from_hz": 220.0, "to_hz": 220.0, "duration_s": 0.18, "volume_db": -8.0},
		CUE_KEPT: {"from_hz": 440.0, "to_hz": 880.0, "duration_s": 0.3, "volume_db": -8.0},
		CUE_REVERTED: {"from_hz": 660.0, "to_hz": 220.0, "duration_s": 0.4, "volume_db": -8.0},
	},
	"pulses": {
		CUE_START: {"frequency_hz": 0.0, "amplitude": 0.4, "duration_s": 0.1},
		CUE_KEPT: {"frequency_hz": 0.0, "amplitude": 0.7, "duration_s": 0.25},
		CUE_REVERTED: {"frequency_hz": 0.0, "amplitude": 1.0, "duration_s": 0.4},
	},
}

## Seconds a new setting waits for the confirm before it reverts.
var keep_seconds: float = 15.0
## Seconds A must be held to keep it.
var hold_seconds: float = 1.5
## Cue name -> {from_hz, to_hz, duration_s, volume_db}.
var tones: Dictionary = {}
## Cue name -> {frequency_hz, amplitude, duration_s}.
var pulses: Dictionary = {}
## Why the file was rejected, or "" when it was read.
var error: String = ""


static func load_file(path: String = DEFAULT_FILE) -> FoveationKeepSpec:
	if not FileAccess.file_exists(path):
		return built_in("%s is missing" % path)
	return parse(FileAccess.get_file_as_string(path))


## The built-in values, with `reason` as the error ("" for none).
static func built_in(reason: String = "") -> FoveationKeepSpec:
	var spec: FoveationKeepSpec = FoveationKeepSpec.new()
	spec._take(BUILT_IN)
	spec.error = reason
	return spec


static func parse(text: String) -> FoveationKeepSpec:
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		return built_in("the file is not a JSON object")
	var problem: String = _check(data)
	if problem != "":
		return built_in(problem)
	var spec: FoveationKeepSpec = FoveationKeepSpec.new()
	spec._take(data)
	return spec


## The first field of `data` out of shape or range, named, or "".
static func _check(data: Dictionary) -> String:
	var problem: String = _number(data, "keep_seconds", KEEP_RANGE, "")
	if problem == "":
		problem = _number(data, "hold_seconds", HOLD_RANGE, "")
	for group: String in ["tones", "pulses"]:
		if problem != "":
			return problem
		var ranges: Dictionary[String, Vector2] = TONE_RANGES if group == "tones" else PULSE_RANGES
		var entries: Variant = data.get(group)
		if not entries is Dictionary:
			return "%s is missing or not an object" % group
		for cue: String in CUES:
			var entry: Variant = (entries as Dictionary).get(cue)
			if not entry is Dictionary:
				return "%s.%s is missing or not an object" % [group, cue]
			for field: String in ranges:
				problem = _number(entry, field, ranges[field], "%s.%s." % [group, cue])
				if problem != "":
					return problem
	return problem


static func _number(data: Dictionary, field: String, allowed: Vector2, prefix: String) -> String:
	var value: Variant = data.get(field)
	if not (value is float or value is int):
		return "%s%s is missing or not a number" % [prefix, field]
	if float(value) < allowed.x or float(value) > allowed.y:
		return "%s%s is %s, not %s to %s" % [prefix, field, value, allowed.x, allowed.y]
	return ""


func _take(data: Dictionary) -> void:
	keep_seconds = float(data["keep_seconds"])
	hold_seconds = float(data["hold_seconds"])
	tones = (data["tones"] as Dictionary).duplicate(true)
	pulses = (data["pulses"] as Dictionary).duplicate(true)
