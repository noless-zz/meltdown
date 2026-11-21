class_name ComponentPickup
extends RefCounted

## How destroyed robots drop components and ships take them (CRF-1, ARC-4).
## An instance holds the rules read from `data/components/pickup.json`; core
## opens no files, so the caller hands the text to `parse_json` and the rules
## to `Sim.set_component_rules`. The static functions are the per-tick logic,
## kept out of `Sim` so its tick stays short.
##
## Each robot rolls its drop table from its own stream: the run seed salted
## with the robot's spawn number. So the order robots die in, or how many other
## robots died first, never changes what one robot drops (ARC-2).
##
## Shaft tier weights (#1000, CRF-7, RUN-1): a level reached through a chosen
## shaft may carry that shaft's `reward.tier_weights`, three whole numbers for
## component tiers 1, 2 and 3 (`set_tier_weights`). Each drop-table line's
## `chance` is then multiplied by its kind's tier weight divided by the mean of
## the three weights, and capped at 1.0: a weight above the mean makes that tier
## likelier, a weight of 0 stops it dropping. Only the chance changes, never the
## draws, so every robot's table still means what it says and a robot's stream
## is drawn exactly as before. Weights `[1, 1, 1]`, or none, roll exactly as an
## unweighted level does. A kind with no known tier keeps its chance.

## How far beyond its `radius` a ship's centre may pass from a component and
## still take it, metres, 0..`REACH_MAX`.
var pickup_reach: float = 2.5

## Every key of the data file; all are required and no others are allowed.
const KEYS: Array[String] = ["pickup_reach"]
const REACH_MAX: float = 20.0
## Mixed into every roll's seed so the component stream never repeats another
## stream drawn from the same run seed.
const STREAM_SALT: String = "component drops"

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""
## Tier 1..3 weights of the shaft the level was reached through; empty for none.
var tier_weights: Array[int] = []
## Tier of each component kind by id, given with the weights.
var kind_tiers: Dictionary[String, int] = {}

const TIERS: int = 3


## Parses the text of the pickup file. A missing or unknown key is an error
## naming the key. On failure the returned rules have `error` set.
static func parse_json(text: String) -> ComponentPickup:
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
	if not data.has("pickup_reach"):
		return _rejected("missing key \"pickup_reach\"")
	var value: Variant = data["pickup_reach"]
	# A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return _rejected("key \"pickup_reach\" must be a number")
	if float(value) < 0.0 or float(value) > REACH_MAX:
		return _rejected("key \"pickup_reach\" is %s, must be 0 to %s" % [float(value), REACH_MAX])
	var rules: ComponentPickup = ComponentPickup.new()
	rules.pickup_reach = float(value)
	return rules


## Without weights this is the hash every earlier replay was pinned with, so
## the weights join the state hash only when set.
func values_hash() -> int:
	if tier_weights.is_empty():
		return hash(["pickup_reach", pickup_reach])
	var kinds: Array[String] = []
	kinds.assign(kind_tiers.keys())
	kinds.sort()
	var tiers: Array = []
	for kind: String in kinds:
		tiers.append_array([kind, kind_tiers[kind]])
	return hash(["pickup_reach", pickup_reach, "tier_weights", tier_weights, tiers])


## Weighs the drop rolls by `weights`, three whole numbers of 0 or more with
## at least one above 0, for tiers 1, 2 and 3; `tiers` gives each kind id its
## tier, 1..3. Returns "" or the problem, naming the value, and then leaves
## the rules unweighted.
func set_tier_weights(weights: Array, tiers: Dictionary) -> String:
	var bad: String = "tier weights %s must be %d whole numbers of 0 or more, at least one above 0" % [
		JSON.stringify(weights), TIERS]
	if weights.size() != TIERS:
		return bad
	var checked: Array[int] = []
	var total: int = 0
	for value: Variant in weights:
		if not _is_whole(value) or float(value) < 0.0:
			return bad
		checked.append(int(value))
		total += int(value)
	if total <= 0:
		return bad
	var checked_tiers: Dictionary[String, int] = {}
	for kind: Variant in tiers:
		var tier: Variant = tiers[kind]
		if typeof(kind) != TYPE_STRING or not _is_whole(tier) or int(tier) < 1 or int(tier) > TIERS:
			return "the tier of \"%s\" is %s, must be a whole number 1 to %d" % [str(kind), str(tier), TIERS]
		checked_tiers[kind] = int(tier)
	tier_weights = checked
	kind_tiers = checked_tiers
	return ""


## The chance `drop` rolls with under these rules: the table's chance, scaled
## by its kind's tier weight over the mean weight and capped at 1.0, as the
## class comment says.
func chance_of(drop: ComponentDrop) -> float:
	if tier_weights.is_empty() or not kind_tiers.has(drop.id):
		return drop.chance
	var total: int = 0
	for weight: int in tier_weights:
		total += weight
	var mean: float = float(total) / float(TIERS)
	return minf(drop.chance * float(tier_weights[kind_tiers[drop.id] - 1]) / mean, 1.0)


## Gives `sim` the rules unless `started`; for `Sim.set_component_rules`.
static func install(sim: Sim, rules: ComponentPickup, started: bool) -> String:
	if started:
		return "the component rules are set before the first tick"
	if rules == null or rules.error != "":
		return "the component rules are not resolved"
	sim.component_rules = rules
	return ""


## What a robot of type `def` with spawn number `serial` drops at `position`:
## each line of its table rolled once, in table order, `chance` first and then
## a count in [min, max]. Both numbers are drawn for every line, hit or miss,
## so one line's odds never shift the next line's roll. `rules`, when given,
## scales each line's chance by its tier weight (`chance_of`).
static func roll(def: RobotDef, run_seed: int, serial: int, position: Vector3,
		rules: ComponentPickup = null) -> Array[ComponentItem]:
	var items: Array[ComponentItem] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([run_seed, STREAM_SALT, serial])
	for drop: ComponentDrop in def.components:
		var draw: float = rng.randf()
		var count: int = rng.randi_range(drop.count_min, drop.count_max)
		var chance: float = rules.chance_of(drop) if rules != null else drop.chance
		# randf can return exactly 1.0, so a certain line is tested apart.
		if chance >= 1.0 or draw < chance:
			items.append(ComponentItem.new(drop.id, count, position))
	return items


## Leaves the components of every robot destroyed this tick, in robot order.
## Called before the destroyed robots are removed. Does nothing without rules.
static func drop(sim: Sim) -> void:
	if sim.component_rules == null:
		return
	for robot: RobotState in sim.robots:
		if robot.is_alive():
			continue
		var serial: int = sim.robot_serials.get(robot, -1)
		sim.components.append_array(roll(robot.def, sim.run_seed, serial, robot.position,
			sim.component_rules))


## Lets every live ship take the components its centre passed within
## `radius + pickup_reach` of on its path this tick, from `from[i]` to where it
## is now, so a fast pass still takes them. Ships go in index order, so on a
## tie the lower index gets the item; each ship takes items in list order. A
## taken item adds its count to `sim.collected`, leaves `sim.components`
## (keeping the order of the rest) and adds one COMPONENT_COLLECTED event.
static func collect(sim: Sim, from: Array[Vector3]) -> void:
	if sim.component_rules == null or sim.components.is_empty():
		return
	var kept: Array[ComponentItem] = sim.components.duplicate()
	for i: int in sim.ships.size():
		var ship: ShipState = sim.ships[i]
		if ship.is_destroyed() or ship.escaped:
			continue
		var reach: float = ship.radius + sim.component_rules.pickup_reach
		var left: Array[ComponentItem] = []
		for item: ComponentItem in kept:
			if Projectile.segment_entry(from[i], ship.position, item.position, reach) < 0.0:
				left.append(item)
				continue
			sim.collected[item.kind_id] = sim.collected.get(item.kind_id, 0) + item.count
			var event: SimEvent = SimEvent.new(SimEvent.Kind.COMPONENT_COLLECTED, i,
				float(item.count), item.position)
			event.component = item.kind_id
			sim.last_events.append(event)
		kept = left
	sim.components = kept


## Hash of the component state, joined to the sim's only with rules set: the
## rules, every item, the collected counts by sorted kind, and every robot's
## drop table.
static func state_hash(sim: Sim) -> int:
	var parts: Array[int] = [hash("components"), sim.component_rules.values_hash()]
	for item: ComponentItem in sim.components:
		parts.append(item.state_hash())
	var kinds: Array[String] = []
	kinds.assign(sim.collected.keys())
	kinds.sort()
	for kind: String in kinds:
		parts.append(hash([kind, sim.collected[kind]]))
	for robot: RobotState in sim.robots:
		parts.append(robot.def.values_hash(true))
	return hash(parts)


## A JSON number with no fraction; a bool is not one.
static func _is_whole(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and float(value) == floorf(float(value))


static func _rejected(message: String) -> ComponentPickup:
	var rules: ComponentPickup = ComponentPickup.new()
	rules.error = message
	return rules
