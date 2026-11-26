class_name CrewBonus
extends RefCounted

## What the pilot's crew adds to a run level's simulation (CRW-1, CRW-3,
## SLV-3, #1386): extra slots in every ship's salvage hold and extra seconds
## on the reactor's meltdown countdown. `CrewBenefits` sums and caps the crew
## in `meta/`; core opens no files and knows no profile, so the totals arrive
## here as start-of-run data before the first tick, like the alarm (ARC-1,
## MP-2), and a replay carries them on its crew line (`ReplayCrewLine`).
##
##     {"hold_slots": 2, "meltdown_seconds": 20}
##
## A bonus of zero changes nothing: it is never installed, never written to a
## replay and never hashed, so every run without crew keeps its hash.

const HOLD_SLOTS_KEY: String = "hold_slots"
const MELTDOWN_SECONDS_KEY: String = "meltdown_seconds"
const KEYS: Array[String] = [HOLD_SLOTS_KEY, MELTDOWN_SECONDS_KEY]
## Bounds that only refuse nonsense; the roles file's caps are far below them.
const HOLD_SLOTS_MAX: int = 16
const MELTDOWN_SECONDS_MAX: int = 600

## Slots added to every ship's `ShipState.HOLD_CAPACITY`.
var hold_slots: int = 0
## Whole seconds added to the reactor's countdown when it dies, after the
## level's own clamp (`ReactorState.meltdown_ticks_for_path`).
var meltdown_seconds: int = 0
## Set by `parse` when the data was rejected; empty otherwise.
var error: String = ""


static func of(p_hold_slots: int, p_meltdown_seconds: int) -> CrewBonus:
	var bonus: CrewBonus = CrewBonus.new()
	bonus.hold_slots = p_hold_slots
	bonus.meltdown_seconds = p_meltdown_seconds
	bonus.error = bonus._check()
	return bonus


## Reads a bonus from `value`, a parsed JSON object with both keys.
static func parse(value: Variant) -> CrewBonus:
	var bonus: CrewBonus = CrewBonus.new()
	if typeof(value) != TYPE_DICTIONARY:
		bonus.error = "must be a JSON object"
		return bonus
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(key):
			bonus.error = "unknown key \"%s\"" % str(key)
			return bonus
	for key: String in KEYS:
		var number: Variant = data.get(key, null)
		if typeof(number) != TYPE_INT and typeof(number) != TYPE_FLOAT \
				or not is_finite(float(number)) or float(number) != floorf(float(number)):
			bonus.error = "key \"%s\" must be a whole number" % key
			return bonus
	bonus.hold_slots = int(data[HOLD_SLOTS_KEY])
	bonus.meltdown_seconds = int(data[MELTDOWN_SECONDS_KEY])
	bonus.error = bonus._check()
	return bonus


static func parse_json(text: String) -> CrewBonus:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		var failed: CrewBonus = CrewBonus.new()
		failed.error = "invalid JSON: %s" % json.get_error_message()
		return failed
	return parse(json.data)


func to_json() -> String:
	return JSON.stringify({HOLD_SLOTS_KEY: hold_slots, MELTDOWN_SECONDS_KEY: meltdown_seconds},
		"", true, true)


## True when the bonus adds nothing.
func is_zero() -> bool:
	return hold_slots == 0 and meltdown_seconds == 0


func values_hash() -> int:
	return hash(["crew", hold_slots, meltdown_seconds])


## Gives `sim` the bonus before its first tick: every ship's hold grows and
## the reactor's countdown lengthens. A zero bonus installs nothing, so the
## sim stays exactly as it was. Returns "" or the reason nothing changed.
static func install(sim: Sim, bonus: CrewBonus, started: bool) -> String:
	if started:
		return "the crew bonus is set before the first tick"
	if bonus == null or bonus.error != "":
		return "the crew bonus is not resolved"
	if bonus.is_zero():
		return ""
	sim.crew = bonus
	for ship: ShipState in sim.ships:
		ship.hold_capacity = ShipState.HOLD_CAPACITY + bonus.hold_slots
	if sim.reactor != null:
		sim.reactor.crew_seconds = bonus.meltdown_seconds
	return ""


func _check() -> String:
	if hold_slots < 0 or hold_slots > HOLD_SLOTS_MAX:
		return "key \"%s\" must be 0 to %d" % [HOLD_SLOTS_KEY, HOLD_SLOTS_MAX]
	if meltdown_seconds < 0 or meltdown_seconds > MELTDOWN_SECONDS_MAX:
		return "key \"%s\" must be 0 to %d" % [MELTDOWN_SECONDS_KEY, MELTDOWN_SECONDS_MAX]
	return ""
