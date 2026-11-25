class_name ReplayRulesLine
extends RefCounted

## Writes and reads a replay's run-level rule lines (version 18, #1028): the
## component drop rules and the miner rescue rules a run level flies with
## (CRF-1, SLV-3). Kept apart from `Replay`, which is at its size limit; the
## format is documented there.
##
##     components {"pickup_reach":2.5}
##     rescue {"hold_seconds":2.0,"miners":[[2000,-20000,-60000]],"rescue_reach":4.0}
##
## `components` is `ComponentPickup`'s data file, plus, for a level reached
## through a shaft (#1000), "tier_weights" and "kind_tiers" (each component
## kind's tier by id) only when the rules are weighted. With it, every robot line
## carries its type's drop table under "components" too, so the replay drops
## exactly what the live run dropped. `rescue` is `MinerRescue`'s data file
## plus "miners", the trapped miners in whole millimetres, in level order.
##
## A replay without the lines flies with drops and rescue off, as every replay
## before version 18 did. A replay is written as version 18 only when it has
## one of the lines, so the text of every other replay, and every level hash
## taken from it, stays as it was.

## First format version that may carry these lines.
const VERSION: int = 18
## The version a replay without them is written as.
const PLAIN_VERSION: int = ReplayLines.AIM_VERSION
const MINERS_KEY: String = "miners"
const WEIGHTS_KEY: String = "tier_weights"
const TIERS_KEY: String = "kind_tiers"


## The format version `replay.to_text()` writes; an alarm line (#1342) needs a later one.
static func format_version(replay: Replay) -> int:
	var version: int = VERSION if replay.component_rules != null or replay.rescue_rules != null else PLAIN_VERSION
	return maxi(version, ReplayAlarmLine.format_version(replay))


static func lines(replay: Replay) -> PackedStringArray:
	var out: PackedStringArray = PackedStringArray()
	if replay.component_rules != null:
		var rules: ComponentPickup = replay.component_rules
		var data: Dictionary = {"pickup_reach": rules.pickup_reach}
		if not rules.tier_weights.is_empty():
			data[WEIGHTS_KEY] = rules.tier_weights
			data[TIERS_KEY] = rules.kind_tiers
		out.append("components " + JSON.stringify(data, "", true, true))
	if replay.rescue_rules != null:
		var miners: Array = []
		for miner: Vector3i in replay.miners:
			miners.append([miner.x, miner.y, miner.z])
		out.append("rescue " + JSON.stringify({"rescue_reach": replay.rescue_rules.rescue_reach,
			"hold_seconds": replay.rescue_rules.hold_seconds, MINERS_KEY: miners}, "", true, true))
	out.append_array(ReplayAlarmLine.lines(replay))
	return out


## Gives `sim` the replay's rules, if it has any. Before the first tick.
static func apply(replay: Replay, sim: Sim) -> void:
	if replay.component_rules != null:
		sim.set_component_rules(replay.component_rules)
	if replay.rescue_rules != null:
		sim.set_rescue_rules(replay.rescue_rules, replay.miners)
	ReplayAlarmLine.apply(replay, sim)


## A robot type's drop table as its data file writes it, for the robot line.
static func drop_table(def: RobotDef) -> Array:
	var table: Array = []
	for drop: ComponentDrop in def.components:
		table.append({"id": drop.id, "chance": drop.chance, "count": [drop.count_min, drop.count_max]})
	return table


## `json_text` is everything after "components ". Returns "" with the rules
## stored on `replay`, or a problem without the line number.
static func parse_components(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	var problem: String = _check_line("components", seen, version)
	if problem != "":
		return problem
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "components: must be one JSON object"
	var data: Dictionary = json.data
	var weights: Variant = data.get(WEIGHTS_KEY, null)
	var tiers: Variant = data.get(TIERS_KEY, null)
	if (weights == null) != (tiers == null):
		return "components: \"%s\" and \"%s\" come together" % [WEIGHTS_KEY, TIERS_KEY]
	data.erase(WEIGHTS_KEY)
	data.erase(TIERS_KEY)
	var rules: ComponentPickup = ComponentPickup.parse_json(JSON.stringify(data, "", true, true))
	if rules.error != "":
		return "components: " + rules.error
	if weights != null:
		if typeof(weights) != TYPE_ARRAY or typeof(tiers) != TYPE_DICTIONARY:
			return "components: \"%s\" must be a list and \"%s\" an object" % [WEIGHTS_KEY, TIERS_KEY]
		problem = rules.set_tier_weights(weights, tiers)
		if problem != "":
			return "components: " + problem
	replay.component_rules = rules
	return ""


## `json_text` is everything after "rescue ". Returns "" with the rules and
## miners stored on `replay`, or a problem without the line number.
static func parse_rescue(replay: Replay, json_text: String,
		seen: Dictionary[String, bool], version: int) -> String:
	var problem: String = _check_line("rescue", seen, version)
	if problem != "":
		return problem
	var json: JSON = JSON.new()
	if json.parse(json_text) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return "rescue: must be one JSON object"
	var data: Dictionary = json.data
	if not data.has(MINERS_KEY):
		return "rescue: missing key \"%s\"" % MINERS_KEY
	var miners: Array[Vector3i] = []
	problem = _read_miners(data[MINERS_KEY], miners)
	if problem != "":
		return "rescue: " + problem
	data.erase(MINERS_KEY)
	var rules: MinerRescue = MinerRescue.parse_json(JSON.stringify(data, "", true, true))
	if rules.error != "":
		return "rescue: " + rules.error
	replay.rescue_rules = rules
	replay.miners = miners
	return ""


static func _check_line(key: String, seen: Dictionary[String, bool], version: int) -> String:
	if seen.is_empty():
		return "the first line must be '%s <version>'" % Replay.FORMAT_NAME
	if version < VERSION:
		return "a %s line needs format version %d or later" % [key, VERSION]
	if seen.has(key):
		return "'%s' appears twice" % key
	seen[key] = true
	return ""


static func _read_miners(value: Variant, miners: Array[Vector3i]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "key \"miners\" must be a list of [x, y, z] in whole millimetres"
	for entry: Variant in value:
		if typeof(entry) != TYPE_ARRAY or (entry as Array).size() != 3:
			return "key \"miners\" must be a list of [x, y, z] in whole millimetres"
		var numbers: Array[int] = []
		for number: Variant in entry:
			if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT \
					or float(number) != floorf(float(number)):
				return "key \"miners\" must be a list of [x, y, z] in whole millimetres"
			numbers.append(int(number))
		miners.append(Vector3i(numbers[0], numbers[1], numbers[2]))
	return ""
