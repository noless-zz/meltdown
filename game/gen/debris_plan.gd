class_name DebrisPlan
extends RefCounted

## The meltdown debris a generated level gets (#398, RUN-4, GEN-1, ARC-4), read
## from `data/gen/debris.json`:
##
##     {"count": [2, 5], "radius": [1.5, 3], "after_seconds": [8, 60],
##      "min_start_distance": 15, "min_reactor_distance": 6, "min_robot_distance": 2,
##      "latest_fall_fraction": 0.8}
##
## Each range is `[lowest, highest]`, both included. `count` is how many
## entries a level gets, `radius` their radius in metres and `after_seconds`
## how long after the reactor dies each falls. The two distances are metres of
## clear space between an entry's surface and the start point, and between an
## entry's surface and the reactor's surface; `min_robot_distance` (#436) is
## the clear space between an entry's surface and each robot spawn's surface,
## so no robot starts inside a rock once it falls. `latest_fall_fraction`
## (#437, 0.1..1) caps every fall time at that fraction of the level's meltdown
## countdown, `ReactorState.meltdown_ticks_for_path` for the `EscapePath` from
## the reactor to the start, so debris still falls before a short level's
## countdown ends. Radii and distances are
## held as whole millimetres and times as whole ticks, so placement is exact
## (ARC-2).
## The caller hands over the file's text, because `gen/` never opens files.
##
## `place` puts entries where the escape runs, on `DebrisSpots.escape_spots`:
## in the modules holding the shortest route from the reactor to the start,
## each centred in one of those modules' boxes or in an opening between two of
## them. Whether an entry may really fall is not decided here:
## `DebrisRouteGuard` holds back any that would close the last route out when
## it falls due. What is decided here (#493) is that the escape still fits the
## countdown once the entries the guard lets fall are down: `place` drops
## entries until `DebrisEscape` passes, with `escape_validator`'s speed and
## margin.

const KEYS: Array[String] = ["count", "radius", "after_seconds", "min_start_distance",
		"min_reactor_distance", "min_robot_distance", "latest_fall_fraction"]
## The optional `doors` section (#462), read by `DebrisDoors`; without it no doors.
const DOORS_KEY: String = "doors"
## The optional `fires` section (#497), read by `DebrisFires`; without it no fire.
const FIRES_KEY: String = "fires"
## Largest radius an entry may have, metres: a cave-in, not a wall of rock.
const MAX_RADIUS_M: float = 20.0
## Latest an entry may fall, seconds after the reactor dies.
const MAX_AFTER_SECONDS: float = 3600.0
## Furthest a distance key may be, metres: far beyond any level.
const MAX_DISTANCE_M: float = 10000.0
## Bounds of `latest_fall_fraction`: below a tenth every rock falls at once.
const MIN_FALL_FRACTION: float = 0.1
const MAX_FALL_FRACTION: float = 1.0
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
var min_robot_distance_mm: int = 0
var latest_fall_fraction: float = 1.0
## Blast doors to place after the spheres (#462), or null without a section.
var doors: DebrisDoors = null
## Fires to place after the trimming (#497), or null without a section.
var fires: DebrisFires = null
## Whose `escape_speed_mps` and `escape_margin` the escape with debris fallen
## must keep (#493). The defaults are `validator.json`'s; `SeedLevel` hands over
## the file it read, so the placing and the check that follows agree. Null
## leaves the entries as drawn, for tests that compare.
var escape_validator: LevelValidator = LevelValidator.new()
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
	plan.error = DebrisPlanFile.read(plan, json.data)
	return plan


## The debris for `level`, built from `generator`, or null when there is none
## to place: no reactor, no route from it to the start, or a count of zero.
## Every draw comes from a generator seeded from `output_hash` and "debris", so
## the same seed gives the same debris, and the reactor, the robots and the
## generator itself are left as they were. Why fewer entries than drawn were
## placed goes to `generator.debris_note`. `robot_plan` gives the radius of
## each of `level`'s robots by id (a resolved spawn's own type wins); a spot
## too close to one is skipped, and an entry that found only such spots is
## dropped and counted in the note, while the next entries still get placed.
## A fall time drawn past `fall_limit_ticks` is drawn again from its own
## generator between the lowest `after_seconds` and the limit (or set to the
## limit when even the lowest is later), so the main draws, and with them the
## spots, stay what they were.
func place(generator: MineGenerator, level: LevelDef, ship_radius: float,
		robot_plan: RobotPlan = null) -> MeltdownDebris:
	if level.reactor == null:
		generator.debris_note = "no debris: the level has no reactor"
		return null
	var spots: Array[Vector3i] = DebrisSpots.escape_spots(generator, level, ship_radius)
	if spots.is_empty():
		generator.debris_note = "no debris: no route from the reactor to the start"
		return null
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash([generator.output_hash(), "debris"])
	var wanted: int = min_count + _pick(rng, max_count - min_count + 1)
	var robot_radii: Array[int] = robot_radii_mm(level, robot_plan)
	var limit: int = fall_limit_ticks(level)
	var fall_rng: RandomNumberGenerator = RandomNumberGenerator.new()
	fall_rng.seed = hash([generator.output_hash(), "debris fall"])
	var debris: MeltdownDebris = MeltdownDebris.new()
	var near_robots: int = 0
	var no_room: bool = false
	for count: int in wanted:
		var radius: int = min_radius_mm + _pick(rng, max_radius_mm - min_radius_mm + 1)
		var ticks: int = min_after_ticks + _pick(rng, max_after_ticks - min_after_ticks + 1)
		var spot: int = -1
		var robot_blocked: bool = false
		for attempt: int in TRIES:
			if spots.is_empty():
				break
			var drawn: int = _pick(rng, spots.size())
			if not fits(spots[drawn], radius, level):
				continue
			if clear_of_robots(spots[drawn], radius, level, robot_radii):
				spot = drawn
				break
			robot_blocked = true
		if spot < 0 and robot_blocked:
			near_robots += 1
			continue
		if spot < 0:
			no_room = true
			break
		debris.positions_mm.append(spots[spot])
		debris.radii_mm.append(radius)
		debris.after_ticks.append(_within(ticks, limit, fall_rng))
		debris.skipped.append(false)
		spots.remove_at(spot)
	var notes: Array[String] = []
	if no_room or near_robots > 0:
		var why: Array[String] = []
		if no_room:
			why.append("no room found in %d tries" % TRIES)
		if near_robots > 0:
			why.append("%d dropped for min_robot_distance" % near_robots)
		notes.append("placed %d of %d debris entries: %s" % [debris.size(), wanted, ", ".join(why)])
	var door_note: String = "" if doors == null else doors.place(generator, level, debris, robot_radii, limit,
			ship_radius)
	if door_note != "":
		notes.append(door_note)
	var dropped: int = 0 if escape_validator == null else DebrisEscape.trim(level, debris,
			ship_radius, escape_validator.escape_speed_mps, escape_validator.escape_margin)
	if dropped > 0:
		notes.append("%d debris entries dropped to keep the escape in time" % dropped)
	# Fire goes in after the trimming: it never closes an opening, so it cannot
	# lengthen the escape, and the solid entries stay those a plan without fire
	# keeps (#497).
	var fire_note: String = "" if fires == null \
			else fires.place(generator, level, debris, robot_radii, countdown_ticks(level), limit)
	if fire_note != "":
		notes.append(fire_note)
	generator.debris_note = "; ".join(notes)
	return null if debris.size() == 0 else debris


## The latest tick after the reactor dies an entry of `level` may fall on:
## `latest_fall_fraction` of its countdown, at least 1.
func fall_limit_ticks(level: LevelDef) -> int:
	return maxi(1, floori(countdown_ticks(level) * latest_fall_fraction))


## The meltdown countdown `level` gets when its reactor dies (RUN-5): the one
## for its escape path from the reactor to the start, or the unscaled countdown
## without a route.
static func countdown_ticks(level: LevelDef) -> int:
	var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
			level.start_position())
	return level.reactor.meltdown_ticks() if path_mm == EscapePath.UNREACHABLE \
			else level.reactor.meltdown_ticks_for_path(path_mm)


## `ticks`, or when it is past `limit` a fresh draw in `min_after_ticks..limit`.
func _within(ticks: int, limit: int, fall_rng: RandomNumberGenerator) -> int:
	if ticks <= limit:
		return ticks
	if min_after_ticks >= limit:
		return limit
	return min_after_ticks + _pick(fall_rng, limit - min_after_ticks + 1)


## True if an entry of `radius_mm` centred on `point_mm` keeps
## `min_robot_distance` from every robot of `level`, whose radii in millimetres
## `robot_radii_mm` gives in spawn order.
func clear_of_robots(point_mm: Vector3i, radius_mm: int, level: LevelDef,
		robot_radii_mm: Array[int]) -> bool:
	for index: int in level.robots.spawns.size():
		var gap: int = radius_mm + min_robot_distance_mm + robot_radii_mm[index]
		if _distance_squared(point_mm, level.robots.spawns[index].position_mm) < _squared(gap):
			return false
	return true


## Each of `level`'s robots' radius in millimetres, in spawn order: the
## resolved type's, else `robot_plan`'s for its id, else 0.
static func robot_radii_mm(level: LevelDef, robot_plan: RobotPlan) -> Array[int]:
	var by_id: Dictionary[String, int] = {}
	if robot_plan != null:
		by_id = robot_plan.radii_by_id()
	var radii: Array[int] = []
	for spawn: RobotSpawn in level.robots.spawns:
		if spawn.def != null:
			radii.append(roundi(spawn.def.radius * RobotSpawn.SCALE))
		else:
			radii.append(by_id.get(spawn.id, 0))
	return radii


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


static func _distance_squared(a: Vector3i, b: Vector3i) -> int:
	var d: Vector3i = a - b
	return d.x * d.x + d.y * d.y + d.z * d.z


static func _squared(value: int) -> int:
	return value * value


## A whole number from 0 up to, not including, `size`.
static func _pick(rng: RandomNumberGenerator, size: int) -> int:
	return int(rng.randi() % size)
