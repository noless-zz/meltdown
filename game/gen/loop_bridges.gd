class_name LoopBridges
extends RefCounted

## Closes loops in a generated mine (#396, GEN-5): after the chain is placed,
## two open connectors of the same size class that face each other along one
## axis (outward axes opposite, centres on one line along it) are joined by a
## straight tunnel, so a level has more than one way back to the exit (RUN-4,
## MAP-2).
##
## Read from `data/gen/generator.json`:
##
##     {"loop_min_m": 10, "loop_max_m": 60, "loop_max_count": 2}
##
## The gap is the distance between the two openings along their axis. A bridge
## is the tunnel box (the connector's square, face to face) plus a doorway box
## at each end, as `MineGenerator` adds for a join, so the level stays one
## piece under `LevelDef.joined`. It is made only when the tunnel overlaps no
## placed box and each doorway overlaps no placed box but those of the module
## it opens into. One open connector is always left for the start.
##
## Pairs are tried lowest open-connector index first, then lowest partner, so
## the same seed gives the same level (GEN-2, ARC-2); nothing here is random.
## The caller hands over the file's text, because `gen/` never opens files.

const KEYS: Array[String] = ["loop_min_m", "loop_max_m", "loop_max_count"]
## Upper bound on either gap key, metres: longer than any level is wide.
const MAX_GAP_M: float = 1000.0

## Shortest and longest gap bridged, whole millimetres.
var min_gap_mm: int = 0
var max_gap_mm: int = 0
## Most bridges in one level.
var max_count: int = 0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


static func parse_json(text: String) -> LoopBridges:
	var bridges: LoopBridges = LoopBridges.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		bridges.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return bridges
	if typeof(json.data) != TYPE_DICTIONARY:
		bridges.error = "top level must be a JSON object"
		return bridges
	bridges.error = bridges._read(json.data)
	return bridges


## Bridges `generator`'s facing open connectors, adding the boxes and taking
## the bridged connectors off its open list. Returns how many were made.
func apply(generator: MineGenerator) -> int:
	var made: int = 0
	var used: Array[bool] = []
	used.resize(generator.open_connectors.size())
	used.fill(false)
	var left: int = generator.open_connectors.size()
	for a: int in generator.open_connectors.size():
		if made >= max_count or left <= 2:
			break
		if used[a]:
			continue
		for b: int in range(a + 1, generator.open_connectors.size()):
			if used[b]:
				continue
			var boxes: Array[Vector3i] = _bridge(generator, a, b)
			if boxes.is_empty():
				continue
			for index: int in range(0, boxes.size(), 2):
				generator.add_box(boxes[index], boxes[index + 1])
			used[a] = true
			used[b] = true
			left -= 2
			made += 1
			break
	for index: int in range(used.size() - 1, -1, -1):
		if used[index]:
			generator.open_connectors.remove_at(index)
			generator.open_owner.remove_at(index)
	return made


## The bridge's boxes as corner pairs [tunnel, door at a, door at b], or empty
## when the two connectors do not face each other in range or it would not fit.
func _bridge(generator: MineGenerator, a: int, b: int) -> Array[Vector3i]:
	var from: ModuleConnector = generator.open_connectors[a]
	var to: ModuleConnector = generator.open_connectors[b]
	if from.size_class != to.size_class or from.axis() != to.axis() or from.axis_sign() == to.axis_sign():
		return []
	var axis: int = from.axis()
	for other: int in 3:
		if other != axis and from.position_mm[other] != to.position_mm[other]:
			return []
	var gap: int = (to.position_mm[axis] - from.position_mm[axis]) * from.axis_sign()
	if gap < min_gap_mm or gap > max_gap_mm:
		return []
	var half: int = from.size_mm() / 2
	var low: Vector3i = from.position_mm - Vector3i(half, half, half)
	var high: Vector3i = from.position_mm + Vector3i(half, half, half)
	low[axis] = mini(from.position_mm[axis], to.position_mm[axis])
	high[axis] = maxi(from.position_mm[axis], to.position_mm[axis])
	var door_a: Array[Vector3i] = MineGenerator.door_for(from)
	var door_b: Array[Vector3i] = MineGenerator.door_for(to)
	if not _clear(generator, low, high, -1) \
			or not _clear(generator, door_a[0], door_a[1], generator.open_owner[a].x) \
			or not _clear(generator, door_b[0], door_b[1], generator.open_owner[b].x):
		return []
	return [low, high, door_a[0], door_a[1], door_b[0], door_b[1]]


## True if the box overlaps no placed box, apart from those of placement
## `allowed` (-1 for none).
static func _clear(generator: MineGenerator, low: Vector3i, high: Vector3i, allowed: int) -> bool:
	var first: int = -1
	var end: int = -1
	if allowed >= 0:
		first = generator.placements[allowed].first_box
		end = generator.placements[allowed].end_box
	for index: int in generator.min_mm.size():
		if index >= first and index < end:
			continue
		if MineGenerator.overlaps(low, high, generator.min_mm[index], generator.max_mm[index]):
			return false
	return true


## "" or the first unknown key, else every missing key, else the first bad value.
func _read(data: Dictionary) -> String:
	for key: Variant in data:
		if not KEYS.has(key):
			return "unknown key \"%s\"" % key
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("missing key \"%s\"" % key)
	if not missing.is_empty():
		return ", ".join(missing)
	for key: String in KEYS:
		var value: Variant = data[key]
		# JSON numbers arrive as floats.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT or not is_finite(float(value)):
			return "key \"%s\" must be a number" % key
	var low: float = float(data["loop_min_m"])
	var high: float = float(data["loop_max_m"])
	var count: float = float(data["loop_max_count"])
	if low <= 0.0 or low > MAX_GAP_M:
		return "key \"loop_min_m\" must be above 0 and at most %s" % MAX_GAP_M
	if high < low or high > MAX_GAP_M:
		return "key \"loop_max_m\" must be loop_min_m..%s" % MAX_GAP_M
	if count < 0.0 or count != floorf(count):
		return "key \"loop_max_count\" must be a whole number, at least 0"
	min_gap_mm = roundi(low * RobotSpawn.SCALE)
	max_gap_mm = roundi(high * RobotSpawn.SCALE)
	max_count = int(count)
	return ""
