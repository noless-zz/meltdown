class_name RobotDef
extends RefCounted

## One robot type, read from a text data file so that robots are data, not code
## branches (ARC-4, CMB-3). Parsed like `WeaponDef`: the caller reads the file
## and hands its text to `parse_json`, because core never opens files.
##
## Each field below is one key of the data file, with the same name and unit.

## Name of the type; matches the data file's name without `.json`. Lower case
## letters, digits and underscores, 1..64 characters, so it is also a safe path.
var id: String = ""
## Hull at spawn, hull points, 1..10000. Same unit as the ship's `max_hull`.
var hull: float = 20.0
## Collision radius, metres, 0.1..10. Same unit as the ship's `radius`.
var radius: float = 1.0
## Top speed, metres per second, 0..200. Zero is allowed for a fixed turret.
var max_speed: float = 8.0
## Acceleration towards `max_speed`, metres per second squared, 0..1000.
var acceleration: float = 16.0
## Fastest turn, degrees per second, 1..1440. Degrees keep the data readable;
## the simulation converts once when it reads the definition.
var turn_rate: float = 90.0
## Named movement behaviour, one of `MOVEMENTS`. The simulation maps each name
## to a behaviour, so a new type needs no new code unless it needs a new name.
var movement: String = "hover"
## Id of the weapon it fires: a file `<weapon>.json` in `WEAPONS_DIR`.
var weapon: String = ""
## Id of the weapon or part it drops when destroyed (SLV-1).
var salvage: String = ""

## Optional movement tuning. A file may leave any of these out and gets the
## default, so the shipped robots keep today's behaviour (CMB-3, #242). The
## defaults match the constants `RobotState` used before these keys existed.

## Chase stand-off as a multiple of the robot's own radius, 1..50: a chaser
## stops this many radii, plus the ship's radius, from the ship's centre.
var standoff_radii: float = 4.0
## Near edge of the band a strafer holds from its target's centre, metres,
## 0..500. Must not exceed `strafe_max_distance`.
var strafe_min_distance: float = 10.0
## Far edge of the strafe band, metres, 0..500.
var strafe_max_distance: float = 20.0
## How hard a strafer pulls back to the middle of its band, metres per second
## of radial speed per metre off the middle, 0..10.
var strafe_radial_gain: float = 0.5

## Movement behaviours the simulation knows:
## hover: hold position near its spawn, turning to face the target.
## chase: close in on the target.
## strafe: keep its distance and circle the target sideways.
const MOVEMENTS: Array[String] = ["hover", "chase", "strafe"]

## Folder holding weapon data files, for resolving `weapon` and `salvage`.
const WEAPONS_DIR: String = "res://data/weapons"

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = [
	"id", "hull", "radius", "max_speed", "acceleration", "turn_rate",
	"movement", "weapon", "salvage",
]

## Keys a file may leave out; each falls back to its field's default above.
const OPTIONAL_KEYS: Array[String] = [
	"standoff_radii", "strafe_min_distance", "strafe_max_distance", "strafe_radial_gain",
]

## Keys whose value is an id string rather than a number.
const ID_KEYS: Array[String] = ["id", "weapon", "salvage"]

## Allowed range of each number key, inclusive: [minimum, maximum]. Keep these
## in step with the ranges written on the fields above.
const RANGES: Dictionary = {
	"hull": [1.0, 10000.0],
	"radius": [0.1, 10.0],
	"max_speed": [0.0, 200.0],
	"acceleration": [0.0, 1000.0],
	"turn_rate": [1.0, 1440.0],
	"standoff_radii": [1.0, 50.0],
	"strafe_min_distance": [0.0, 500.0],
	"strafe_max_distance": [0.0, 500.0],
	"strafe_radial_gain": [0.0, 10.0],
}

const ID_MAX_LENGTH: int = 64

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a robot data file: one JSON object holding every key in
## `KEYS`, any of `OPTIONAL_KEYS`, and nothing else. A missing required key is
## an error rather than a silent default, so a typo cannot leave a robot
## untuned; an unknown key is an error too, so a misspelt optional key is
## caught instead of quietly falling back to its default. On failure the returned
## robot has `error` set, naming the field, and default values.
static func parse_json(text: String) -> RobotDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return _failed("unknown key \"%s\"" % str(key))
	var robot: RobotDef = RobotDef.new()
	for key: String in KEYS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
		var value: Variant = data[key]
		var message: String = ""
		if key == "movement":
			message = _check_movement(value)
		elif ID_KEYS.has(key):
			message = _check_id(key, value)
		else:
			message = _check_number(key, value)
		if message != "":
			return _failed(message)
		if typeof(value) == TYPE_STRING:
			robot.set(key, value)
		else:
			robot.set(key, float(value))
	for key: String in OPTIONAL_KEYS:
		if not data.has(key):
			continue
		var message: String = _check_number(key, data[key])
		if message != "":
			return _failed(message)
		robot.set(key, float(data[key]))
	if robot.strafe_min_distance > robot.strafe_max_distance:
		return _failed("key \"strafe_min_distance\" is %s, must not exceed \"strafe_max_distance\" %s" % [robot.strafe_min_distance, robot.strafe_max_distance])
	return robot


## Path of the weapon data file this robot fires; the caller reads it and
## parses it with `WeaponDef.parse_json`.
func weapon_path() -> String:
	return "%s/%s.json" % [WEAPONS_DIR, weapon]


## Hash of the values, so a replay can record which robot data it ran with.
func values_hash() -> int:
	return hash([id, hull, radius, max_speed, acceleration, turn_rate, movement, weapon, salvage,
		standoff_radii, strafe_min_distance, strafe_max_distance, strafe_radial_gain])


static func _check_number(key: String, value: Variant) -> String:
	# JSON numbers arrive as floats. A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "key \"%s\" must be a number" % key
	var number: float = float(value)
	var low: float = RANGES[key][0]
	var high: float = RANGES[key][1]
	if number < low:
		return "key \"%s\" is %s, must be at least %s" % [key, number, low]
	if number > high:
		return "key \"%s\" is %s, must be at most %s" % [key, number, high]
	return ""


static func _check_id(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"%s\" must be a string" % key
	var text: String = value
	if text.is_empty() or text.length() > ID_MAX_LENGTH:
		return "key \"%s\" must be 1 to %d characters" % [key, ID_MAX_LENGTH]
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return "key \"%s\" is \"%s\", must use only a-z, 0-9 and _" % [key, text]
	return ""


static func _check_movement(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"movement\" must be a string"
	if not MOVEMENTS.has(value):
		return "key \"movement\" is \"%s\", must be one of %s" % [value, ", ".join(PackedStringArray(MOVEMENTS))]
	return ""


static func _failed(message: String) -> RobotDef:
	var robot: RobotDef = RobotDef.new()
	robot.error = message
	return robot
