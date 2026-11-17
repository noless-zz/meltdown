class_name LoopBridges
extends RefCounted

## Closes loops in a generated mine (#396, #411, GEN-5): after the chain is
## placed, two open connectors of the same size class that face each other
## along one axis (outward axes opposite) are joined by a tunnel, so a level
## has more than one way back to the exit (RUN-4, MAP-2).
##
## Read from `data/gen/generator.json`:
##
##     {"loop_min_m": 10, "loop_max_m": 60, "loop_max_count": 2,
##      "loop_max_offset_m": 20, "dead_end_min_open": 6, "loop_bias": 0.5}
##
## `dead_end_min_open` is not about loops but lives in the same file, so this
## class reads it too (#421, ARC-4): `MineGenerator.generate` takes it from
## here when given bridges, so the owner can tune how branchy levels feel
## without code. So does `loop_bias` (#438): how often the generator, choosing
## where to attach the next module, prefers a placement that leaves an open
## connector facing another (`LoopBias`). Placement, not the tunnel shape, is
## what limits the loop rate (#411).
##
## The gap is the distance between the two openings along their axis; the
## offset is how far apart their centres are across it. Openings exactly in
## line get a straight tunnel; others, up to the offset, a Z (`LoopShapes`):
## exactly facing pairs are rare with the shipped modules (#411). A bridge is
## the tunnel boxes plus a doorway box at each end, as `MineGenerator` adds for
## a join, so the level stays one piece under `LevelDef.joined`. It is made
## only when no tunnel box overlaps a placed box and each doorway overlaps no
## placed box but those of the module it opens into. One open connector is
## always left for the start.
##
## Pairs are tried lowest open-connector index first, then lowest partner, so
## the same seed gives the same level (GEN-2, ARC-2); nothing here is random.
## The caller hands over the file's text, because `gen/` never opens files.

const KEYS: Array[String] = [
	"loop_min_m", "loop_max_m", "loop_max_count", "loop_max_offset_m", "dead_end_min_open",
	"loop_bias",
]
## Upper bound on either gap key, metres: longer than any level is wide.
const MAX_GAP_M: float = 1000.0
## Upper bound on `dead_end_min_open`: far above any level's open connectors,
## so it only keeps the number a plain int.
const MAX_DEAD_END_MIN_OPEN: int = 1000

## Shortest and longest gap bridged, whole millimetres.
var min_gap_mm: int = 0
var max_gap_mm: int = 0
## Most bridges in one level.
var max_count: int = 0
## Furthest apart, across their axis, two bridged openings' centres may be, mm.
var max_offset_mm: int = 0
## Open connectors needed before a dead end may join (`MineGenerator`).
var dead_end_min_open: int = MineGenerator.DEAD_END_MIN_OPEN
## `loop_bias` in thousandths, so the draw against it is a whole number (GEN-2).
var loop_bias_permille: int = 0
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


## The bridge's boxes as corner pairs (tunnel boxes, then the doors at a and
## b), or empty when the two connectors do not face each other in range or it
## would not fit.
func _bridge(generator: MineGenerator, a: int, b: int) -> Array[Vector3i]:
	var from: ModuleConnector = generator.open_connectors[a]
	var to: ModuleConnector = generator.open_connectors[b]
	if from.size_class != to.size_class or from.axis() != to.axis() or from.axis_sign() == to.axis_sign():
		return []
	var axis: int = from.axis()
	var gap: int = (to.position_mm[axis] - from.position_mm[axis]) * from.axis_sign()
	if gap < min_gap_mm or gap > max_gap_mm:
		return []
	var shift: Vector3i = to.position_mm - from.position_mm
	shift[axis] = 0
	# Squared in 64-bit ints, so whole millimetres compare exactly (ARC-2).
	var shift_x: int = shift.x
	var shift_y: int = shift.y
	var shift_z: int = shift.z
	if shift_x * shift_x + shift_y * shift_y + shift_z * shift_z > max_offset_mm * max_offset_mm:
		return []
	var boxes: Array[Vector3i] = LoopShapes.straight(from, to) if shift == Vector3i.ZERO \
			else LoopShapes.z_shape(from, to)
	if boxes.is_empty():
		return []
	for index: int in range(0, boxes.size(), 2):
		if not _clear(generator, boxes[index], boxes[index + 1], -1):
			return []
	var door_a: Array[Vector3i] = MineGenerator.door_for(from)
	var door_b: Array[Vector3i] = MineGenerator.door_for(to)
	if not _clear(generator, door_a[0], door_a[1], generator.open_owner[a].x) \
			or not _clear(generator, door_b[0], door_b[1], generator.open_owner[b].x):
		return []
	boxes.append_array(door_a)
	boxes.append_array(door_b)
	return boxes


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
	var offset: float = float(data["loop_max_offset_m"])
	var dead_end: float = float(data["dead_end_min_open"])
	var bias: float = float(data["loop_bias"])
	if low <= 0.0 or low > MAX_GAP_M:
		return "key \"loop_min_m\" must be above 0 and at most %s" % MAX_GAP_M
	if high < low or high > MAX_GAP_M:
		return "key \"loop_max_m\" must be loop_min_m..%s" % MAX_GAP_M
	if count < 0.0 or count != floorf(count):
		return "key \"loop_max_count\" must be a whole number, at least 0"
	if offset < 0.0 or offset > MAX_GAP_M:
		return "key \"loop_max_offset_m\" must be 0..%s" % MAX_GAP_M
	if dead_end < 2.0 or dead_end > MAX_DEAD_END_MIN_OPEN or dead_end != floorf(dead_end):
		return "key \"dead_end_min_open\" must be a whole number, 2..%d" % MAX_DEAD_END_MIN_OPEN
	if bias < 0.0 or bias > 1.0:
		return "key \"loop_bias\" must be 0..1"
	min_gap_mm = roundi(low * RobotSpawn.SCALE)
	max_gap_mm = roundi(high * RobotSpawn.SCALE)
	max_count = int(count)
	max_offset_mm = roundi(offset * RobotSpawn.SCALE)
	dead_end_min_open = int(dead_end)
	loop_bias_permille = roundi(bias * LoopBias.SCALE)
	return ""
