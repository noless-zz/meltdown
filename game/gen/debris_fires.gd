class_name DebrisFires
extends RefCounted

## Fire for a generated level (#497, RUN-4, GEN-3, ARC-4): fire entries of
## `MeltdownDebris` (`MeltdownFire`, #480) that start burning during the
## meltdown, so fire happens on generated seeds too. Read from the optional
## `fires` section of `data/gen/debris.json`:
##
##     "fires": {"count": [0, 2], "radius": [2, 3], "damage_per_second": 5,
##               "after_fraction": [0.03, 0.12], "min_start_distance": 15,
##               "min_reactor_distance": 6, "min_robot_distance": 2}
##
## `count`, `radius` and `after_fraction` are `[lowest, highest]` ranges like
## the spheres'. `after_fraction` (#620) is when a fire lights, as a fraction
## of the level's own meltdown countdown (the countdown set the moment the
## reactor dies, RUN-5), held in thousandths: fixed seconds lit most fires
## after a short level's escape was over, so the window scales with the level
## to stay fair. `damage_per_second` is what each fire deals a ship inside it;
## the three distances are metres of clear space between the fire's surface and
## the start point, the reactor's surface and each robot spawn's surface.
##
## A fire is centred in one of the level's module boxes, never one of the start
## module's, small enough to lie wholly inside that box and clear of every box
## of the start module, and only where a route from the start reaches. Fire is
## passable, so the escape stays open whatever burns: fires are not checked
## against routes here and `DebrisRouteGuard` never holds one back.
##
## Every draw comes from generators seeded with `output_hash` and "debris
## fires", apart from the spheres' and the doors', and fires are appended after
## both, so `output_hash`, the reactor, the robots and every solid entry are as
## they were without the section (ARC-2).

const KEYS: Array[String] = ["count", "radius", "damage_per_second", "after_fraction",
		"min_start_distance", "min_reactor_distance", "min_robot_distance"]
## Draws of a box for one fire before the placing gives up on it.
const TRIES: int = 32
## `after_fraction` is held in thousandths of the countdown, so draws are exact (ARC-2).
const FRACTION_SCALE: int = 1000

var min_count: int = 0
var max_count: int = 0
var min_radius_mm: int = 1
var max_radius_mm: int = 1
var milli_dps: int = 1
var min_after_permille: int = 1
var max_after_permille: int = 1
var min_start_distance_mm: int = 0
var min_reactor_distance_mm: int = 0
var min_robot_distance_mm: int = 0


## Reads the `fires` section into a new `DebrisFires`, or returns the problem
## with every key named "fires.<key>".
static func read(value: Variant, into: Array[DebrisFires]) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "fires must be a JSON object"
	var data: Dictionary = value
	var unknown: Array[String] = []
	for key: Variant in data:
		if not KEYS.has(key):
			unknown.append("\"fires.%s\"" % str(key))
	if not unknown.is_empty():
		return "unknown key %s" % ", ".join(unknown)
	var missing: Array[String] = []
	for key: String in KEYS:
		if not data.has(key):
			missing.append("\"fires.%s\"" % key)
	if not missing.is_empty():
		return "missing key %s" % ", ".join(missing)
	var counts: Array[int] = []
	var problem: String = DebrisPlan._read_range(data["count"], "fires.count", 1.0, 0.0, 1000.0,
		"a whole number", counts)
	if problem != "":
		return problem
	var radii: Array[int] = []
	problem = DebrisPlan._read_range(data["radius"], "fires.radius", RobotSpawn.SCALE, 0.001,
		DebrisPlan.MAX_RADIUS_M, "metres", radii)
	if problem != "":
		return problem
	var damage: Array[int] = []
	problem = MeltdownFire.read({"kind": MeltdownFire.KIND_FIRE,
			"damage_per_second": data["damage_per_second"]}, damage)
	if problem != "":
		return "fires.%s" % problem
	var fractions: Array[int] = []
	problem = DebrisPlan._read_range(data["after_fraction"], "fires.after_fraction",
		FRACTION_SCALE, 1.0 / FRACTION_SCALE, 1.0, "a fraction of the countdown", fractions)
	if problem != "":
		return problem
	var distances: Array[int] = []
	for key: String in ["min_start_distance", "min_reactor_distance", "min_robot_distance"]:
		var distance: Variant = data[key]
		if not DebrisPlan._is_number(distance) or float(distance) < 0.0 \
				or float(distance) > DebrisPlan.MAX_DISTANCE_M:
			return "fires.%s must be a number of metres from 0 to %s" % [key, DebrisPlan.MAX_DISTANCE_M]
		distances.append(roundi(float(distance) * RobotSpawn.SCALE))
	var fires: DebrisFires = DebrisFires.new()
	fires.min_count = counts[0]
	fires.max_count = counts[1]
	fires.min_radius_mm = radii[0]
	fires.max_radius_mm = radii[1]
	fires.milli_dps = damage[0]
	fires.min_after_permille = fractions[0]
	fires.max_after_permille = fractions[1]
	fires.min_start_distance_mm = distances[0]
	fires.min_reactor_distance_mm = distances[1]
	fires.min_robot_distance_mm = distances[2]
	into.append(fires)
	return ""


## Appends this level's fires to `debris`, after its spheres and doors.
## `robot_radii_mm` is each robot's radius in spawn order, `countdown` the
## level's meltdown countdown in ticks (`DebrisPlan.countdown_ticks`) and
## `fall_limit` the latest tick a fire may start on
## (`DebrisPlan.fall_limit_ticks`). Returns why fewer fires than drawn were
## placed, or "".
func place(generator: MineGenerator, level: LevelDef, debris: MeltdownDebris,
		robot_radii_mm: Array[int], countdown: int, fall_limit: int) -> String:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "debris fires"])
	var wanted: int = min_count + DebrisPlan._pick(rng, max_count - min_count + 1)
	if wanted == 0:
		return ""
	var start_boxes: Array[int] = boxes(generator, true)
	var free: Array[int] = boxes(generator)
	# Solid entries built without sizes or fire leave the lists short.
	while debris.sizes_mm.size() < debris.size():
		debris.sizes_mm.append(Vector3i.ZERO)
	while debris.fire_milli_dps.size() < debris.size():
		debris.fire_milli_dps.append(0)
	var placed: int = 0
	for count: int in wanted:
		var radius: int = min_radius_mm + DebrisPlan._pick(rng, max_radius_mm - min_radius_mm + 1)
		# One draw, as the seconds were, so the boxes drawn after it are the same.
		var permille: int = min_after_permille \
				+ DebrisPlan._pick(rng, max_after_permille - min_after_permille + 1)
		var spot: int = -1
		for attempt: int in TRIES:
			if free.is_empty():
				break
			var drawn: int = DebrisPlan._pick(rng, free.size())
			if fits(generator, free[drawn], radius, level, start_boxes, robot_radii_mm):
				spot = drawn
				break
		if spot < 0:
			continue
		var box: int = free.pop_at(spot)
		debris.positions_mm.append(centre_mm(generator, box))
		debris.radii_mm.append(radius)
		debris.sizes_mm.append(Vector3i.ZERO)
		debris.after_ticks.append(after_ticks(permille, countdown, fall_limit))
		debris.fire_milli_dps.append(milli_dps)
		debris.skipped.append(false)
		placed += 1
	if placed == wanted:
		return ""
	return "placed %d of %d fires: no box clear of the start, reactor and robots in %d tries" \
			% [placed, wanted, TRIES]


## The boxes a fire may be centred in, in box order: every box of every module
## but the start's. Doorways and loop bridges are left out; they are openings.
## With `start_only` it is the start module's boxes instead.
static func boxes(generator: MineGenerator, start_only: bool = false) -> Array[int]:
	var found: Array[int] = []
	if generator.open_owner.is_empty():
		return found
	var start: int = GeneratedLevel.start_placement(generator)
	for index: int in generator.placements.size():
		if (index == start) != start_only:
			continue
		var placement: ModulePlacement = generator.placements[index]
		for box: int in range(placement.first_box, placement.end_box):
			found.append(box)
	return found


static func centre_mm(generator: MineGenerator, box: int) -> Vector3i:
	return (generator.min_mm[box] + generator.max_mm[box]) / 2


## True if a fire of `radius_mm` centred in `box` lies wholly inside it, touches
## no box of `start_boxes`, keeps the section's distances from the start, the
## reactor and each robot, and is reachable from the start.
func fits(generator: MineGenerator, box: int, radius_mm: int, level: LevelDef,
		start_boxes: Array[int], robot_radii_mm: Array[int]) -> bool:
	var centre: Vector3i = centre_mm(generator, box)
	var extent: Vector3i = generator.max_mm[box] - generator.min_mm[box]
	if 2 * radius_mm > mini(extent.x, mini(extent.y, extent.z)):
		return false
	for start_box: int in start_boxes:
		if gap_squared(generator, start_box, centre) <= _squared(radius_mm):
			return false
	if _distance_squared(centre, level.start_position_mm) \
			< _squared(radius_mm + min_start_distance_mm):
		return false
	if level.reactor != null and _distance_squared(centre, level.reactor.position_mm) \
			< _squared(radius_mm + min_reactor_distance_mm + level.reactor.radius_mm):
		return false
	for index: int in level.robots.spawns.size():
		if _distance_squared(centre, level.robots.spawns[index].position_mm) \
				< _squared(radius_mm + min_robot_distance_mm + robot_radii_mm[index]):
			return false
	return EscapePath.length_mm(level.union, level.start_position(),
			Vector3(centre) / float(RobotSpawn.SCALE)) != EscapePath.UNREACHABLE


## Squared millimetres from `point` to the nearest point of generator box `box`;
## 0 inside it.
static func gap_squared(generator: MineGenerator, box: int, point: Vector3i) -> int:
	var outside: Vector3i = point - point.clamp(generator.min_mm[box], generator.max_mm[box])
	return outside.x * outside.x + outside.y * outside.y + outside.z * outside.z


## The tick a fire drawn at `permille` thousandths of a `countdown`-tick
## countdown lights on: at least 1, and never past `fall_limit`, the latest
## tick any meltdown debris may start on.
static func after_ticks(permille: int, countdown: int, fall_limit: int) -> int:
	return clampi(countdown * permille / FRACTION_SCALE, 1, maxi(1, fall_limit))


static func _distance_squared(a: Vector3i, b: Vector3i) -> int:
	var d: Vector3i = a - b
	return d.x * d.x + d.y * d.y + d.z * d.z


static func _squared(value: int) -> int:
	return value * value
