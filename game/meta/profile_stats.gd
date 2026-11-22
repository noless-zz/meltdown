class_name ProfileStats
extends RefCounted

## Lifetime statistics the hub shows next to crew and unlocks (CRW-2, #1069).
## Kept for the whole profile and never reset, so a lost run keeps them too
## (RUN-7). Pure data with update calls: recording them from a run and drawing
## them in the hub are separate issues. `Profile` stores them under `stats`.

const KEY_RUNS_STARTED: String = "runs_started"
const KEY_RUNS_WON: String = "runs_won"
const KEY_RUNS_LOST: String = "runs_lost"
const KEY_LEVELS_ESCAPED: String = "levels_escaped"
const KEY_DEEPEST_LEVEL: String = "deepest_level"
const KEY_MINERS_RESCUED: String = "miners_rescued"
const KEY_COMPONENTS_BANKED: String = "components_banked"
const KEYS: Array[String] = [
	KEY_RUNS_STARTED, KEY_RUNS_WON, KEY_RUNS_LOST, KEY_LEVELS_ESCAPED,
	KEY_DEEPEST_LEVEL, KEY_MINERS_RESCUED, KEY_COMPONENTS_BANKED,
]

var runs_started: int = 0
var runs_won: int = 0
var runs_lost: int = 0
var levels_escaped: int = 0
## 1-based: escaping the first level of a run makes this at least 1.
var deepest_level: int = 0
var miners_rescued: int = 0
## Total components over all kinds, as banked on each escape.
var components_banked: int = 0


func record_run_start() -> bool:
	runs_started += 1
	return true


## One level escaped. `level_index` is the run's 0-based index (as in
## `RunState.level_index`), `miners` the miners carried out and `banked` the
## component id to count map banked on that escape. Refuses the whole call,
## changing nothing, if any argument is negative or malformed.
func record_escape(level_index: int, miners: int, banked: Dictionary) -> bool:
	if level_index < 0 or miners < 0 or not valid_counts(banked):
		return false
	var total: int = 0
	for id: Variant in banked:
		total += int(banked[id])
	levels_escaped += 1
	deepest_level = maxi(deepest_level, level_index + 1)
	miners_rescued += miners
	components_banked += total
	return true


func record_loss() -> bool:
	runs_lost += 1
	return true


func record_win() -> bool:
	runs_won += 1
	return true


func to_dict() -> Dictionary:
	return {
		KEY_RUNS_STARTED: runs_started,
		KEY_RUNS_WON: runs_won,
		KEY_RUNS_LOST: runs_lost,
		KEY_LEVELS_ESCAPED: levels_escaped,
		KEY_DEEPEST_LEVEL: deepest_level,
		KEY_MINERS_RESCUED: miners_rescued,
		KEY_COMPONENTS_BANKED: components_banked,
	}


func equals(other: ProfileStats) -> bool:
	return other != null and to_dict() == other.to_dict()


## Error describing what is wrong with a stored `stats` value, or "" when it is
## an object whose keys are all known counters holding whole numbers of at least
## 0. A missing counter reads as 0.
static func check(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be an object of counters"
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(str(key)):
			return "unknown counter \"%s\"" % str(key)
		if not whole_number(data[key]) or float(data[key]) < 0.0:
			return "counter \"%s\" must be a whole number of at least 0" % str(key)
	return ""


## Reads a value `check` accepted. Callers check first.
static func from_dict(data: Dictionary) -> ProfileStats:
	var stats: ProfileStats = ProfileStats.new()
	stats.runs_started = int(data.get(KEY_RUNS_STARTED, 0))
	stats.runs_won = int(data.get(KEY_RUNS_WON, 0))
	stats.runs_lost = int(data.get(KEY_RUNS_LOST, 0))
	stats.levels_escaped = int(data.get(KEY_LEVELS_ESCAPED, 0))
	stats.deepest_level = int(data.get(KEY_DEEPEST_LEVEL, 0))
	stats.miners_rescued = int(data.get(KEY_MINERS_RESCUED, 0))
	stats.components_banked = int(data.get(KEY_COMPONENTS_BANKED, 0))
	return stats


## Component id (non-empty string) to a whole number of at least 0.
static func valid_counts(counts: Dictionary) -> bool:
	for id: Variant in counts:
		if typeof(id) != TYPE_STRING or String(id).is_empty():
			return false
		if not whole_number(counts[id]) or float(counts[id]) < 0.0:
			return false
	return true


## JSON gives every number as a float; a bool must not pass as 0 or 1.
static func whole_number(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var number: float = value
	return is_finite(number) and number == floorf(number) and absf(number) < 1.0e15
