extends RefCounted

## Robot spawns as data (#228, CMB-3, ARC-4): the level file is parsed and
## checked, types resolve all or nothing, the facing sets the orientation, and
## replays record the spawns exactly (ARC-2).

const ROBOTS_DIR: String = "res://data/robots/"
const SPAWN_FILE: String = "res://data/levels/test_tunnel_robots.json"


func _texts(ids: Array[String]) -> Dictionary:
	var texts: Dictionary = {}
	for id: String in ids:
		texts[id] = FileAccess.get_file_as_string(ROBOTS_DIR + id + ".json")
	return texts


func _drone() -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string(ROBOTS_DIR + "drone.json"))


func test_the_shipped_spawn_file_parses_and_resolves() -> String:
	var list: RobotSpawnList = RobotSpawnList.parse_json(FileAccess.get_file_as_string(SPAWN_FILE))
	if list.error != "":
		return "the shipped file is rejected: %s" % list.error
	if list.spawns.size() != 6 or list.ids().size() != 6:
		return "%d spawns of %d types, expected 6 of 6" % [list.spawns.size(), list.ids().size()]
	var problem: String = list.resolve(_texts(list.ids()))
	if problem != "":
		return "the shipped types do not resolve: %s" % problem
	for spawn: RobotSpawn in list.spawns:
		if spawn.def == null or spawn.def.id != spawn.id:
			return "spawn %s did not get its type" % spawn.id
	return ""


func test_positions_are_read_in_whole_millimetres() -> String:
	var list: RobotSpawnList = RobotSpawnList.parse_json(
		"{\"robots\": [{\"id\": \"drone\", \"position\": [1.2344, -0.5, -30], \"facing\": [0, 0, 2]}]}")
	if list.error != "":
		return list.error
	var spawn: RobotSpawn = list.spawns[0]
	if spawn.position_mm != Vector3i(1234, -500, -30000) or spawn.facing_mm != Vector3i(0, 0, 2000):
		return "read %s facing %s" % [spawn.position_mm, spawn.facing_mm]
	return ""


func test_rejections_name_the_problem() -> String:
	var entry: String = "{\"id\": \"drone\", \"position\": [0, 0, -1], \"facing\": [0, 0, 1]%s}"
	var cases: Array[Array] = [
		["[]", "top level must be a JSON object"],
		["{\"robot\": []}", "unknown key \"robot\""],
		["{\"robots\": 3}", "key \"robots\" must be a list"],
		["{\"robots\": [%s]}" % (entry % ", \"hull\": 3"), "robot 1: unknown key \"hull\""],
		["{\"robots\": [%s, {\"id\": \"drone\", \"position\": [0, 0, 0]}]}" % (entry % ""),
			"robot 2: missing key \"facing\""],
		["{\"robots\": [{\"id\": \"Drone\", \"position\": [0, 0, 0], \"facing\": [0, 0, 1]}]}",
			"robot 1: \"id\" is \"Drone\", must use only a-z, 0-9 and _"],
		["{\"robots\": [{\"id\": 4, \"position\": [0, 0, 0], \"facing\": [0, 0, 1]}]}",
			"robot 1: \"id\" must be a string"],
		["{\"robots\": [{\"id\": \"drone\", \"position\": [0, 0], \"facing\": [0, 0, 1]}]}",
			"robot 1: position must be a list of three numbers"],
		["{\"robots\": [{\"id\": \"drone\", \"position\": [0, 0, 20000], \"facing\": [0, 0, 1]}]}",
			"robot 1: position must be within 10000.0 m of the origin"],
		["{\"robots\": [{\"id\": \"drone\", \"position\": [0, 0, 0], \"facing\": [0, 0, 0.0001]}]}",
			"robot 1: facing must not be zero"],
	]
	for c: Array in cases:
		var list: RobotSpawnList = RobotSpawnList.parse_json(c[0])
		if list.error != c[1]:
			return "%s gave \"%s\", expected \"%s\"" % [c[0], list.error, c[1]]
		if not list.spawns.is_empty():
			return "a rejected file kept spawns"
	return ""


func test_resolve_is_all_or_nothing() -> String:
	var list: RobotSpawnList = RobotSpawnList.parse_json(FileAccess.get_file_as_string(SPAWN_FILE))
	var texts: Dictionary = _texts(list.ids())
	texts.erase("warden")
	if list.resolve(texts) != "robot \"warden\": data file not found":
		return "a missing type gave \"%s\"" % list.resolve(texts)
	texts["warden"] = texts["drone"]
	if list.resolve(texts) != "robot \"warden\": its file says id \"drone\"":
		return "a mismatched id gave \"%s\"" % list.resolve(texts)
	for spawn: RobotSpawn in list.spawns:
		if spawn.def != null:
			return "a failed resolve gave %s a type" % spawn.id
	var sim: Sim = Sim.new()
	if RobotSpawn.spawn_all(sim, list.spawns) or not sim.robots.is_empty():
		return "unresolved spawns were spawned"
	return ""


func test_the_facing_sets_the_orientation() -> String:
	var directions: Array[Vector3i] = [Vector3i(0, 0, 1000), Vector3i(1000, 0, 0),
		Vector3i(0, 1000, 0), Vector3i(0, -500, 0), Vector3i(300, 400, -1200)]
	for facing: Vector3i in directions:
		var spawn: RobotSpawn = RobotSpawn.new(_drone(), Vector3i(0, 0, -5000), facing)
		var robot: RobotState = RobotState.new(spawn.def, spawn.position(), spawn.orientation())
		var expected: Vector3 = Vector3(facing).normalized()
		if robot.forward().distance_to(expected) > 1e-5:
			return "facing %s gave forward %s" % [facing, robot.forward()]
		if not robot.orientation.is_equal_approx(robot.orientation.orthonormalized()):
			return "facing %s gave a basis that is not a rotation" % facing
	return ""


func test_replay_robot_lines_read_back_exactly() -> String:
	var replay: Replay = Replay.new(3, 1)
	var def: RobotDef = _drone()
	def.max_speed = 7.123456789012  # Not round: lost precision would show.
	replay.robots = [RobotSpawn.new(def, Vector3i(-1, 2, -30000), Vector3i(0, 0, 1000)),
		RobotSpawn.new(_drone(), Vector3i(5, 6, -7), Vector3i(1, 2, 3))]
	replay.add_tick([ShipInput.new(Vector3i(0, 0, -1000))] as Array[ShipInput])
	var text: String = replay.to_text()
	var reread: Replay = Replay.from_text(text)
	if reread.error != "":
		return reread.error
	if reread.to_text() != text:
		return "the text changed on reading back:\n%s\n%s" % [text, reread.to_text()]
	if reread.robots.size() != 2 or reread.robots[0].def.max_speed != def.max_speed:
		return "the robots did not read back exactly"
	if replay.run().state_hash() != reread.run().state_hash():
		return "the reread replay ends on another hash"
	if reread.run().robots.size() != 2:
		return "running the replay did not spawn its robots"
	return ""


func test_robot_line_rejections() -> String:
	var drone: String = FileAccess.get_file_as_string(ROBOTS_DIR + "drone.json").replace("\n", "").replace("\t", "")
	var header: String = "meltdown-replay 8\nseed 1\nships 1\n"
	var cases: Array[Array] = [
		["meltdown-replay 7\nseed 1\nships 1\nrobot 0 0 0 0 0 1 %s\n" % drone,
			"line 4: a robot line needs format version 8 or later"],
		[header + "robot 0 0 0 0 0 1\n", "line 4: robot needs a position, a facing and the robot's data"],
		[header + "robot 0 0 x 0 0 1 %s\n" % drone, "line 4: 'x' is not a whole number"],
		[header + "robot 0 0 0 0 0 0 %s\n" % drone, "line 4: robot facing must not be zero"],
		[header + "robot 0 0 0 0 0 1 {\"id\": \"drone\"}\n", "line 4: robot 1: missing key \"hull\""],
	]
	for c: Array in cases:
		var replay: Replay = Replay.from_text(c[0] + "inputs\n")
		if replay.error != c[1]:
			return "gave \"%s\", expected \"%s\"" % [replay.error, c[1]]
	return ""
