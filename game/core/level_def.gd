class_name LevelDef
extends RefCounted

## A hand-built level read from a data file: its walls as a union of boxes, where
## the player starts, and the robots it starts with (GEN-5, CMB-3, ARC-4). The
## caller reads the file and hands over its text, because core never opens files.
##
## The file is one JSON object:
##
##     {"boxes": [{"min": [-6, -4, -40], "max": [6, 4, 6]}, ...],
##      "start": {"position": [0, 0, 0], "facing": [0, 0, -1]},
##      "robots": [{"id": "drone", "position": [0, -20, -42], "facing": [0, 1, 0]}],
##      "reactor": {"position": [0, -39, -114], "radius": 2.5, "hull": 400, "meltdown_seconds": 90},
##      "exit_radius": 4,
##      "debris": [{"position": [-3, -15, -45], "radius": 1, "after_seconds": 10}]}
##
## Corners, positions and facings are metres, read in whole millimetres like
## robot spawns, so a level reads the same on every run (ARC-2). `robots` uses
## the entry format of `RobotSpawnList`, which parses it. `reactor` is optional
## (RUN-2) and read by `ReactorState`; a level without one runs as before. Its
## optional `meltdown_base_seconds`, `meltdown_seconds_per_metre`,
## `meltdown_min_seconds` and `meltdown_max_seconds` scale the countdown with the
## escape path (RUN-5, `EscapePath`).
## `exit_radius` is optional too: the radius in metres of the exit sphere around
## the start (RUN-3). When it is left out the level takes the `LevelDefaults`
## handed to `parse_json`, which the loader reads from the data file (ARC-4). It
## is handed to the reactor, which carries it into the simulation and the replay.
## `debris` is optional too: spheres that fall during the meltdown (RUN-4), read
## by `MeltdownDebris`. Whether they leave a way out is the level validator's job.
##
## A level is rejected, with a message naming the problem, when a box's min is
## not below its max, a box cannot be reached from box 0, the start or a robot
## spawn is not held by the union with `CLEARANCE_M` to spare, the reactor's
## sphere is not held by the union, or a key is unknown or missing. Checking here, not when the level is flown, means a bad
## file never puts a ship in rock (see the #271 devlog).

const TOP_KEYS: Array[String] = ["boxes", "start", "robots"]
## Top-level keys a level may leave out.
const OPTIONAL_KEYS: Array[String] = ["reactor", "exit_radius", "debris"]
const BOX_KEYS: Array[String] = ["min", "max"]
const START_KEYS: Array[String] = ["position", "facing"]
## Two boxes are joined when they overlap by at least this much on every axis:
## the opening between them is at least this wide both ways, and each reaches
## this far into the other across the shared face.
const MIN_OVERLAP_M: float = 2.0
## Radius the union must hold, whole, at the start and at every spawn.
const CLEARANCE_M: float = 1.0

## The level's walls; empty when the text was rejected.
var union: BoxUnion = BoxUnion.new()
## The level's robots, unresolved (`RobotSpawnList.resolve` gives them types).
var robots: RobotSpawnList = RobotSpawnList.new()
var start_position_mm: Vector3i = Vector3i.ZERO
var start_facing_mm: Vector3i = Vector3i(0, 0, -RobotSpawn.SCALE)
## The level's reactor before the first tick, or null for a level without one.
var reactor: ReactorState = null
## The level's falling debris before the first tick, or null without a `debris` key.
var debris: MeltdownDebris = null
## Radius of the exit sphere around the start (RUN-3), also set on `reactor`.
var exit_radius_mm: int = LevelDefaults.FALLBACK_EXIT_RADIUS_MM
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a level file. On failure `error` is set and the level is
## empty, so nothing half-read is ever flown. `defaults` fills in what the file
## leaves out; the loader reads them from `res://data/level_defaults.json`.
static func parse_json(text: String, defaults: LevelDefaults = null) -> LevelDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	var problem: String = _check_keys(data, TOP_KEYS, OPTIONAL_KEYS)
	if problem != "":
		return _failed(problem)
	var level: LevelDef = LevelDef.new()
	if defaults != null:
		level.exit_radius_mm = defaults.exit_radius_mm
	problem = level._read_boxes(data["boxes"])
	if problem == "":
		problem = level._read_start(data["start"])
	if problem == "":
		problem = level._read_robots(data["robots"])
	if problem == "" and data.has("reactor"):
		problem = level._read_reactor(data["reactor"])
	if problem == "" and data.has("exit_radius"):
		problem = level._read_exit_radius(data["exit_radius"])
	if problem == "" and data.has("debris"):
		var read: MeltdownDebris = MeltdownDebris.parse(data["debris"])
		problem = read.error
		level.debris = read
	if problem == "":
		problem = level._check_connected()
	if problem == "":
		problem = level._check_held()
	if problem != "":
		return _failed(problem)
	return level


## Where the player starts, metres.
func start_position() -> Vector3:
	return Vector3(start_position_mm) / float(RobotSpawn.SCALE)


## The direction the player faces at the start, unit length.
func start_facing() -> Vector3:
	return Vector3(start_facing_mm).normalized()


## True if boxes `a` and `b` overlap by at least `MIN_OVERLAP_M` on every axis.
static func joined(a: BoxBounds, b: BoxBounds) -> bool:
	for axis: int in 3:
		var overlap: float = minf(a.max_corner[axis], b.max_corner[axis]) \
				- maxf(a.min_corner[axis], b.min_corner[axis])
		if overlap < MIN_OVERLAP_M:
			return false
	return true


## Indices of the boxes joined to box `index`, lowest first.
func neighbours(index: int) -> Array[int]:
	var found: Array[int] = []
	for other: int in union.boxes.size():
		if other != index and joined(union.boxes[index], union.boxes[other]):
			found.append(other)
	return found


func _read_boxes(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "key \"boxes\" must be a non-empty list"
	var entries: Array = value
	var boxes: Array[BoxBounds] = []
	for index: int in entries.size():
		var what: String = "box %d" % index
		if typeof(entries[index]) != TYPE_DICTIONARY:
			return "%s: must be a JSON object" % what
		var entry: Dictionary = entries[index]
		var problem: String = _check_keys(entry, BOX_KEYS)
		var read: Array[Vector3i] = []
		if problem == "":
			problem = RobotSpawn.read_mm(entry["min"], "min", read)
		if problem == "":
			problem = RobotSpawn.read_mm(entry["max"], "max", read)
		if problem != "":
			return "%s: %s" % [what, problem]
		for axis: int in 3:
			if read[0][axis] >= read[1][axis]:
				return "%s: min must be below max on every axis" % what
		var scale: float = float(RobotSpawn.SCALE)
		boxes.append(BoxBounds.new(Vector3(read[0]) / scale, Vector3(read[1]) / scale))
	union = BoxUnion.new(boxes)
	return ""


func _read_start(value: Variant) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "start: must be a JSON object"
	var entry: Dictionary = value
	var problem: String = _check_keys(entry, START_KEYS)
	var read: Array[Vector3i] = []
	if problem == "":
		problem = RobotSpawn.read_mm(entry["position"], "position", read)
	if problem == "":
		problem = RobotSpawn.read_mm(entry["facing"], "facing", read)
	if problem == "" and read[1] == Vector3i.ZERO:
		problem = "facing must not be zero"
	if problem != "":
		return "start: %s" % problem
	start_position_mm = read[0]
	start_facing_mm = read[1]
	return ""


func _read_robots(value: Variant) -> String:
	# Re-encoded so the spawn format has exactly one parser.
	var list: RobotSpawnList = RobotSpawnList.parse_json(JSON.stringify({"robots": value}))
	if list.error != "":
		return list.error
	robots = list
	return ""


func _read_reactor(value: Variant) -> String:
	# One place to set the exit in a level file: the top level.
	if typeof(value) == TYPE_DICTIONARY and (value as Dictionary).has("exit_radius"):
		return "reactor: unknown key \"exit_radius\" (it belongs at the top level)"
	var read: ReactorState = ReactorState.parse(value)
	if read.error != "":
		return read.error
	reactor = read
	# The default exit until a top-level `exit_radius` replaces it.
	reactor.exit_radius_mm = exit_radius_mm
	return ""


func _read_exit_radius(value: Variant) -> String:
	var read: Array[int] = []
	var problem: String = ReactorState.read_radius_mm(value, "exit_radius", read)
	if problem != "":
		return problem
	exit_radius_mm = read[0]
	if reactor != null:
		reactor.exit_radius_mm = exit_radius_mm
	return ""


## Every box reachable from box 0 through joined boxes, visited in index order.
func _check_connected() -> String:
	var reached: Array[bool] = []
	reached.resize(union.boxes.size())
	reached.fill(false)
	reached[0] = true
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in neighbours(index):
			if not reached[other]:
				reached[other] = true
				queue.append(other)
	for index: int in reached.size():
		if not reached[index]:
			return "box %d: not connected to box 0" % index
	return ""


func _check_held() -> String:
	if not union.holds(start_position(), CLEARANCE_M):
		return "start: position is not inside the level with %s m to spare" % CLEARANCE_M
	for index: int in robots.spawns.size():
		if not union.holds(robots.spawns[index].position(), CLEARANCE_M):
			return "robot %d: position is not inside the level with %s m to spare" \
					% [index + 1, CLEARANCE_M]
	if reactor != null and not union.holds(reactor.position(), reactor.radius()):
		return "reactor: position is not inside the level with its radius to spare"
	return ""


## "" or the first unknown key, then the first missing one, in `keys` order.
## Keys in `optional` may appear but need not.
static func _check_keys(data: Dictionary, keys: Array[String],
		optional: Array[String] = []) -> String:
	for key: Variant in data:
		if not keys.has(key) and not optional.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in keys:
		if not data.has(key):
			return "missing key \"%s\"" % key
	return ""


static func _failed(message: String) -> LevelDef:
	var level: LevelDef = LevelDef.new()
	level.error = message
	return level
