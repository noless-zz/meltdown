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

## Normal top speed, metres per second (FLT-1).
var max_speed: float = 20.0
## Thrust acceleration at full stick, metres per second squared (FLT-1).
var acceleration: float = 40.0
## Fraction of velocity lost per second when coasting, per second (FLT-1).
var damping: float = 2.0
## Size of the energy pool, energy units (FLT-2).
var max_energy: float = 100.0
## Top speed while the afterburner is on, metres per second (FLT-2).
var afterburner_max_speed: float = 35.0
## Thrust acceleration while the afterburner is on, metres per second squared (FLT-2).
var afterburner_acceleration: float = 80.0
## Energy spent while the afterburner is on, energy units per second (FLT-2).
var afterburner_drain: float = 25.0
## Energy regained while the afterburner is off, energy units per second (FLT-2).
var energy_recharge: float = 12.5
## Energy the pool must refill to after running dry before the afterburner
## works again, energy units (FLT-2).
var afterburner_restart_energy: float = 25.0
## Hull at the start of a run, hull points (FLT-3).
var max_hull: float = 100.0
## Radius of the collision sphere, metres (FLT-3).
var radius: float = 1.0
## Fraction of the speed into a wall kept by a bounce, unitless 0..1; values
## under `ShipState.MIN_WALL_RESTITUTION` are raised to it (FLT-3).
var wall_restitution: float = 0.5
## Hull lost per unit of impact speed, hull points per metre per second (FLT-3).
var wall_damage_per_speed: float = 0.5
## Impact speed below which a bounce deals no damage, metres per second (FLT-3).
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

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a ship data file: one JSON object holding every key in
## `KEYS` as a number, and nothing else. A missing key is an error rather
## than a silent default, so a typo in the file cannot leave a value
## untuned without anyone noticing.
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
	return tuning


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
