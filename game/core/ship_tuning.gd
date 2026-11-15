class_name ShipTuning
extends RefCounted

## The feel values of a ship, read from a text data file so that they can be
## tuned without code changes (ARC-4, ARC-5, decision record 0003).
##
## Core never opens files: the caller reads the text and hands it to
## `parse_json`. The defaults equal `ShipState`'s, so a ship given the default
## tuning flies exactly as before and every recorded replay keeps its hash.
## Tuning belongs to the ship, never to a comfort preset: every player of the
## same ship gets the same numbers (CMF-6).
##
## Each field below is one key of the data file, with the same name and unit.

## Normal top speed, metres per second, 1..200 (FLT-1).
var max_speed: float = 20.0
## Thrust acceleration at full stick, metres per second squared, 1..1000 (FLT-1).
var acceleration: float = 40.0
## Fraction of velocity lost per second when coasting, per second, 0..60;
## above the tick rate a tick would remove more than all the velocity (FLT-1).
var damping: float = 2.0
## Size of the energy pool, energy units, 1..1000 (FLT-2).
var max_energy: float = 100.0
## Top speed while the afterburner is on, metres per second,
## `max_speed`..300, so boosting is never slower than cruising (FLT-2).
var afterburner_max_speed: float = 35.0
## Thrust acceleration while the afterburner is on, metres per second squared,
## 1..2000 (FLT-2).
var afterburner_acceleration: float = 80.0
## Energy spent while the afterburner is on, energy units per second, 0.1..1000;
## at 0 the pool would never matter (FLT-2).
var afterburner_drain: float = 25.0
## Energy regained while the afterburner is off, energy units per second,
## 0.1..1000; at 0 the pool would never recharge (FLT-2).
var energy_recharge: float = 12.5
## Energy the pool must refill to after running dry before the afterburner
## works again, energy units, 0..`max_energy`; above it the afterburner would
## stay locked for good (FLT-2).
var afterburner_restart_energy: float = 25.0
## Hull at the start of a run, hull points, 1..10000 (FLT-3).
var max_hull: float = 100.0
## Radius of the collision sphere, metres, 0.1..10 (FLT-3).
var radius: float = 1.0
## Fraction of the speed into a wall kept by a bounce, unitless, 0..1; values
## under `ShipState.MIN_WALL_RESTITUTION` are raised to it (FLT-3).
var wall_restitution: float = 0.5
## Hull lost per unit of impact speed, hull points per metre per second,
## 0..100 (FLT-3).
var wall_damage_per_speed: float = 0.5
## Impact speed below which a bounce deals no damage, metres per second,
## 0..300 (FLT-3).
var wall_damage_min_speed: float = 4.0

## Every key of the data file, in the order the file lists them. Each one is
## a field of this class and of `ShipState` with the same name.
const KEYS: Array[String] = [
	"max_speed", "acceleration", "damping",
	"max_energy", "afterburner_max_speed", "afterburner_acceleration",
	"afterburner_drain", "energy_recharge", "afterburner_restart_energy",
	"max_hull", "radius", "wall_restitution", "wall_damage_per_speed",
	"wall_damage_min_speed",
]

## Allowed range of each key, inclusive: [minimum, maximum]. A bound that is
## a String names another key, whose parsed value is the bound. Keep these in
## step with the ranges written on the fields above.
const RANGES: Dictionary = {
	"max_speed": [1.0, 200.0],
	"acceleration": [1.0, 1000.0],
	"damping": [0.0, 60.0],
	"max_energy": [1.0, 1000.0],
	"afterburner_max_speed": ["max_speed", 300.0],
	"afterburner_acceleration": [1.0, 2000.0],
	"afterburner_drain": [0.1, 1000.0],
	"energy_recharge": [0.1, 1000.0],
	"afterburner_restart_energy": [0.0, "max_energy"],
	"max_hull": [1.0, 10000.0],
	"radius": [0.1, 10.0],
	"wall_restitution": [0.0, 1.0],
	"wall_damage_per_speed": [0.0, 100.0],
	"wall_damage_min_speed": [0.0, 300.0],
}

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a ship data file: one JSON object holding every key in
## `KEYS` as a number, and nothing else. A missing key is an error rather
## than a silent default, so a typo in the file cannot leave a value
## untuned without anyone noticing. Each value must lie in its range in
## `RANGES`, so a data file cannot put the simulation into a nonsense state.
## On failure the returned tuning has `error` set and default values.
static func parse_json(text: String) -> ShipTuning:
	var tuning: ShipTuning = ShipTuning.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		tuning.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return tuning
	if typeof(json.data) != TYPE_DICTIONARY:
		tuning.error = "top level must be a JSON object"
		return tuning
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _defaults_with_error("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _defaults_with_error("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# JSON numbers arrive as floats; ints are accepted for safety. A bool
		# must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _defaults_with_error("key \"%s\" must be a number" % key)
		tuning.set(key, float(value))
	# Ranges are checked only once every value is read, because some bounds
	# are other keys.
	for key: String in KEYS:
		var message: String = tuning._range_error(key)
		if message != "":
			return _defaults_with_error(message)
	return tuning


## Bound `bound` of `key` as a number: a literal, or the value of the key it names.
func _bound(bound: Variant) -> float:
	if typeof(bound) == TYPE_STRING:
		return get(bound)
	return bound


## Empty when `key` is inside its range, otherwise a message naming the key.
func _range_error(key: String) -> String:
	var value: float = get(key)
	var low: Variant = RANGES[key][0]
	var high: Variant = RANGES[key][1]
	if value < _bound(low):
		return "key \"%s\" is %s, must be at least %s" % [key, value, _describe(low)]
	if value > _bound(high):
		return "key \"%s\" is %s, must be at most %s" % [key, value, _describe(high)]
	return ""


func _describe(bound: Variant) -> String:
	if typeof(bound) == TYPE_STRING:
		return "%s (%s)" % [bound, get(bound)]
	return str(bound)


static func _defaults_with_error(message: String) -> ShipTuning:
	var tuning: ShipTuning = ShipTuning.new()
	tuning.error = message
	return tuning


## Gives `ship` these values. Meant for a ship at the start of a run: the
## energy pool and the hull are filled to their new maxima and the
## afterburner lock is cleared.
func apply_to(ship: ShipState) -> void:
	for key: String in KEYS:
		ship.set(key, get(key))
	ship.energy = ship.max_energy
	ship.hull = ship.max_hull
	ship.afterburner_locked = false
