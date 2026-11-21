class_name MinerPlan
extends RefCounted

## The trapped miners a generated level gets (#938, SLV-3, CRW-1, GEN-1, ARC-4),
## read from `data/gen/miners.json`:
##
##     {"count": [0, 2], "min_start_distance": 20, "min_reactor_distance": 8,
##      "min_robot_distance": 4}
##
## `count` is `[lowest, highest]`, both included. The distances are metres from
## the start, from the reactor's centre and from each robot's centre, held as
## whole millimetres so placement is exact (ARC-2). The caller hands over the
## file's text, because `gen/` never opens files. Miners are crew to rescue
## (CRW-1); picking them up comes later, so here they are only positions.
##
## `place` puts each miner in a module box the ship can reach from the start,
## with a ship's diameter clear of that box's faces, of the reactor's surface,
## of every robot's surface and of every miner already placed, and at least the
## file's distances away. Its draws come from their own generator, seeded from
## `output_hash` and "miners", so the reactor, robots and debris of a seed are
## the same with or without miners (GEN-2).

const KEYS: Array[String] = ["count", "min_start_distance", "min_reactor_distance",
		"min_robot_distance"]
## Most miners a level may ask for.
const MAX_COUNT: int = 100
## Furthest a distance key may be, metres: far beyond any level.
const MAX_DISTANCE_M: float = 10000.0
## Draws for one miner before the placing gives up.
const TRIES: int = 64

var min_count: int = 0
var max_count: int = 0
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
var min_robot_distance_mm: int = 0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


static func parse_json(text: String) -> MinerPlan:
	var plan: MinerPlan = MinerPlan.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		plan.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return plan
	if typeof(json.data) != TYPE_DICTIONARY:
		plan.error = "top level must be a JSON object"
		return plan
	plan.error = plan._read(json.data)
	return plan


## The miners for `level`, built from `generator`, as whole-millimetre
## positions; why fewer than drawn were placed goes to `generator.miner_note`.
## `robot_radii_mm` gives the radius of the level's unresolved robots by id.
func place(generator: MineGenerator, level: LevelDef, ship_radius: float,
		robot_radii_mm: Dictionary[String, int] = {}) -> Array[Vector3i]:
	var placed: Array[Vector3i] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "miners"])
	var wanted: int = min_count + _pick(rng, max_count - min_count + 1)
	if wanted == 0:
		return placed
	var boxes: Array[int] = reachable_module_boxes(level)
	if boxes.is_empty():
		generator.miner_note = "placed 0 of %d miners: no module box reachable from the start" % wanted
		return placed
	var diameter: int = roundi(2.0 * ship_radius * RobotSpawn.SCALE)
	var robot_gaps: Array[int] = []
	for spawn: RobotSpawn in level.robots.spawns:
		var radius: int = maxi(RobotChecks.radius_mm(spawn, robot_radii_mm), 0)
		robot_gaps.append(maxi(min_robot_distance_mm, radius + diameter))
	for count: int in wanted:
		var found: bool = false
		for attempt: int in TRIES:
			var drawn: Array[Vector3i] = _draw(generator, boxes[_pick(rng, boxes.size())], diameter, rng)
			if not drawn.is_empty() and _clear(drawn[0], level, diameter, robot_gaps, placed):
				placed.append(drawn[0])
				found = true
				break
		if not found:
			generator.miner_note = "placed %d of %d miners: no room found in %d tries" \
					% [count, wanted, TRIES]
			return placed
	return placed


## The boxes of `level` that belong to a module (not a doorway or a bridge)
## and are joined, box to box, to the box holding the start; lowest first.
static func reachable_module_boxes(level: LevelDef) -> Array[int]:
	var found: Array[int] = []
	var boxes: Array[BoxBounds] = level.union.boxes
	var start: int = -1
	for index: int in boxes.size():
		if boxes[index].holds(level.start_position(), 0.0):
			start = index
			break
	if start < 0:
		return found
	var reached: Array[bool] = []
	reached.resize(boxes.size())
	reached.fill(false)
	reached[start] = true
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in boxes.size():
			if not reached[other] and LevelDef.joined(boxes[index], boxes[other]):
				reached[other] = true
				queue.append(other)
	for index: int in boxes.size():
		if reached[index] and index < level.box_modules.size() and level.box_modules[index] >= 0:
			found.append(index)
	return found


## A point in `box` a ship's diameter clear of its faces, alone in the list;
## empty when the box is too small for it.
static func _draw(generator: MineGenerator, box: int, diameter: int,
		rng: RandomNumberGenerator) -> Array[Vector3i]:
	var point: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		var low: int = generator.min_mm[box][axis] + diameter
		var high: int = generator.max_mm[box][axis] - diameter
		if high < low:
			return []
		point[axis] = low + _pick(rng, high - low + 1)
	return [point]


func _clear(point: Vector3i, level: LevelDef, diameter: int, robot_gaps: Array[int],
		placed: Array[Vector3i]) -> bool:
	if _distance_squared(point, level.start_position_mm) < _squared(min_start_distance_mm):
		return false
	if level.reactor != null:
		var gap: int = maxi(min_reactor_distance_mm, level.reactor.radius_mm + diameter)
		if _distance_squared(point, level.reactor.position_mm) < _squared(gap):
			return false
	for index: int in robot_gaps.size():
		if _distance_squared(point, level.robots.spawns[index].position_mm) < _squared(robot_gaps[index]):
			return false
	for other: Vector3i in placed:
		if _distance_squared(point, other) < _squared(diameter):
			return false
	return true


func _read(data: Dictionary) -> String:
	for key: Variant in data:
		if not KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("\"%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = DebrisPlan._read_range(data["count"], "count", 1.0, 0.0,
			float(MAX_COUNT), "a whole number", counts)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance", "min_robot_distance"]:
		var value: Variant = data[key]
		if not DebrisPlan._is_number(value) or float(value) < 0.0 or float(value) > MAX_DISTANCE_M:
			return "%s must be a number of metres from 0 to %s" % [key, MAX_DISTANCE_M]
		distances.append(roundi(float(value) * RobotSpawn.SCALE))
	min_count = counts[0]
	max_count = counts[1]
	min_start_distance_mm = distances[0]
	min_reactor_distance_mm = distances[1]
	min_robot_distance_mm = distances[2]
	return ""


static func _distance_squared(a: Vector3i, b: Vector3i) -> int:
	var d: Vector3i = a - b
	return d.x * d.x + d.y * d.y + d.z * d.z


static func _squared(value: int) -> int:
	return value * value


## A whole number from 0 up to, not including, `size`.
static func _pick(rng: RandomNumberGenerator, size: int) -> int:
	return int(rng.randi() % size)
