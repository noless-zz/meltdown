extends RefCounted

## Robots' shown names (#1413, CRW-2, ARC-4, NAM-3): every robot file names its
## type, a file without a name or with an empty one is refused with the key
## named, a replay's robot line still parses without one, and the name never
## changes a replay's hash. `RobotDrops` gives each component its robots by name.

const ROBOTS_DIR: String = "res://data/robots"
const BASE: String = "\"id\": \"probe\", \"hull\": 20, \"radius\": 0.8, \"max_speed\": 8, \"acceleration\": 16, " \
	+ "\"turn_rate\": 120, \"movement\": \"hover\", \"weapon\": \"robot_pulse\", \"salvage\": \"pulse_cannon\""


static func _robot(extra: String) -> String:
	return "{%s%s}" % [BASE, extra]


func test_every_shipped_robot_file_has_a_shown_name() -> String:
	var seen: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if not file.ends_with(".json"):
			continue
		var robot: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(ROBOTS_DIR.path_join(file)))
		if robot.error != "" or robot.check_name() != "":
			return "%s: %s%s" % [file, robot.error, robot.check_name()]
		if robot.display_name == robot.id or seen.has(robot.display_name):
			return "%s shows \"%s\": an id or a name already taken" % [file, robot.display_name]
		seen.append(robot.display_name)
	if seen.size() < 6:
		return "only %d robot files" % seen.size()
	return "" if RobotDrops.load_shipped().error == "" else RobotDrops.load_shipped().error


func test_a_missing_name_is_refused_with_the_key_named() -> String:
	var drops: RobotDrops = RobotDrops.parse({"probe.json": _robot("")})
	if not drops.error.contains("probe.json") or not drops.error.contains("\"name\""):
		return "a file without a name gave \"%s\"" % drops.error
	return ""


func test_an_empty_or_wrong_name_is_refused_with_the_key_named() -> String:
	for value: String in ["\"\"", "\"   \"", "7", "\"%s\"" % "x".repeat(RobotDef.NAME_MAX_LENGTH + 1)]:
		var robot: RobotDef = RobotDef.parse_json(_robot(", \"name\": %s" % value))
		if not robot.error.contains("\"name\""):
			return "name %s gave \"%s\"" % [value, robot.error]
	return ""


func test_a_replay_line_without_a_name_still_parses_and_the_name_is_not_hashed() -> String:
	var bare: RobotDef = RobotDef.parse_json(_robot(""))
	var named: RobotDef = RobotDef.parse_json(_robot(", \"name\": \"Probe\""))
	if bare.error != "" or named.error != "" or named.display_name != "Probe":
		return "parsed \"%s\" and \"%s\" (%s)" % [bare.error, named.error, named.display_name]
	if bare.values_hash(true) != named.values_hash(true):
		return "the shown name changed the robot's hash"
	return ""


func test_drops_list_each_components_robots_by_shown_name() -> String:
	var drops: RobotDrops = RobotDrops.parse({
		"b.json": _robot(", \"name\": \"Beta\", \"components\": [{\"id\": \"ore\", \"chance\": 0.5, \"count\": [1, 1]}]")
			.replace("\"probe\"", "\"b\""),
		"a.json": _robot(", \"name\": \"Alpha\", \"components\": [{\"id\": \"ore\", \"chance\": 0.5, \"count\": [1, 1]}, "
			+ "{\"id\": \"gem\", \"chance\": 0.1, \"count\": [1, 1]}]").replace("\"probe\"", "\"a\""),
	})
	if drops.error != "" or drops.names("ore") != ["Alpha", "Beta"] or drops.names("gem") != ["Alpha"] \
			or not drops.names("dust").is_empty():
		return "drops %s (%s)" % [drops.sources, drops.error]
	var shipped: RobotDrops = RobotDrops.load_shipped()
	if shipped.names("scrap_alloy").is_empty() or shipped.names("scrap_alloy").has("drone"):
		return "shipped scrap alloy comes from %s" % [shipped.names("scrap_alloy")]
	return ""
