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

## Optional burst keys (#612, CMB-3). A file may leave any of them out and gets
## the default, which fires one shot every `fire_interval_ticks` as before, so
## weapons without them keep their behaviour and hashes. Robots read them
## (`RobotState.fire_at`); a ship's trigger ignores them.

## Shots in one burst, whole shots, 1..100, `fire_interval_ticks` apart.
var burst_shots: int = 1
## Ticks from the last shot of a burst to the next burst, whole ticks, 0..600.
## Never shorter than `fire_interval_ticks`; 0 means exactly that.
var burst_pause_ticks: int = 0
## Ticks a robot spends winding up, holding its aim, before the first shot of
## each burst, whole ticks, 0..600. The view can show it (#604), so the pilot
## has a window to dodge or shoot first.
var windup_ticks: int = 0

## Optional flag (#1105, SLV-1, SLV-2): true for a weapon that is only ever
## crafted, never dropped by a robot. Such a weapon stays out of the salvage
## catalogue (`SpawnLoader.parts_from_files`), whose contents `SimHash` hashes,
## so adding a crafted weapon file moves no session's hash. Not part of
## `values_hash`: it says where the weapon comes from, not how it fires.
var crafted_only: bool = false

## Optional (#1210, PLT-2): the name a pilot reads on the status panel, 1..24
## characters. Not part of `values_hash` and never read by the simulation, so
## naming a weapon moves no hash; "" when the file names none.
var name: String = ""

## Every key of the data file, in the order the file lists them.
const KEYS: Array[String] = [
	"fire_interval_ticks", "projectile_speed", "lifetime", "damage", "energy_cost",
]

## Keys a file may leave out; each falls back to its field's default above.
const OPTIONAL_KEYS: Array[String] = ["burst_shots", "burst_pause_ticks", "windup_ticks"]

## Optional keys read as booleans rather than numbers; each defaults to false.
const FLAG_KEYS: Array[String] = ["crafted_only"]

## Optional keys read as text; each defaults to "".
const TEXT_KEYS: Array[String] = ["name"]
## The longest name the panel's row is laid out for.
const MAX_NAME_LENGTH: int = 24

## Keys read as whole numbers.
const WHOLE_KEYS: Array[String] = [
	"fire_interval_ticks", "burst_shots", "burst_pause_ticks", "windup_ticks",
]

## Allowed range of each key, inclusive: [minimum, maximum]. Keep these in step
## with the ranges written on the fields above.
const RANGES: Dictionary = {
	"fire_interval_ticks": [1.0, 600.0],
	"projectile_speed": [1.0, 1000.0],
	"lifetime": [0.05, 30.0],
	"damage": [0.0, 10000.0],
	"energy_cost": [0.0, 1000.0],
	"burst_shots": [1.0, 100.0],
	"burst_pause_ticks": [0.0, 600.0],
	"windup_ticks": [0.0, 600.0],
}

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a weapon data file: one JSON object holding every key in
## `KEYS` as a number, any of `OPTIONAL_KEYS`, any of `FLAG_KEYS` as a
## boolean, any of `TEXT_KEYS` as text, and nothing else. A missing
## required key is an error rather than a silent default, so a typo cannot
## leave a value untuned. On failure the
## returned weapon has `error` set, naming the field, and default values.
static func parse_json(text: String) -> WeaponDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_KEYS.has(key)
				or FLAG_KEYS.has(key) or TEXT_KEYS.has(key)):
			return _failed("unknown key \"%s\"" % str(key))
	var weapon: WeaponDef = WeaponDef.new()
	for key: String in FLAG_KEYS:
		if data.has(key):
			if typeof(data[key]) != TYPE_BOOL:
				return _failed("key \"%s\" must be true or false" % key)
			weapon.set(key, data[key])
	for key: String in TEXT_KEYS:
		if data.has(key):
			if typeof(data[key]) != TYPE_STRING or String(data[key]).strip_edges().is_empty() \
					or String(data[key]).length() > MAX_NAME_LENGTH:
				return _failed("key \"%s\" must be text of 1 to %d characters" % [key, MAX_NAME_LENGTH])
			weapon.set(key, String(data[key]).strip_edges())
	for key: String in KEYS + OPTIONAL_KEYS:
		if not data.has(key):
			if OPTIONAL_KEYS.has(key):
				continue
			return _failed("missing key \"%s\"" % key)
		var message: String = _set_number(weapon, key, data[key])
		if message != "":
			return _failed(message)
	return weapon


## Ticks a projectile of this weapon lives, never fewer than one.
func lifetime_ticks() -> int:
	return maxi(roundi(lifetime * ShipState.TICK_RATE), 1)


## True when any burst key differs from its default, so the weapon fires in
## bursts or winds up rather than one shot per interval.
func has_bursts() -> bool:
	return burst_shots != 1 or burst_pause_ticks != 0 or windup_ticks != 0


## Ticks from the last shot of a burst to the next burst's wind-up.
func burst_cooldown_ticks() -> int:
	return maxi(fire_interval_ticks, burst_pause_ticks)


## Hash of the values, so a ship's state hash changes with what it carries.
## The burst keys join only when set, so weapons without them keep their hashes.
func values_hash() -> int:
	var values: Array = [fire_interval_ticks, projectile_speed, lifetime, damage, energy_cost]
	if has_bursts():
		values.append_array(["burst", burst_shots, burst_pause_ticks, windup_ticks])
	return hash(values)


## Checks one number key and sets it on `weapon`; returns the problem or "".
static func _set_number(weapon: WeaponDef, key: String, value: Variant) -> String:
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
	if WHOLE_KEYS.has(key):
		if number != floorf(number):
			return "key \"%s\" is %s, must be a whole number" % [key, number]
		weapon.set(key, int(number))
	else:
		weapon.set(key, number)
	return ""


static func _failed(message: String) -> WeaponDef:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.error = message
	return weapon
