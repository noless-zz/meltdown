class_name InertiaDrift
extends RefCounted

## The "with inertia drift" part of preset 4's acceleration feel (CMF-1,
## #840): when the ship's velocity changes suddenly, the eye lags behind it
## inside the cockpit by a few centimetres, then settles back.
##
## Fed copies of the ship's velocity and orientation once a frame, it answers
## a translation in the cockpit's own frame, opposite to the change. It never
## rotates the view, so it adds no smooth rotation to any preset (CMF-3), and
## it reads ship state only, so it cannot change what the ship does (CMF-6,
## ARC-3, MP-2). Presets without `inertia_drift` always get the identity.
##
## The values are guesses for the gate #56 headset session and live in
## `res://xr/inertia_drift.json` so the owner can tune them.

const DEFAULT_FILE: String = "res://xr/inertia_drift.json"
## The largest offset any file may ask for, metres. Well inside
## `HeadRecentre.HEAD_REACH`, the lean the ship's radius already leaves room
## for, so the near plane never reaches a wall the ship touches.
const OFFSET_CEILING_M: float = 0.1

## Metres the eye lags per metre per second of velocity change, 0..0.02.
var lag_m_per_m_per_s: float = 0.002
## Time for the largest offset to settle back to nothing, seconds, 0.05..2.
## A smaller offset settles sooner: the return runs at a steady speed.
var settle_s: float = 0.5
## Largest offset, metres, 0..`OFFSET_CEILING_M`.
var max_offset_m: float = 0.04

## Every key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = ["lag_m_per_m_per_s", "settle_s", "max_offset_m"]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in
## step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"lag_m_per_m_per_s": [0.0, 0.02],
	"settle_s": [0.05, 2.0],
	"max_offset_m": [0.0, OFFSET_CEILING_M],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""

## The current offset, in the cockpit's frame.
var _offset: Vector3 = Vector3.ZERO
## The velocity of the previous sample, in world space.
var _last_velocity: Vector3 = Vector3.ZERO
## False until the first sample, which has nothing to compare with.
var _has_velocity: bool = false
## The preset of the previous `advance`; a different one drops the offset.
var _preset: ComfortPreset = null


## Parses the text of a drift data file: one JSON object holding every key in
## `KEYS` as a number in its range, and nothing else. On failure the returned
## drift has `error` set, naming the field, and default values.
static func parse_json(text: String) -> InertiaDrift:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var drift: InertiaDrift = InertiaDrift.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if float(value) < low or float(value) > high:
			return _rejected("key \"%s\" is %s, must be within %s..%s" % [key, value, low, high])
		drift.set(key, float(value))
	return drift


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> InertiaDrift:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var drift: InertiaDrift = parse_json(FileAccess.get_file_as_string(path))
	if drift.error != "":
		drift.error = "%s: %s" % [path, drift.error]
	return drift


## Moves the drift on by `delta` seconds for `preset`, given the ship's
## `velocity` and `orientation` now, and returns the offset for the frame.
## A change of preset drops any offset at once. With `delta` 0 (a paused
## frame) nothing moves; a velocity change seen then is not shown later.
func advance(preset: ComfortPreset, velocity: Vector3, orientation: Basis, delta: float) -> Transform3D:
	if preset != _preset:
		_preset = preset
		_offset = Vector3.ZERO
	var change: Vector3 = velocity - _last_velocity if _has_velocity else Vector3.ZERO
	_last_velocity = velocity
	_has_velocity = true
	if preset == null or not preset.inertia_drift or delta <= 0.0:
		if preset == null or not preset.inertia_drift:
			_offset = Vector3.ZERO
		return offset()
	# Settle first, then add this frame's change, so a sudden change shows in full.
	_offset = _offset.move_toward(Vector3.ZERO, max_offset_m / settle_s * delta)
	var local_change: Vector3 = orientation.orthonormalized().transposed() * change
	_offset = (_offset - local_change * lag_m_per_m_per_s).limit_length(max_offset_m)
	return offset()


## The offset for the current state: a translation only.
func offset() -> Transform3D:
	return Transform3D(Basis.IDENTITY, _offset)


static func _rejected(message: String) -> InertiaDrift:
	var drift: InertiaDrift = InertiaDrift.new()
	drift.error = message
	return drift
