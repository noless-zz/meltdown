class_name ComponentDrop
extends RefCounted

## One line of a robot's component drop table (CRF-1): when the robot is
## destroyed, `id` drops with probability `chance`, between `count_min` and
## `count_max` of it. Kept out of `RobotDef` so that file stays small.
##
## In a robot file the table is the optional key `components`:
##
##     "components": [{"id": "scrap_alloy", "chance": 0.5, "count": [1, 2]}]

## Component kind id; a file in `ComponentList.COMPONENTS_DIR`.
var id: String = ""
## Probability of the drop, above 0 and at most 1.
var chance: float = 1.0
## Fewest and most that drop, whole numbers, 1..`COUNT_MAX`, min <= max.
var count_min: int = 1
var count_max: int = 1

const KEYS: Array[String] = ["id", "chance", "count"]
const COUNT_MAX: int = 99


## Parses the value of a `components` key: a list of entries. Returns the
## drops, or sets `problem[0]` to the first problem, naming the entry and key,
## and returns an empty list. A kind listed twice is an error, since two lines
## for one kind would make the odds hard to read.
static func parse_table(value: Variant, problem: Array[String]) -> Array[ComponentDrop]:
	var drops: Array[ComponentDrop] = []
	if typeof(value) != TYPE_ARRAY:
		problem.append("key \"components\" must be a list")
		return drops
	var entries: Array = value
	var seen: Dictionary[String, bool] = {}
	for index: int in entries.size():
		var drop: ComponentDrop = ComponentDrop.new()
		var message: String = drop._read(entries[index])
		if message == "" and seen.has(drop.id):
			message = "\"%s\" is listed twice" % drop.id
		if message != "":
			problem.append("key \"components\", entry %d: %s" % [index + 1, message])
			drops.clear()
			return drops
		seen[drop.id] = true
		drops.append(drop)
	return drops


func _read(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var data: Dictionary = entry
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in KEYS:
		if not data.has(key):
			return "missing key \"%s\"" % key
	var message: String = ComponentDef.check_id("id", data["id"])
	if message != "":
		return message
	id = data["id"]
	var odds: Variant = data["chance"]
	if typeof(odds) != TYPE_FLOAT and typeof(odds) != TYPE_INT:
		return "key \"chance\" must be a number"
	if float(odds) <= 0.0 or float(odds) > 1.0:
		return "key \"chance\" is %s, must be above 0 and at most 1" % float(odds)
	chance = float(odds)
	return _read_count(data["count"])


func _read_count(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return "key \"count\" must be a list of two whole numbers [min, max]"
	var pair: Array = value
	for number: Variant in pair:
		if typeof(number) != TYPE_FLOAT and typeof(number) != TYPE_INT:
			return "key \"count\" must be a list of two whole numbers [min, max]"
		var whole: float = float(number)
		if whole != floorf(whole) or whole < 1.0 or whole > COUNT_MAX:
			return "key \"count\" has %s, each must be a whole number 1 to %d" % [whole, COUNT_MAX]
	count_min = int(pair[0])
	count_max = int(pair[1])
	if count_min > count_max:
		return "key \"count\" is [%d, %d], min must not exceed max" % [count_min, count_max]
	return ""
