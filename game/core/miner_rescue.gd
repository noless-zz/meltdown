class_name MinerRescue
extends RefCounted

## How ships rescue trapped miners (SLV-3, CRW-1, ARC-4). The rules are read
## from `data/miners/rescue.json`; core opens no files, so the caller hands the
## text to `parse_json` and the rules, with the level's miners, to
## `Sim.set_rescue_rules`. The sim then owns a copy holding the run's state:
## the miners still trapped, how long a ship has held at each, and how many
## were rescued. The static functions are the per-tick logic, kept out of
## `Sim` so its tick stays short.
##
## A rescue is "hover close for a moment", not flying through like components,
## so a miner is never boarded by accident in a fight: a live ship's centre has
## to stay within `rescue_reach` of the miner for `hold_ticks()` ticks in a row.
## A tick with no ship in reach resets that miner's count. Carrying rescued
## miners into the profile's crew is the caller's job, on escape (SLV-3).

## Every key of the data file; all are required and no others are allowed.
const KEYS: Array[String] = ["rescue_reach", "hold_seconds"]
const REACH_MAX: float = 50.0
const HOLD_MAX: float = 60.0
const TICKS_PER_SECOND: int = 60

## How far a ship's centre may be from a miner and still count as holding at
## it, metres, above 0 and at most `REACH_MAX`.
var rescue_reach: float = 4.0
## How long the ship must hold, seconds, above 0 and at most `HOLD_MAX`.
var hold_seconds: float = 2.0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""

## Run state, only in the copy a sim owns: each trapped miner's position in
## whole millimetres, as `LevelDef.miners` holds them, in level order; the
## ticks a ship has held at each, same order; and how many were rescued.
var trapped: Array[Vector3i] = []
var held: Array[int] = []
var rescued: int = 0


## Parses the text of the rescue file. A missing, unknown or out-of-range key
## is an error naming the key. On failure the returned rules have `error` set.
static func parse_json(text: String) -> MinerRescue:
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
	var limits: Array[float] = [REACH_MAX, HOLD_MAX]
	var values: Array[float] = []
	for index: int in KEYS.size():
		var key: String = KEYS[index]
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("key \"%s\" must be a number" % key)
		if float(value) <= 0.0 or float(value) > limits[index]:
			return _rejected("key \"%s\" is %s, must be above 0 and at most %s" \
				% [key, float(value), limits[index]])
		values.append(float(value))
	var rules: MinerRescue = MinerRescue.new()
	rules.rescue_reach = values[0]
	rules.hold_seconds = values[1]
	return rules


## Ticks a ship must hold at a miner: `hold_seconds` at 60 Hz, rounded, and
## never less than one.
func hold_ticks() -> int:
	return maxi(1, roundi(hold_seconds * TICKS_PER_SECOND))


func values_hash() -> int:
	return hash(["rescue_reach", rescue_reach, "hold_seconds", hold_seconds])


## Gives `sim` a fresh copy of `rules` trapping `miners` (millimetres) unless
## `started`; for `Sim.set_rescue_rules`. The copy keeps one rules object
## shared by two sims from sharing their counts.
static func install(sim: Sim, rules: MinerRescue, miners: Array[Vector3i], started: bool) -> String:
	if started:
		return "the rescue rules are set before the first tick"
	if rules == null or rules.error != "":
		return "the rescue rules are not resolved"
	var own: MinerRescue = MinerRescue.new()
	own.rescue_reach = rules.rescue_reach
	own.hold_seconds = rules.hold_seconds
	own.trapped = miners.duplicate()
	for miner: Vector3i in miners:
		own.held.append(0)
	sim.rescue = own
	return ""


## A miner's position in metres.
static func position_of(miner: Vector3i) -> Vector3:
	return Vector3(miner) / float(RobotSpawn.SCALE)


## Counts this tick for every trapped miner, from where the ships ended it.
## A miner whose count reaches `hold_ticks()` is rescued: it leaves `trapped`
## (keeping the order of the rest), adds one to `rescued` and adds one
## MINER_RESCUED event. Called once per tick; does nothing without rules.
static func step(sim: Sim) -> void:
	var state: MinerRescue = sim.rescue
	if state == null or state.trapped.is_empty():
		return
	var need: int = state.hold_ticks()
	var kept: Array[Vector3i] = []
	var kept_held: Array[int] = []
	for index: int in state.trapped.size():
		var miner: Vector3i = state.trapped[index]
		var at: Vector3 = position_of(miner)
		var holder: int = _holder(sim, at, state.rescue_reach)
		var count: int = 0 if holder < 0 else state.held[index] + 1
		if count < need:
			kept.append(miner)
			kept_held.append(count)
			continue
		state.rescued += 1
		sim.last_events.append(SimEvent.new(SimEvent.Kind.MINER_RESCUED, holder,
			float(index), at))
	state.trapped = kept
	state.held = kept_held


## The lowest-index live ship whose centre is within `reach` of `at`, or -1.
static func _holder(sim: Sim, at: Vector3, reach: float) -> int:
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.is_destroyed() or ship.escaped:
			continue
		if ship.position.distance_to(at) <= reach:
			return i
	return -1


## Hash of the rescue state, joined to the sim's only with rules set: the
## rules, every trapped miner with its count, and the rescued total.
static func state_hash(sim: Sim) -> int:
	var state: MinerRescue = sim.rescue
	var parts: Array[int] = [hash("rescue"), state.values_hash(), state.rescued]
	for index: int in state.trapped.size():
		parts.append(hash([state.trapped[index], state.held[index]]))
	return hash(parts)


static func _rejected(message: String) -> MinerRescue:
	var rules: MinerRescue = MinerRescue.new()
	rules.error = message
	return rules
