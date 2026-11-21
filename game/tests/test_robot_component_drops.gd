extends RefCounted

## Robot component drop tables (CRF-1, ARC-4, #925): optional, parsed by
## `RobotDef`, checked against the kinds, and kept out of the robot's hash so
## no replay changes before the simulation drops anything.

const ComponentKinds := preload("res://tests/test_component_kinds.gd")
const ROBOTS_DIR: String = "res://data/robots"
const BASE: String = "{\"id\": \"drone\", \"hull\": 20.0, \"radius\": 0.8, \"max_speed\": 8.0, \"acceleration\": 16.0, \"turn_rate\": 120.0, \"movement\": \"hover\", \"weapon\": \"robot_pulse\", \"salvage\": \"pulse_cannon\"%s}"
const TABLE: String = ", \"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 2]}, {\"id\": \"circuit_shards\", \"chance\": 0.1, \"count\": [1, 1]}]"
## Tier-2 drops may appear only on these robots, and only rarely.
const TIER_2_ROBOTS: Array[String] = ["hauler", "warden"]
const RARE_CHANCE: float = 0.2


func test_no_table_means_no_components() -> String:
	var robot: RobotDef = RobotDef.parse_json(BASE % "")
	if robot.error != "":
		return robot.error
	if not robot.components.is_empty():
		return "a robot without a table has %d drops" % robot.components.size()
	return ""


func test_table_is_read() -> String:
	var robot: RobotDef = RobotDef.parse_json(BASE % TABLE, ComponentKinds.load_shipped())
	if robot.error != "":
		return robot.error
	if robot.components.size() != 2:
		return "%d drops" % robot.components.size()
	var first: ComponentDrop = robot.components[0]
	if first.id != "scrap_alloy" or first.chance != 0.5 or first.count_min != 1 or first.count_max != 2:
		return "first drop read as %s %s [%d, %d]" % [first.id, first.chance, first.count_min, first.count_max]
	return ""


func test_empty_table_is_allowed() -> String:
	var robot: RobotDef = RobotDef.parse_json(BASE % ", \"components\": []")
	if robot.error != "" or not robot.components.is_empty():
		return "empty table gave \"%s\"" % robot.error
	return ""


func test_unknown_component_is_an_error() -> String:
	var text: String = BASE % TABLE.replace("circuit_shards", "unobtainium")
	var robot: RobotDef = RobotDef.parse_json(text, ComponentKinds.load_shipped())
	if robot.error != "key \"components\", entry 2: unknown component \"unobtainium\"":
		return "unknown id gave \"%s\"" % robot.error
	var unchecked: RobotDef = RobotDef.parse_json(text)
	if unchecked.error != "":
		return unchecked.error
	if unchecked.check_components(ComponentKinds.load_shipped()) == "":
		return "check_components passed an unknown id"
	return ""


func test_rejects_each_bad_entry() -> String:
	var bad: Dictionary = {
		"\"components\": 3": "must be a list",
		"\"components\": [3]": "entry 1: must be a JSON object",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5}]": "entry 1: missing key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 1], \"odds\": 1}]": "entry 1: unknown key \"odds\"",
		"\"components\": [{\"id\": \"Scrap\", \"chance\": 0.5, \"count\": [1, 1]}]": "entry 1: key \"id\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0, \"count\": [1, 1]}]": "entry 1: key \"chance\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 1.5, \"count\": [1, 1]}]": "entry 1: key \"chance\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": \"0.5\", \"count\": [1, 1]}]": "entry 1: key \"chance\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [2, 1]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [0, 1]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 1.5]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, true]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 100]}]": "entry 1: key \"count\"",
		"\"components\": [{\"id\": \"scrap_alloy\", \"chance\": 0.5, \"count\": [1, 1]}, {\"id\": \"scrap_alloy\", \"chance\": 0.2, \"count\": [1, 1]}]": "entry 2: \"scrap_alloy\" is listed twice",
	}
	for table: String in bad:
		var robot: RobotDef = RobotDef.parse_json(BASE % (", " + table))
		var want: String = "key \"components\""
		if not robot.error.begins_with(want) or not robot.error.contains(bad[table]):
			return "%s gave \"%s\", want \"%s\"" % [table, robot.error, bad[table]]
		if not robot.components.is_empty():
			return "rejected robot kept drops"
	return ""


func test_shipped_robots_have_valid_tables() -> String:
	var kinds: ComponentList = ComponentKinds.load_shipped()
	if kinds.error != "":
		return kinds.error
	for file: String in _robot_files():
		var robot: RobotDef = RobotDef.parse_json(_text(file), kinds)
		if robot.error != "":
			return "%s: %s" % [file, robot.error]
		var has_tier_1: bool = false
		for drop: ComponentDrop in robot.components:
			var tier: int = kinds.get_kind(drop.id).tier
			if tier == 1:
				has_tier_1 = true
			elif tier == 2:
				if not TIER_2_ROBOTS.has(robot.id):
					return "%s drops tier-2 %s" % [robot.id, drop.id]
				if drop.chance > RARE_CHANCE:
					return "%s drops tier-2 %s at %s, not rare" % [robot.id, drop.id, drop.chance]
			else:
				return "%s drops tier-%d %s" % [robot.id, tier, drop.id]
		if not has_tier_1:
			return "%s drops no tier-1 component" % robot.id
	for id: String in TIER_2_ROBOTS:
		var found: bool = false
		for drop: ComponentDrop in RobotDef.parse_json(_text(id + ".json"), kinds).components:
			found = found or kinds.get_kind(drop.id).tier == 2
		if not found:
			return "%s has no rare tier-2 drop" % id
	return ""


## No simulation change yet: a table does not change the robot's hash, so the
## shipped robots hash as they did before they had tables.
func test_table_leaves_hash_unchanged() -> String:
	for file: String in _robot_files():
		var json: JSON = JSON.new()
		json.parse(_text(file))
		var data: Dictionary = json.data
		var with_table: RobotDef = RobotDef.parse_json(_text(file))
		data.erase(RobotDef.COMPONENTS_KEY)
		var without: RobotDef = RobotDef.parse_json(JSON.stringify(data))
		if with_table.error != "" or without.error != "":
			return "%s: %s%s" % [file, with_table.error, without.error]
		if with_table.values_hash() != without.values_hash():
			return "%s: the drop table changed the hash" % file
	return ""


func _robot_files() -> PackedStringArray:
	var names: PackedStringArray = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.get_extension() == "json":
			names.append(file)
	return names


func _text(file: String) -> String:
	return FileAccess.get_file_as_string("%s/%s" % [ROBOTS_DIR, file])
