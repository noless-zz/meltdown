class_name WeaponDef
extends RefCounted

## One weapon, read from a text data file so that weapons are data, not code
## branches (ARC-4). Parsed like `ShipTuning`: the caller reads the file and
## hands its text to `parse_json`, because core never opens files.
##
## Each field below is one key of the data file, with the same name and unit.

## Ticks between two shots while the trigger is held, whole ticks, 1..600.
## A whole number of ticks keeps the fire rate exact on the fixed tick (ARC-2).
var fire_interval_ticks: int = 10
## Speed of each projectile, metres per second, 1..1000.
var projectile_speed: float = 120.0
## How long a projectile flies before it expires, seconds, 0.05..30.
var lifetime: float = 1.5
## Damage one projectile deals on a hit, damage points, 0..10000.
var damage: float = 8.0
## Energy spent per shot, energy units, 0..1000. A shot is refused while the
## ship has less than this.
var energy_cost: float = 2.0

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = [
	"fire_interval_ticks", "projectile_speed", "lifetime", "damage", "energy_cost",
]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in step
## with the ranges written on the fields above.
const RANGES: Dictionary = {
	"fire_interval_ticks": [1.0, 600.0],
	"projectile_speed": [1.0, 1000.0],
	"lifetime": [0.05, 30.0],
	"damage": [0.0, 10000.0],
	"energy_cost": [0.0, 1000.0],
}

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a weapon data file: one JSON object holding every key in
## `KEYS` as a number, and nothing else. A missing key is an error rather than
## a silent default, so a typo cannot leave a value untuned. On failure the
## returned weapon has `error` set, naming the field, and default values.
static func parse_json(text: String) -> WeaponDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _failed("unknown key \"%s\"" % str(key))
	var weapon: WeaponDef = WeaponDef.new()
	for key: String in KEYS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# JSON numbers arrive as floats. A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _failed("key \"%s\" must be a number" % key)
		var number: float = float(value)
		var low: float = RANGES[key][0]
		var high: float = RANGES[key][1]
		if number < low:
			return _failed("key \"%s\" is %s, must be at least %s" % [key, number, low])
		if number > high:
			return _failed("key \"%s\" is %s, must be at most %s" % [key, number, high])
		if key == "fire_interval_ticks":
			if number != floorf(number):
				return _failed("key \"%s\" is %s, must be a whole number" % [key, number])
			weapon.fire_interval_ticks = int(number)
		else:
			weapon.set(key, number)
	return weapon


## Ticks a projectile of this weapon lives, never fewer than one.
func lifetime_ticks() -> int:
	return maxi(roundi(lifetime * ShipState.TICK_RATE), 1)


## Hash of the values, so a ship's state hash changes with what it carries.
func values_hash() -> int:
	return hash([fire_interval_ticks, projectile_speed, lifetime, damage, energy_cost])


static func _failed(message: String) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.error = message
	return weapon
