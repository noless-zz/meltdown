class_name AimAssist
extends RefCounted

## The aim assist module (CMB-7, CMB-8, decision record 0010, #1096): a shot
## from a ship with the module fitted bends towards the nearest live robot
## whose centre lies within a small cone around where it was aimed and within
## range. Read from `data/aim/aim_assist.json`; core opens no files, so the
## caller hands the text to `parse_json` and the values to `Sim.set_aim_assist`.
##
## A new `AimAssist` holds the shipped values, so a `Sim` given none flies
## them, as with `LookAim`. Deterministic, no randomness (ARC-1, ARC-2): ties
## in distance go to the lower robot index. A ship without the module never
## reaches this code, so recorded runs keep their hashes.

## Largest angle, in degrees, between the aim and a robot's centre for the shot
## to bend towards it. Measured from the aim line, so a robot 3 degrees off is
## inside a 6-degree setting.
var cone_degrees: float = 6.0
## Farthest a robot's centre may be from the shot's origin, metres.
var range_m: float = 60.0

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = ["cone_degrees", "range_m"]
## Allowed range of each key, inclusive. Past 45 degrees the gun would aim
## itself; a cone of 0 turns the module off.
const RANGES: Dictionary = {
	"cone_degrees": [0.0, 45.0],
	"range_m": [1.0, 1000.0],
}

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of an aim assist data file: one JSON object holding every
## key of `KEYS` as a number and nothing else. On failure the returned value
## has `error` set, naming the key, and the values of `AimAssist.new()`.
static func parse_json(text: String) -> AimAssist:
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
	var assist: AimAssist = AimAssist.new()
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
		assist.set(key, number)
	return assist


## The direction a shot from `origin` aimed along `direction` (world space, any
## non-zero length) leaves in: towards the centre of the nearest live robot of
## `robots` inside the cone and range, or `direction` itself, unchanged, when
## there is none.
func bend(origin: Vector3, direction: Vector3, robots: Array[RobotState]) -> Vector3:
	if direction.is_zero_approx():
		return direction
	var aim: Vector3 = direction.normalized()
	var limit: float = deg_to_rad(cone_degrees)
	var best: int = -1
	var best_distance: float = INF
	for index: int in robots.size():
		var robot: RobotState = robots[index]
		if not robot.is_alive():
			continue
		var offset: Vector3 = robot.position - origin
		var distance: float = offset.length()
		if distance > range_m or distance < 0.0001 or distance >= best_distance:
			continue
		if aim.angle_to(offset) > limit:
			continue
		best = index
		best_distance = distance
	if best < 0:
		return direction
	return (robots[best].position - origin).normalized()


static func _rejected(message: String) -> AimAssist:
	var assist: AimAssist = AimAssist.new()
	assist.error = message
	return assist
