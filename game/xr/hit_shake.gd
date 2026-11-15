class_name HitShake
extends RefCounted

## The "Hits" row of the comfort table (CMF-1) as a view effect: preset 1 no
## cockpit shake, 2 a light shake, 3 the full shake, 4 the full shake and a
## spin. Fed the simulation's events and the frame time, it answers the view
## offset for the frame; the rig applies it on top of the ship's pose.
##
## It only reads `SimEvent`s, so a preset changes what the player sees and
## never what the ship does (ARC-3, CMF-6). Preset 1 has `hit_shake` 0 and
## always answers the identity, so a hit never moves its view at all (CMF-3).
##
## The caps, decay time and frequency are guesses for the G1 headset session
## and live in `res://xr/hit_shake.json` so the owner can change them.

const DEFAULT_FILE: String = "res://xr/hit_shake.json"

## Largest shake translation at full strength, metres, 0..0.05. Small, so the
## eye never leaves the cockpit frame.
var max_offset_m: float = 0.02
## Largest spin roll at full strength, degrees, 0..30.
var max_roll_deg: float = 6.0
## Time for a full-strength hit to fade to nothing, seconds, 0.05..2.
var decay_s: float = 0.4
## Impact speed that gives a full-strength hit, metres per second, 1..60.
## Faster impacts are capped there.
var full_impact_speed_m_per_s: float = 15.0
## How fast the shake wobbles, hertz, 1..40.
var shake_frequency_hz: float = 18.0

## Every key of the data file, with the same name as the field it sets.
const KEYS: Array[String] = [
	"max_offset_m", "max_roll_deg", "decay_s", "full_impact_speed_m_per_s",
	"shake_frequency_hz",
]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in
## step with the ranges written on the fields above.
const RANGES: Dictionary[String, Array] = {
	"max_offset_m": [0.0, 0.05],
	"max_roll_deg": [0.0, 30.0],
	"decay_s": [0.05, 2.0],
	"full_impact_speed_m_per_s": [1.0, 60.0],
	"shake_frequency_hz": [1.0, 40.0],
}

## Set when the text was rejected; empty otherwise.
var error: String = ""
## The preset whose "Hits" row is shown; null shows nothing.
var preset: ComfortPreset = null

## Strength of the hit being shown, 0..1; falls linearly to 0 over `decay_s`.
var _strength: float = 0.0
## Roll direction of the current hit: +1 or -1.
var _roll_sign: float = 1.0
## Time since the effect was created, seconds; drives the wobble.
var _phase_s: float = 0.0


## Parses the text of a hit-shake data file: one JSON object holding every key
## in `KEYS` as a number in its range, and nothing else. On failure the
## returned shake has `error` set, naming the field, and default values.
static func parse_json(text: String) -> HitShake:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var shake: HitShake = HitShake.new()
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
		shake.set(key, float(value))
	return shake


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> HitShake:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var shake: HitShake = parse_json(FileAccess.get_file_as_string(path))
	if shake.error != "":
		shake.error = "%s: %s" % [path, shake.error]
	return shake


## Takes in one tick's events. Only wall impacts on `ship` (this player's
## ship) count; a stronger hit replaces a weaker one still fading, and hits
## never add up past full strength, so a burst stays within the caps.
func feed(events: Array[SimEvent], ship: int) -> void:
	for event: SimEvent in events:
		if event == null or event.ship != ship or event.kind != SimEvent.Kind.WALL_IMPACT:
			continue
		if not event.magnitude > 0.0:
			continue
		var strength: float = minf(event.magnitude / full_impact_speed_m_per_s, 1.0)
		if strength >= _strength:
			_strength = strength
			# A hit from the right rolls the view left and the other way round.
			_roll_sign = -1.0 if event.vector.x > 0.0 else 1.0


## Advances the effect by `delta` seconds and returns the view offset for the
## frame, in the cockpit's own frame. The identity when nothing shows.
func advance(delta: float) -> Transform3D:
	if delta > 0.0:
		_phase_s += delta
		_strength = maxf(_strength - delta / decay_s, 0.0)
	return offset()


## The view offset for the current state, without advancing time.
func offset() -> Transform3D:
	if preset == null or _strength <= 0.0:
		return Transform3D.IDENTITY
	var amount: float = clampf(preset.hit_shake, 0.0, 1.0) * _strength
	if amount <= 0.0:
		return Transform3D.IDENTITY
	var turn: float = TAU * shake_frequency_hz * _phase_s
	# Three unrelated frequencies keep the wobble from tracing a visible pattern.
	var wobble: Vector3 = Vector3(sin(turn), sin(turn * 1.31 + 1.7), sin(turn * 0.73 + 4.1))
	var origin: Vector3 = (wobble * max_offset_m * amount).limit_length(max_offset_m * amount)
	var basis: Basis = Basis.IDENTITY
	# Only `hit_spin` rolls the view, and `ComfortPreset.has_smooth_rotation`
	# counts it, so a preset that must stay free of smooth rotation (CMF-3)
	# cannot turn the spin on unnoticed.
	if preset.hit_spin and max_roll_deg > 0.0:
		basis = Basis(Vector3.FORWARD, _roll_sign * deg_to_rad(max_roll_deg) * amount)
	return Transform3D(basis, origin)


## Strength of the hit being shown, 0..1, before the preset scales it.
func strength() -> float:
	return _strength


static func _rejected(message: String) -> HitShake:
	var shake: HitShake = HitShake.new()
	shake.error = message
	return shake
