class_name DebrisDoors
extends RefCounted

## Failed blast doors for a generated level (#462, RUN-4, GEN-3, ARC-4): box
## entries of `MeltdownDebris` dropped across module openings during the
## meltdown, so the mine changes in more than one way on the way out. Read from
## the optional `doors` section of `data/gen/debris.json`:
##
##     "doors": {"count": [0, 2], "thickness": 0.5, "after_seconds": [10, 60],
##               "min_start_distance": 15, "min_reactor_distance": 6,
##               "min_robot_distance": 2}
##
## `count` and `after_seconds` are `[lowest, highest]` ranges like the
## spheres'; `thickness` is the slab's depth through the opening in metres; the
## three distances are metres of clear space between the slab and the start
## point, the reactor's surface and each robot spawn's surface. Kept apart from
## `DebrisPlan`, which is near its size limit.
##
## An opening is the doorway box `MineGenerator` adds where two modules join.
## A door is centred on the plane the two modules meet in and covers the whole
## opening square, so with it down nothing passes. Openings of the start's
## module are never used. Any other opening may be, the escape route's
## included: when a door falls due, `DebrisRouteGuard` holds it back if it
## would close the last route out, as it does for spheres. Loop bridges are not
## module openings and get no doors.
##
## Every draw comes from generators seeded with `output_hash` and "debris
## doors", apart from the spheres', so adding doors leaves `output_hash`, the
## reactor, the robots and every sphere entry as they were (ARC-2).

const KEYS: Array[String] = ["count", "thickness", "after_seconds", "min_start_distance",
		"min_reactor_distance", "min_robot_distance"]
## Bounds of `thickness`, metres. A doorway reaches 3 m into each module, so
## the thickest slab still sits inside it.
const MIN_THICKNESS_M: float = 0.1
const MAX_THICKNESS_M: float = 4.0

var min_count: int = 0
var max_count: int = 0
var thickness_mm: int = 500
var min_after_ticks: int = 1
var max_after_ticks: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
var min_robot_distance_mm: int = 0


## Reads the `doors` section into a new `DebrisDoors`, or returns the problem
## with every key named "doors.<key>".
static func read(value: Variant, into: Array[DebrisDoors]) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "doors must be a JSON object"
	var data: Dictionary = value
	var unknown: Array[String] = []
	for key: Variant in data:
		if not KEYS.has(key):
			unknown.append("\"doors.%s\"" % str(key))
	if not unknown.is_empty():
		return "unknown key %s" % ", ".join(unknown)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("\"doors.%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = DebrisPlan._read_range(data["count"], "doors.count", 1.0, 0.0, 1000.0,
		"a whole number", counts)
	if problem != "":
		return problem
	var thickness: Variant = data["thickness"]
	if not DebrisPlan._is_number(thickness) or float(thickness) < MIN_THICKNESS_M \
			or float(thickness) > MAX_THICKNESS_M:
		return "doors.thickness must be a number of metres from %s to %s" \
				% [MIN_THICKNESS_M, MAX_THICKNESS_M]
	var ticks: Array[int] = []
	problem = DebrisPlan._read_range(data["after_seconds"], "doors.after_seconds",
		MeltdownDebris.TICKS_PER_SECOND, 1.0 / MeltdownDebris.TICKS_PER_SECOND,
		DebrisPlan.MAX_AFTER_SECONDS, "seconds", ticks)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance", "min_robot_distance"]:
		var distance: Variant = data[key]
		if not DebrisPlan._is_number(distance) or float(distance) < 0.0 \
				or float(distance) > DebrisPlan.MAX_DISTANCE_M:
			return "doors.%s must be a number of metres from 0 to %s" % [key, DebrisPlan.MAX_DISTANCE_M]
		distances.append(roundi(float(distance) * RobotSpawn.SCALE))
	var doors: DebrisDoors = DebrisDoors.new()
	doors.min_count = counts[0]
	doors.max_count = counts[1]
	doors.thickness_mm = roundi(float(thickness) * RobotSpawn.SCALE)
	doors.min_after_ticks = ticks[0]
	doors.max_after_ticks = ticks[1]
	doors.min_start_distance_mm = distances[0]
	doors.min_reactor_distance_mm = distances[1]
	doors.min_robot_distance_mm = distances[2]
	into.append(doors)
	return ""


## Appends this level's doors to `debris`, after its spheres. `robot_radii_mm`
## is each robot's radius in spawn order and `fall_limit` the latest tick a
## door may fall on (`DebrisPlan.fall_limit_ticks`). Returns why fewer doors
## than drawn were placed, or "".
func place(generator: MineGenerator, level: LevelDef, debris: MeltdownDebris,
		robot_radii_mm: Array[int], fall_limit: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "debris doors"])
	var fall_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	fall_rng.seed = hash([generator.output_hash(), "debris doors fall"])
	var wanted: int = min_count + DebrisPlan._pick(rng, max_count - min_count + 1)
	if wanted == 0:
		return ""
	var free: Array[int] = []
	for box: int in openings(generator):
		if _fits(generator, box, level, robot_radii_mm):
			free.append(box)
	# Spheres built without sizes leave the list short; a door needs its own.
	while debris.sizes_mm.size() < debris.size():
		debris.sizes_mm.append(Vector3i.ZERO)
	var placed: int = 0
	while placed < wanted and not free.is_empty():
		var box: int = free.pop_at(DebrisPlan._pick(rng, free.size()))
		var ticks: int = min_after_ticks + DebrisPlan._pick(rng, max_after_ticks - min_after_ticks + 1)
		debris.positions_mm.append(centre_mm(generator, box))
		debris.radii_mm.append(0)
		debris.sizes_mm.append(size_mm(generator, box))
		debris.after_ticks.append(_within(ticks, fall_limit, fall_rng))
		debris.skipped.append(false)
		placed += 1
	if placed == wanted:
		return ""
	return "placed %d of %d doors: only %d openings clear of the start, reactor and robots" \
			% [placed, wanted, placed]


## The doorway boxes a door may close, in placement order: every module join
## but those of the start's module.
static func openings(generator: MineGenerator) -> Array[int]:
	var found: Array[int] = []
	if generator.open_owner.is_empty():
		return found
	var start: int = generator.open_owner[0].x
	for index: int in generator.placements.size():
		var placement: ModulePlacement = generator.placements[index]
		if placement.door_box < 0 or index == start or placement.parent == start:
			continue
		found.append(placement.door_box)
	return found


## The axis a doorway box runs through: its shortest side, since it reaches
## `DOOR_DEPTH_MM` into each module (6 m in all) and every opening is wider.
static func through_axis(generator: MineGenerator, box: int) -> int:
	var extent: Vector3i = generator.max_mm[box] - generator.min_mm[box]
	var axis: int = 0
	for other: int in [1, 2]:
		if extent[other] < extent[axis]:
			axis = other
	return axis


## Where a door across doorway `box` is centred: on the plane the modules meet.
static func centre_mm(generator: MineGenerator, box: int) -> Vector3i:
	return (generator.min_mm[box] + generator.max_mm[box]) / 2


## A door's full size: the opening square across, `thickness_mm` through.
func size_mm(generator: MineGenerator, box: int) -> Vector3i:
	var extent: Vector3i = generator.max_mm[box] - generator.min_mm[box]
	extent[through_axis(generator, box)] = thickness_mm
	return extent


func _fits(generator: MineGenerator, box: int, level: LevelDef, robot_radii_mm: Array[int]) -> bool:
	var centre: Vector3i = centre_mm(generator, box)
	var half: Vector3i = size_mm(generator, box) / 2
	if _gap_squared(centre, half, level.start_position_mm) < _squared(min_start_distance_mm):
		return false
	if level.reactor != null and _gap_squared(centre, half, level.reactor.position_mm) \
			< _squared(min_reactor_distance_mm + level.reactor.radius_mm):
		return false
	for index: int in level.robots.spawns.size():
		if _gap_squared(centre, half, level.robots.spawns[index].position_mm) \
				< _squared(min_robot_distance_mm + robot_radii_mm[index]):
			return false
	return true


## `ticks`, or when it is past `limit` a fresh draw in `min_after_ticks..limit`,
## as `DebrisPlan` does for spheres.
func _within(ticks: int, limit: int, fall_rng: RandomNumberGenerator) -> int:
	if ticks <= limit:
		return ticks
	if min_after_ticks >= limit:
		return limit
	return min_after_ticks + DebrisPlan._pick(fall_rng, limit - min_after_ticks + 1)


## Squared millimetres from `point` to the nearest point of the box around
## `centre` with half sizes `half`; 0 inside it.
static func _gap_squared(centre: Vector3i, half: Vector3i, point: Vector3i) -> int:
	var local: Vector3i = point - centre
	var outside: Vector3i = local - local.clamp(-half, half)
	return outside.x * outside.x + outside.y * outside.y + outside.z * outside.z


static func _squared(value: int) -> int:
	return value * value
