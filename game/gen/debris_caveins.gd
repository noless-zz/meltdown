class_name DebrisCaveins
extends RefCounted

## Cave-ins for a generated level (#514, RUN-4, GEN-3, ARC-4): solid box
## entries of `MeltdownDebris` that come down inside a straight tunnel, across
## it, rather than at a doorway like `DebrisDoors`. Read from the optional
## `caveins` section of `data/gen/debris.json`:
##
##     "caveins": {"count": [0, 1], "thickness": 1.0, "after_seconds": [10, 60],
##                 "min_start_distance": 15, "min_reactor_distance": 6,
##                 "min_robot_distance": 2}
##
## Keys are read like the `doors` section's: `count` and `after_seconds` are
## `[lowest, highest]` ranges, `thickness` the slab's depth along the tunnel in
## metres, and the three distances metres of clear space between the slab and
## the start point, the reactor's surface and each robot spawn's surface.
##
## A straight tunnel is a placed module with exactly two connectors facing
## opposite ways on one line. The cave-in is centred on the middle of that line,
## square to it, `thickness` deep along it and covering the module box's whole
## cross-section there, so `BoxSplit` splits the box in two when it falls (#868)
## and the route model, the map, the guard and the bot all treat it as closed.
## Rooms, corners, shafts with a side door and the start's module get none.
##
## Every draw comes from generators seeded with `output_hash` and "debris
## caveins", apart from the spheres', the doors' and the fires', so adding the
## section leaves `output_hash`, the reactor, the robots and every other entry
## as they were (ARC-2). `DebrisPlan` lists cave-ins after the doors and before
## the fires and trims again once they are in: they are the highest-numbered
## solid entries, so `DebrisEscape.trim` drops them before any earlier one.

const KEYS: Array[String] = ["count", "thickness", "after_seconds", "min_start_distance",
		"min_reactor_distance", "min_robot_distance"]
## Bounds of `thickness`, metres: a slab, not a plug filling the tunnel.
const MIN_THICKNESS_M: float = 0.1
const MAX_THICKNESS_M: float = 10.0

var min_count: int = 0
var max_count: int = 0
var thickness_mm: int = 1000
var min_after_ticks: int = 1
var max_after_ticks: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
var min_robot_distance_mm: int = 0


## Reads the `caveins` section into a new `DebrisCaveins`, or returns the
## problem with every key named "caveins.<key>".
static func read(value: Variant, into: Array[DebrisCaveins]) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "caveins must be a JSON object"
	var data: Dictionary = value
	var unknown: Array[String] = []
	for key: Variant in data:
		if not KEYS.has(key):
			unknown.append("\"caveins.%s\"" % str(key))
	if not unknown.is_empty():
		return "unknown key %s" % ", ".join(unknown)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("\"caveins.%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = DebrisPlan._read_range(data["count"], "caveins.count", 1.0, 0.0, 1000.0,
		"a whole number", counts)
	if problem != "":
		return problem
	var thickness: Variant = data["thickness"]
	if not DebrisPlan._is_number(thickness) or float(thickness) < MIN_THICKNESS_M \
			or float(thickness) > MAX_THICKNESS_M:
		return "caveins.thickness must be a number of metres from %s to %s" \
				% [MIN_THICKNESS_M, MAX_THICKNESS_M]
	var ticks: Array[int] = []
	problem = DebrisPlan._read_range(data["after_seconds"], "caveins.after_seconds",
		MeltdownDebris.TICKS_PER_SECOND, 1.0 / MeltdownDebris.TICKS_PER_SECOND,
		DebrisPlan.MAX_AFTER_SECONDS, "seconds", ticks)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance", "min_robot_distance"]:
		var distance: Variant = data[key]
		if not DebrisPlan._is_number(distance) or float(distance) < 0.0 \
				or float(distance) > DebrisPlan.MAX_DISTANCE_M:
			return "caveins.%s must be a number of metres from 0 to %s" % [key, DebrisPlan.MAX_DISTANCE_M]
		distances.append(roundi(float(distance) * RobotSpawn.SCALE))
	var caveins: DebrisCaveins = DebrisCaveins.new()
	caveins.min_count = counts[0]
	caveins.max_count = counts[1]
	caveins.thickness_mm = roundi(float(thickness) * RobotSpawn.SCALE)
	caveins.min_after_ticks = ticks[0]
	caveins.max_after_ticks = ticks[1]
	caveins.min_start_distance_mm = distances[0]
	caveins.min_reactor_distance_mm = distances[1]
	caveins.min_robot_distance_mm = distances[2]
	into.append(caveins)
	return ""


## Appends this level's cave-ins to `debris`, then, with `validator`, trims
## until the escape fits its margin again. `robot_radii_mm` is each robot's
## radius in spawn order, `fall_limit` the latest tick one may fall on
## (`DebrisPlan.fall_limit_ticks`) and `ship_radius` the ship's, in metres.
## The cave-ins are the highest-numbered solid entries, so the trim drops them
## before any earlier entry, and the entries kept before stay as they were.
## Returns why fewer cave-ins than drawn were kept, as notes.
func place(generator: MineGenerator, level: LevelDef, debris: MeltdownDebris,
		robot_radii_mm: Array[int], fall_limit: int, ship_radius: float,
		validator: LevelValidator) -> Array[String]:
	var notes: Array[String] = []
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "debris caveins"])
	var fall_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	fall_rng.seed = hash([generator.output_hash(), "debris caveins fall"])
	var wanted: int = min_count + DebrisPlan._pick(rng, max_count - min_count + 1)
	if wanted == 0:
		return notes
	var free: Array[int] = []
	for placement: int in tunnels(generator):
		if _fits(generator, placement, level, robot_radii_mm):
			free.append(placement)
	if free.is_empty():
		notes.append("placed 0 of %d cave-ins: no straight tunnel clear of the start, reactor and robots"
				% wanted)
		return notes
	# Spheres built without sizes leave the list short; a cave-in needs its own.
	while debris.sizes_mm.size() < debris.size():
		debris.sizes_mm.append(Vector3i.ZERO)
	var placed: int = 0
	while placed < wanted and not free.is_empty():
		var placement: int = free.pop_at(DebrisPlan._pick(rng, free.size()))
		var ticks: int = min_after_ticks + DebrisPlan._pick(rng, max_after_ticks - min_after_ticks + 1)
		debris.positions_mm.append(centre_mm(generator, placement))
		debris.radii_mm.append(0)
		debris.sizes_mm.append(size_mm(generator, placement))
		debris.after_ticks.append(_within(ticks, fall_limit, fall_rng))
		debris.skipped.append(false)
		placed += 1
	if placed < wanted:
		notes.append("placed %d of %d cave-ins: only %d straight tunnels clear of the start, reactor and robots"
				% [placed, wanted, placed])
	if validator != null:
		var dropped: int = DebrisEscape.trim(level, debris, ship_radius,
				validator.escape_speed_mps, validator.escape_margin)
		if dropped > 0:
			notes.append("%d cave-ins dropped to keep the escape in time" % dropped)
	return notes


## The placements a cave-in may go in, in placement order: every straight
## tunnel but the start's module.
static func tunnels(generator: MineGenerator) -> Array[int]:
	var found: Array[int] = []
	if generator.open_owner.is_empty():
		return found
	var start: int = generator.open_owner[0].x
	for index: int in generator.placements.size():
		if index != start and is_straight(generator.placements[index]) \
				and _box_at(generator, index) >= 0:
			found.append(index)
	return found


## True for a module with exactly two connectors, facing opposite ways along
## one axis, on one line along it.
static func is_straight(placement: ModulePlacement) -> bool:
	if placement.connectors.size() != 2:
		return false
	var a: ModuleConnector = placement.connectors[0]
	var b: ModuleConnector = placement.connectors[1]
	if a.axis() != b.axis() or a.axis_sign() == b.axis_sign():
		return false
	var along: int = a.axis()
	for axis: int in 3:
		if axis != along and a.position_mm[axis] != b.position_mm[axis]:
			return false
	return true


## The middle of the line between a straight tunnel's two connectors.
static func centre_mm(generator: MineGenerator, placement: int) -> Vector3i:
	var connectors: Array[ModuleConnector] = generator.placements[placement].connectors
	return (connectors[0].position_mm + connectors[1].position_mm) / 2


## A cave-in's full size: across the tunnel, twice the furthest the box's walls
## lie from the line, so it covers the whole cross-section even off centre;
## along it, `thickness_mm`.
func size_mm(generator: MineGenerator, placement: int) -> Vector3i:
	var box: int = _box_at(generator, placement)
	var centre: Vector3i = centre_mm(generator, placement)
	var along: int = generator.placements[placement].connectors[0].axis()
	var extent: Vector3i = Vector3i.ZERO
	for axis: int in 3:
		extent[axis] = 2 * maxi(centre[axis] - generator.min_mm[box][axis],
				generator.max_mm[box][axis] - centre[axis])
	extent[along] = thickness_mm
	return extent


## The module's own box holding the tunnel's middle, or -1.
static func _box_at(generator: MineGenerator, placement: int) -> int:
	var centre: Vector3i = centre_mm(generator, placement)
	var owned: ModulePlacement = generator.placements[placement]
	for box: int in range(owned.first_box, owned.end_box):
		if centre.clamp(generator.min_mm[box], generator.max_mm[box]) == centre:
			return box
	return -1


func _fits(generator: MineGenerator, placement: int, level: LevelDef,
		robot_radii_mm: Array[int]) -> bool:
	var centre: Vector3i = centre_mm(generator, placement)
	var half: Vector3i = size_mm(generator, placement) / 2
	if DebrisDoors._gap_squared(centre, half, level.start_position_mm) \
			< min_start_distance_mm * min_start_distance_mm:
		return false
	if level.reactor != null:
		var reach: int = min_reactor_distance_mm + level.reactor.radius_mm
		if DebrisDoors._gap_squared(centre, half, level.reactor.position_mm) < reach * reach:
			return false
	for index: int in level.robots.spawns.size():
		var reach: int = min_robot_distance_mm + robot_radii_mm[index]
		if DebrisDoors._gap_squared(centre, half, level.robots.spawns[index].position_mm) < reach * reach:
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
