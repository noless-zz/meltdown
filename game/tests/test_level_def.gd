extends RefCounted

## The hand-built G2 level (#272, GEN-5, CMB-3, ARC-4): the shipped file parses
## and meets its layout rules, counted here from the data, and `LevelDef`
## rejects each kind of bad level with a message naming the problem.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const ROBOTS_DIR: String = "res://data/robots/"
const MIN_BOXES: int = 6
const MIN_PATH_M: float = 120.0
const MIN_NEAREST_ROBOT_M: float = 30.0
## A shaft is at least this tall and twice as tall as it is wide either way.
const MIN_SHAFT_HEIGHT_M: float = 20.0
## Every side of a side room is at least this long.
const MIN_ROOM_SIDE_M: float = 12.0


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


func _centre(box: BoxBounds) -> Vector3:
	return (box.min_corner + box.max_corner) * 0.5


func _overlap_centre(a: BoxBounds, b: BoxBounds) -> Vector3:
	var low: Vector3 = Vector3(maxf(a.min_corner.x, b.min_corner.x),
			maxf(a.min_corner.y, b.min_corner.y), maxf(a.min_corner.z, b.min_corner.z))
	var high: Vector3 = Vector3(minf(a.max_corner.x, b.max_corner.x),
			minf(a.max_corner.y, b.max_corner.y), minf(a.max_corner.z, b.max_corner.z))
	return (low + high) * 0.5


## For each box, the box it is first reached from in a breadth-first walk from
## box 0 (-1 for box 0 itself).
func _parents(level: LevelDef) -> Array[int]:
	var parents: Array[int] = []
	parents.resize(level.union.boxes.size())
	parents.fill(-2)
	parents[0] = -1
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in level.neighbours(index):
			if parents[other] == -2:
				parents[other] = index
				queue.append(other)
	return parents


## Flight path from the start to the centre of box `target`: through the centre
## of each opening on the walk from box 0.
func _path_length(level: LevelDef, parents: Array[int], target: int) -> float:
	var chain: Array[int] = [target]
	while parents[chain[0]] >= 0:
		chain.push_front(parents[chain[0]])
	var points: Array[Vector3] = [level.start_position()]
	for step: int in range(1, chain.size()):
		points.append(_overlap_centre(level.union.boxes[chain[step - 1]], level.union.boxes[chain[step]]))
	points.append(_centre(level.union.boxes[target]))
	var total: float = 0.0
	for step: int in range(1, points.size()):
		total += points[step - 1].distance_to(points[step])
	return total


func _farthest(level: LevelDef, parents: Array[int]) -> int:
	var best: int = 0
	for index: int in parents.size():
		if _path_length(level, parents, index) > _path_length(level, parents, best):
			best = index
	return best


func test_the_shipped_level_parses_and_resolves() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return "the shipped level is rejected: %s" % level.error
	var texts: Dictionary = {}
	for id: String in level.robots.ids():
		texts[id] = FileAccess.get_file_as_string(ROBOTS_DIR + id + ".json")
	var problem: String = level.robots.resolve(texts)
	if problem != "":
		return "the shipped robots do not resolve: %s" % problem
	# Stricter than the parser: each robot fits at its own size, not just 1 m.
	for spawn: RobotSpawn in level.robots.spawns:
		if not level.union.holds(spawn.position(), spawn.def.radius):
			return "%s does not fit at its spawn" % spawn.id
	return ""


func test_the_shipped_level_has_enough_boxes_and_path() -> String:
	var level: LevelDef = _level()
	if level.union.boxes.size() < MIN_BOXES:
		return "%d boxes, expected at least %d" % [level.union.boxes.size(), MIN_BOXES]
	if not level.union.boxes[0].holds(level.start_position(), LevelDef.CLEARANCE_M):
		return "the start is not in box 0"
	var parents: Array[int] = _parents(level)
	var length: float = _path_length(level, parents, _farthest(level, parents))
	if length < MIN_PATH_M:
		return "flight path to the far end is %.1f m, expected at least %.0f" % [length, MIN_PATH_M]
	return ""


func test_the_shipped_level_has_a_vertical_shaft() -> String:
	for box: BoxBounds in _level().union.boxes:
		var size: Vector3 = box.max_corner - box.min_corner
		if size.y >= MIN_SHAFT_HEIGHT_M and size.y >= 2.0 * size.x and size.y >= 2.0 * size.z:
			return ""
	return "no box is a vertical shaft"


func test_the_shipped_level_has_a_side_room() -> String:
	var level: LevelDef = _level()
	var parents: Array[int] = _parents(level)
	var main_path: Array[int] = []
	var index: int = _farthest(level, parents)
	while index >= 0:
		main_path.append(index)
		index = parents[index]
	for room: int in level.union.boxes.size():
		var size: Vector3 = level.union.boxes[room].max_corner - level.union.boxes[room].min_corner
		if main_path.has(room) or level.neighbours(room).size() != 1:
			continue
		if size.x >= MIN_ROOM_SIDE_M and size.y >= MIN_ROOM_SIDE_M and size.z >= MIN_ROOM_SIDE_M:
			return ""
	return "no dead-end room off the main path with every side at least %.0f m" % MIN_ROOM_SIDE_M


func test_the_shipped_level_has_one_robot_of_each_type() -> String:
	var level: LevelDef = _level()
	var types: Array[String] = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json"):
			types.append(file.get_basename())
	if types.size() != 6:
		return "%d robot types shipped, expected 6" % types.size()
	if level.robots.spawns.size() != types.size():
		return "%d robots, expected %d" % [level.robots.spawns.size(), types.size()]
	for id: String in types:
		if not level.robots.ids().has(id):
			return "no %s in the level" % id
	return ""


func test_the_nearest_robot_is_far_from_the_start() -> String:
	var level: LevelDef = _level()
	for spawn: RobotSpawn in level.robots.spawns:
		var distance: float = spawn.position().distance_to(level.start_position())
		if distance < MIN_NEAREST_ROBOT_M:
			return "%s is %.1f m from the start, expected at least %.0f" % [spawn.id, distance, MIN_NEAREST_ROBOT_M]
	return ""


func test_start_is_read_in_millimetres() -> String:
	var level: LevelDef = LevelDef.parse_json(_text("", "[0.0, 1.2344, -2.0]", "[0, 0, -3]", ""))
	if level.error != "":
		return level.error
	if level.start_position_mm != Vector3i(0, 1234, -2000) or level.start_facing_mm != Vector3i(0, 0, -3000):
		return "read %s facing %s" % [level.start_position_mm, level.start_facing_mm]
	if not level.start_facing().is_equal_approx(Vector3.FORWARD):
		return "facing %s" % level.start_facing()
	return ""


## A small valid level: two joined boxes along -z, edited by each case.
func _text(extra_box: String, start: String, facing: String, extra_top: String) -> String:
	return ("{\"boxes\": [{\"min\": [-4, -4, -20], \"max\": [4, 4, 4]}, "
			+ "{\"min\": [-3, -3, -40], \"max\": [3, 3, -18]}%s], "
			+ "\"start\": {\"position\": %s, \"facing\": %s}, "
			+ "\"robots\": [{\"id\": \"drone\", \"position\": [0, 0, -30], \"facing\": [0, 0, 1]}]%s}") \
			% [extra_box, start, facing, extra_top]


func test_rejections_name_the_problem() -> String:
	var start: String = "[0, 0, 0]"
	var facing: String = "[0, 0, -1]"
	var cases: Array[Array] = [
		[_text("", start, facing, ""), ""],
		[_text("", start, facing, ", \"music\": 1"), "unknown key \"music\""],
		[_text(", {\"min\": [0, 0, -30], \"max\": [2, 2, -25], \"size\": 1}", start, facing, ""),
			"box 2: unknown key \"size\""],
		["{\"boxes\": [{\"min\": [-4, -4, -20], \"max\": [4, 4, 4]}], \"start\": {\"position\": [0, 0, 0], "
			+ "\"facing\": [0, 0, -1], \"up\": [0, 1, 0]}, \"robots\": []}", "start: unknown key \"up\""],
		[_text(", {\"min\": [0, 0, -30], \"max\": [2, 0, -25]}", start, facing, ""),
			"box 2: min must be below max on every axis"],
		# Touches box 1 with a 1 m overlap: not joined.
		[_text(", {\"min\": [2, -3, -30], \"max\": [12, 3, -24]}", start, facing, ""),
			"box 2: not connected to box 0"],
		[_text("", "[3.5, 0, 0]", facing, ""), "start: position is not inside the level with 1.0 m to spare"],
		[_text("", start, facing, "").replace("[0, 0, -30]", "[0, 0, -45]"),
			"robot 1: position is not inside the level with 1.0 m to spare"],
	]
	for c: Array in cases:
		var level: LevelDef = LevelDef.parse_json(c[0])
		if level.error != c[1]:
			return "%s gave \"%s\", expected \"%s\"" % [c[0], level.error, c[1]]
		if c[1] != "" and (not level.union.boxes.is_empty() or not level.robots.spawns.is_empty()):
			return "a rejected level kept boxes or robots"
	return ""


func test_joined_needs_the_minimum_overlap_on_every_axis() -> String:
	var a: BoxBounds = BoxBounds.new(Vector3(-4, -4, -20), Vector3(4, 4, 4))
	var cases: Array[Array] = [
		[BoxBounds.new(Vector3(-3, -3, -40), Vector3(3, 3, -18)), true],
		[BoxBounds.new(Vector3(-3, -3, -40), Vector3(3, 3, -18.5)), false],
		[BoxBounds.new(Vector3(2, -3, -40), Vector3(10, 3, -10)), true],
		[BoxBounds.new(Vector3(2.5, -3, -40), Vector3(10, 3, -10)), false],
		[BoxBounds.new(Vector3(-3, 3, -40), Vector3(3, 10, -10)), false],
	]
	for c: Array in cases:
		var b: BoxBounds = c[0]
		if LevelDef.joined(a, b) != c[1] or LevelDef.joined(b, a) != c[1]:
			return "%s..%s: joined should be %s" % [b.min_corner, b.max_corner, c[1]]
	return ""
