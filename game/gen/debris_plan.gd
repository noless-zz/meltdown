class_name DebrisPlan
extends RefCounted

## The meltdown debris a generated level gets (#398, RUN-4, GEN-1, ARC-4), read
## from `data/gen/debris.json`:
##
##     {"count": [2, 5], "radius": [1.5, 3], "after_seconds": [8, 60],
##      "min_start_distance": 15, "min_reactor_distance": 6}
##
## Each range is `[lowest, highest]`, both included. `count` is how many
## entries a level gets, `radius` their radius in metres and `after_seconds`
## how long after the reactor dies each falls. The two distances are metres of
## clear space between an entry's surface and the start point, and between an
## entry's surface and the reactor's surface. Radii and distances are held as
## whole millimetres and times as whole ticks, so placement is exact (ARC-2).
## The caller hands over the file's text, because `gen/` never opens files.
##
## `place` puts entries where the escape runs: in the modules holding the
## shortest route from the reactor to the start, each centred in one of those
## modules' boxes or in an opening between two of them. Whether an entry may
## really fall is not decided here: `DebrisRouteGuard` holds back any that
## would close the last route out when it falls due.

const KEYS: Array[String] = ["count", "radius", "after_seconds", "min_start_distance",
		"min_reactor_distance"]
## Largest radius an entry may have, metres: a cave-in, not a wall of rock.
const MAX_RADIUS_M: float = 20.0
## Latest an entry may fall, seconds after the reactor dies.
const MAX_AFTER_SECONDS: float = 3600.0
## Furthest a distance key may be, metres: far beyond any level.
const MAX_DISTANCE_M: float = 10000.0
## Draws of a spot for one entry before the placing gives up.
const TRIES: int = 64

var min_count: int = 0
var max_count: int = 0
var min_radius_mm: int = 1
var max_radius_mm: int = 1
var min_after_ticks: int = 1
var max_after_ticks: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


static func parse_json(text: String) -> DebrisPlan:
	var plan: DebrisPlan = DebrisPlan.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		plan.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return plan
	if typeof(json.data) != TYPE_DICTIONARY:
		plan.error = "top level must be a JSON object"
		return plan
	plan.error = plan._read(json.data)
	return plan


## The debris for `level`, built from `generator`, or null when there is none
## to place: no reactor, no route from it to the start, or a count of zero.
## Every draw comes from a generator seeded from `output_hash` and "debris", so
## the same seed gives the same debris, and the reactor, the robots and the
## generator itself are left as they were. Why fewer entries than drawn were
## placed goes to `generator.debris_note`.
func place(generator: MineGenerator, level: LevelDef, ship_radius: float) -> MeltdownDebris:
	if level.reactor == null:
		generator.debris_note = "no debris: the level has no reactor"
		return null
	var spots: Array[Vector3i] = escape_spots(generator, level, ship_radius)
	if spots.is_empty():
		generator.debris_note = "no debris: no route from the reactor to the start"
		return null
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "debris"])
	var wanted: int = min_count + _pick(rng, max_count - min_count + 1)
	var debris: MeltdownDebris = MeltdownDebris.new()
	for count: int in wanted:
		var radius: int = min_radius_mm + _pick(rng, max_radius_mm - min_radius_mm + 1)
		var ticks: int = min_after_ticks + _pick(rng, max_after_ticks - min_after_ticks + 1)
		var spot: int = -1
		for attempt: int in TRIES:
			if spots.is_empty():
				break
			var drawn: int = _pick(rng, spots.size())
			if fits(spots[drawn], radius, level):
				spot = drawn
				break
		if spot < 0:
			generator.debris_note = "placed %d of %d debris entries: no room found in %d tries" \
					% [count, wanted, TRIES]
			break
		debris.positions_mm.append(spots[spot])
		debris.radii_mm.append(radius)
		debris.after_ticks.append(ticks)
		debris.skipped.append(false)
		spots.remove_at(spot)
	return null if debris.size() == 0 else debris


## True if an entry of `radius_mm` centred on `point_mm` keeps the file's
## distances from `level`'s start and reactor, in whole millimetres.
func fits(point_mm: Vector3i, radius_mm: int, level: LevelDef) -> bool:
	if _distance_squared(point_mm, level.start_position_mm) \
			< _squared(radius_mm + min_start_distance_mm):
		return false
	if level.reactor != null and _distance_squared(point_mm, level.reactor.position_mm) \
			< _squared(radius_mm + min_reactor_distance_mm + level.reactor.radius_mm):
		return false
	return true


## The spots an entry may be centred on: the centre of every box of every module
## the shortest route from the reactor to the start passes through, then the
## centre of every opening between two such boxes, each in box order and each
## spot once. Empty without a reactor or a route.
static func escape_spots(generator: MineGenerator, level: LevelDef,
		ship_radius: float) -> Array[Vector3i]:
	var spots: Array[Vector3i] = []
	if level.reactor == null:
		return spots
	var all: Array[int] = []
	for box: int in generator.min_mm.size():
		all.append(box)
	var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
		level.start_position(), null, ship_radius)
	if route.length_mm == EscapePath.UNREACHABLE:
		return spots
	var on_route: Array[bool] = route_boxes(generator, route.points_mm)
	var seen: Dictionary[Vector3i, bool] = {}
	for box: int in on_route.size():
		if on_route[box]:
			_add(spots, seen, (generator.min_mm[box] + generator.max_mm[box]) / 2)
	for i: int in on_route.size():
		for j: int in range(i + 1, on_route.size()):
			if not on_route[i] or not on_route[j]:
				continue
			var low: Vector3i = generator.min_mm[i].max(generator.min_mm[j])
			var high: Vector3i = generator.max_mm[i].min(generator.max_mm[j])
			if low.x < high.x and low.y < high.y and low.z < high.z:
				_add(spots, seen, (low + high) / 2)
	return spots


## Per box: true if it belongs (as one of its boxes or its doorway) to a module
## holding one of `corners_mm`. Loop bridges belong to no module.
static func route_boxes(generator: MineGenerator, corners_mm: Array[Vector3i]) -> Array[bool]:
	var owner: Array[int] = []
	owner.resize(generator.min_mm.size())
	owner.fill(-1)
	for index: int in generator.placements.size():
		var placement: ModulePlacement = generator.placements[index]
		for box: int in range(placement.first_box, placement.end_box):
			owner[box] = index
		if placement.door_box >= 0:
			owner[placement.door_box] = index
	var modules: Array[bool] = []
	modules.resize(generator.placements.size())
	modules.fill(false)
	for corner: Vector3i in corners_mm:
		for box: int in owner.size():
			if owner[box] >= 0 and _holds(generator, box, corner):
				modules[owner[box]] = true
	var boxes: Array[bool] = []
	for box: int in owner.size():
		boxes.append(owner[box] >= 0 and modules[owner[box]])
	return boxes


func _read(data: Dictionary) -> String:
	var unknown: Array[String] = []
	for key: Variant in data:
		if not KEYS.has(key):
			unknown.append("\"%s\"" % str(key))
	if not unknown.is_empty():
		return "unknown key %s" % ", ".join(unknown)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("\"%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = _read_range(data["count"], "count", 1.0, 0.0, 1000.0, "a whole number", counts)
	if problem != "":
		return problem
	var radii: Array[int] = []
	problem = _read_range(data["radius"], "radius", RobotSpawn.SCALE, 0.001, MAX_RADIUS_M, "metres", radii)
	if problem != "":
		return problem
	var ticks: Array[int] = []
	problem = _read_range(data["after_seconds"], "after_seconds", MeltdownDebris.TICKS_PER_SECOND,
		1.0 / MeltdownDebris.TICKS_PER_SECOND, MAX_AFTER_SECONDS, "seconds", ticks)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance"]:
		var value: Variant = data[key]
		if not _is_number(value) or float(value) < 0.0 or float(value) > MAX_DISTANCE_M:
			return "%s must be a number of metres from 0 to %s" % [key, MAX_DISTANCE_M]
		distances.append(roundi(float(value) * RobotSpawn.SCALE))
	min_count = counts[0]
	max_count = counts[1]
	min_radius_mm = radii[0]
	max_radius_mm = radii[1]
	min_after_ticks = ticks[0]
	max_after_ticks = ticks[1]
	min_start_distance_mm = distances[0]
	min_reactor_distance_mm = distances[1]
	return ""


## Reads `[lowest, highest]` into `into` as whole units of 1/`scale`. With a
## `scale` of 1 the values must already be whole numbers.
static func _read_range(value: Variant, key: String, scale: float, least: float, most: float,
		unit: String, into: Array[int]) -> String:
	var shape: String = "%s must be [lowest, highest], each %s from %s to %s" % [key, unit, least, most]
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return shape
	for entry: Variant in value:
		if not _is_number(entry) or float(entry) < least or float(entry) > most:
			return shape
		if scale == 1.0 and float(entry) != floorf(float(entry)):
			return shape
		into.append(roundi(float(entry) * scale))
	if into[1] < into[0]:
		return "%s: highest must not be below lowest" % key
	return ""


static func _is_number(value: Variant) -> bool:
	return (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and is_finite(float(value))


static func _add(spots: Array[Vector3i], seen: Dictionary[Vector3i, bool], spot: Vector3i) -> void:
	if not seen.has(spot):
		seen[spot] = true
		spots.append(spot)


static func _holds(generator: MineGenerator, box: int, point: Vector3i) -> bool:
	for axis: int in 3:
		if point[axis] < generator.min_mm[box][axis] or point[axis] > generator.max_mm[box][axis]:
			return false
	return true


static func _distance_squared(a: Vector3i, b: Vector3i) -> int:
	var d: Vector3i = a - b
	return d.x * d.x + d.y * d.y + d.z * d.z


static func _squared(value: int) -> int:
	return value * value


## A whole number from 0 up to, not including, `size`.
static func _pick(rng: RandomNumberGenerator, size: int) -> int:
	return int(rng.randi() % size)
