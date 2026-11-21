class_name LookAim
extends RefCounted

## How far and how fast a ship's guns follow the aim the pilot asks for
## (CMB-6, decision record 0010): within a cone around the nose, turning at a
## gimbal rate. Read from `data/aim/look_aim.json`; core opens no files, so the
## caller hands the text to `parse_json` and the values to `Sim.set_look_aim`.
## The same values serve every way a pilot has look-aim, with or without a
## module, so no preset aims better than another (CMF-6).
##
## A new `LookAim` holds the shipped values, so a `Sim` given none, and a replay
## without an aim line, flies them. A ship whose aim stays on the nose never
## turns its guns, so runs recorded before look-aim keep their hashes whatever
## these values are.

## Full width of the cone around the nose the guns may point into, degrees.
var cone_degrees: float = 35.0
## Fastest the guns turn towards the aim, degrees per second.
var gimbal_degrees_per_second: float = 180.0

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = ["cone_degrees", "gimbal_degrees_per_second"]
## Allowed range of each key, inclusive. A cone of 0 keeps the guns on the
## nose; 180 degrees would let the guns fire backwards along the hull.
const RANGES: Dictionary = {
	"cone_degrees": [0.0, 170.0],
	"gimbal_degrees_per_second": [1.0, 3600.0],
}
## The guns' rest direction in ship space: along the nose (-z).
const NOSE: Vector3 = Vector3(0.0, 0.0, -1.0)

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a look-aim data file: one JSON object holding every key
## of `KEYS` as a number and nothing else. A missing or unknown key is an
## error, so a typo cannot leave a value untuned unnoticed. On failure the
## returned value has `error` set, naming the key, and the values of
## `LookAim.new()`.
static func parse_json(text: String) -> LookAim:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(),
			json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	var aim: LookAim = LookAim.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		var number: float = float(value)
		if number < RANGES[key][0] or number > RANGES[key][1]:
			return _rejected("key \"%s\" is %s, must be %s to %s" % [key, number,
				RANGES[key][0], RANGES[key][1]])
		aim.set(key, number)
	return aim


## One-line JSON holding every key at full precision, so the values read back
## are exactly these.
func to_json() -> String:
	var data: Dictionary = {}
	for key: String in KEYS:
		data[key] = get(key)
	return JSON.stringify(data, "", false, true)


func values_hash() -> int:
	return hash([cone_degrees, gimbal_degrees_per_second])


## Where `aim` (ship space, any length) lands once kept inside the cone: the
## aim itself inside it, otherwise the cone's edge in the aim's direction. A
## zero aim, or one straight behind with no direction to lean, is the nose.
func clamp_to_cone(aim: Vector3) -> Vector3:
	if aim.is_zero_approx():
		return NOSE
	var unit: Vector3 = aim.normalized()
	var half: float = deg_to_rad(cone_degrees) * 0.5
	if NOSE.angle_to(unit) <= half:
		return unit
	var axis: Vector3 = NOSE.cross(unit)
	if axis.is_zero_approx():
		return NOSE
	return NOSE.rotated(axis.normalized(), half)


## Turns `ship`'s guns one tick towards `aim`, kept inside the cone, by at
## most the gimbal rate. Reaching the target sets it exactly, so a gun sent
## back to the nose rests exactly on it and leaves the hash as it was. A
## destroyed ship's guns stay where they are, like the rest of it.
func turn_gun(ship: ShipState, aim: Vector3) -> void:
	if ship.is_destroyed():
		return
	var target: Vector3 = clamp_to_cone(aim)
	if ship.gun_direction == target:
		return
	var angle: float = ship.gun_direction.angle_to(target)
	var step: float = deg_to_rad(gimbal_degrees_per_second) * ShipState.TICK_DT
	if angle <= step:
		ship.gun_direction = target
		return
	var axis: Vector3 = ship.gun_direction.cross(target)
	if axis.is_zero_approx():
		# Exactly opposite: lean over the top. The cone is under 180 degrees,
		# so this only happens on the way back from its far edge.
		axis = Vector3.RIGHT
	ship.gun_direction = ship.gun_direction.rotated(axis.normalized(), step).normalized()


static func _rejected(message: String) -> LookAim:
	var aim: LookAim = LookAim.new()
	aim.error = message
	return aim
