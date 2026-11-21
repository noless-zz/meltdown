extends RefCounted

## Failed blast doors prefer openings on loops (#515, RUN-4, GEN-5, GEN-3,
## ARC-4): `doors.loop_weight` reads and is checked; an opening counts as on a
## loop exactly when a door there alone leaves a route from the reactor to the
## start; at 1 the doors are placed as before #515; and at the shipped value
## the guard holds at most a fifth of the doors over seeds 0..999 while no more
## than a tenth fewer are placed. `test_generated_doors.gd` keeps checking the
## shipped doors against the validator and `DebrisRouteGuard`.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
const SAME_SEEDS: int = 200
## Door count and checksum (`_checksum`) of seeds 0..199 with the shipped file,
## fires and `loop_weight` left out, from `main` before #515 (d1512b0). Taken
## again for #912, which moves the reactor away from the start, so the escape
## route the doors are placed on moves with it; the doors were not changed.
const BEFORE_DOORS: int = 210
const BEFORE_CHECKSUM: int = -727600254
## Most of the doors the guard may hold at the shipped weight, out of 100.
const MOST_HELD_PERCENT: int = 20
## Fewest doors placed at the shipped weight, out of 100 at weight 1.
const LEAST_PLACED_PERCENT: int = 90


func _file() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))
	data.erase(DebrisPlan.FIRES_KEY)
	return data


func _plan(weight: Variant) -> DebrisPlan:
	var data: Dictionary = _file()
	var doors: Dictionary = data[DebrisPlan.DOORS_KEY]
	doors.erase("loop_weight")
	if weight != null:
		doors["loop_weight"] = weight
	return DebrisPlan.parse_json(JSON.stringify(data))


func test_loop_weight_reads_and_defaults_to_one() -> String:
	var shipped: DebrisPlan = DebrisPlan.parse_json(FileAccess.get_file_as_string(DEBRIS_FILE))
	if shipped.error != "" or shipped.doors == null:
		return "debris.json: %s" % shipped.error
	var milli: int = shipped.doors.loop_weight_milli
	if milli <= DebrisDoors.WEIGHT_SCALE or milli > 10 * DebrisDoors.WEIGHT_SCALE:
		return "shipped loop_weight %d thousandths, want above 1 and at most 10" % milli
	if _plan(null).doors.loop_weight_milli != DebrisDoors.WEIGHT_SCALE:
		return "a section without loop_weight does not weigh 1"
	if _plan(2.5).doors.loop_weight_milli != 2500:
		return "loop_weight 2.5 read as %d thousandths" % _plan(2.5).doors.loop_weight_milli
	for bad: Variant in [0.5, 0, 10.5, "loops", [2]]:
		var plan: DebrisPlan = _plan(bad)
		if not plan.error.contains("doors.loop_weight"):
			return "loop_weight %s gave error \"%s\"" % [JSON.stringify(bad), plan.error]
	return ""


## Over seeds 0..49 an opening is on a loop exactly when `KnownRoute` still
## finds a way from the reactor to the start with a fallen door across it alone.
func test_on_loop_agrees_with_a_route_search() -> String:
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var robot_plan: RobotPlan = SeedSweep.load_robot_plan()
	var doors: DebrisDoors = _plan(null).doors
	var radius: float = SeedSweep.ship_radius()
	var loops: int = 0
	var cuts: int = 0
	for level_seed: int in 50:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var level: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan)
		if level.reactor == null:
			continue
		var graph: OpeningGraph = OpeningGraph.new(level, radius)
		var all: Array[int] = []
		for box: int in level.union.boxes.size():
			all.append(box)
		for box: int in DebrisDoors.openings(generator):
			var door: MeltdownDebris = MeltdownDebris.new()
			door.positions_mm.append(DebrisDoors.centre_mm(generator, box))
			door.radii_mm.append(0)
			door.sizes_mm.append(doors.size_mm(generator, box))
			door.after_ticks.append(1)
			door.skipped.append(false)
			door.elapsed_ticks = 1
			var route: KnownRoute = KnownRoute.find(level.union, all, level.reactor.position(),
					level.start_position(), door, radius)
			var open: bool = route.length_mm != EscapePath.UNREACHABLE
			if doors.on_loop(generator, box, graph) != open:
				return "seed %d opening box %d: on_loop %s, route search %s" \
						% [level_seed, box, not open, open]
			if open:
				loops += 1
			else:
				cuts += 1
	if loops == 0 or cuts == 0:
		return "seeds 0..49 have %d loop and %d cutting openings; want both" % [loops, cuts]
	return ""


## With `loop_weight` 1 the doors of seeds 0..199 are those placed before #515,
## and the same as with the key left out. Robots are placed without #531's
## near-start cap, as they were when the checksum was taken, since doors keep
## clear of robots and the cap moves some of them.
func test_weight_one_places_doors_as_before() -> String:
	var robots: RobotPlan = _robots_before_531()
	var one: Dictionary = _doors(_plan(1), SAME_SEEDS, robots)
	var unset: Dictionary = _doors(_plan(null), SAME_SEEDS, robots)
	if one["checksum"] != unset["checksum"] or one["placed"] != unset["placed"]:
		return "loop_weight 1 and no loop_weight place different doors"
	if one["placed"] != BEFORE_DOORS or one["checksum"] != BEFORE_CHECKSUM:
		return "loop_weight 1 placed %d doors, checksum %d; before #515 %d, %d" \
				% [one["placed"], one["checksum"], BEFORE_DOORS, BEFORE_CHECKSUM]
	return ""


## Over seeds 0..999 the guard holds at most `MOST_HELD_PERCENT` of the doors at
## the shipped weight, and at least `LEAST_PLACED_PERCENT` as many are placed
## as at weight 1. Both are printed for the pull request.
func test_shipped_weight_holds_fewer_doors() -> String:
	var shipped: DebrisPlan = DebrisPlan.parse_json(JSON.stringify(_file()))
	var before: Dictionary = _doors(_plan(1), SEEDS)
	var after: Dictionary = _doors(shipped, SEEDS)
	print("  doors over seeds 0..%d: weight 1 %d placed, %d held; shipped weight %s %d placed, %d held"
			% [SEEDS - 1, before["placed"], before["held"],
			shipped.doors.loop_weight_milli / float(DebrisDoors.WEIGHT_SCALE),
			after["placed"], after["held"]])
	if after["held"] * 100 > after["placed"] * MOST_HELD_PERCENT:
		return "%d of %d doors held, more than %d%%" % [after["held"], after["placed"], MOST_HELD_PERCENT]
	if after["placed"] * 100 < before["placed"] * LEAST_PLACED_PERCENT:
		return "%d doors placed, %d at weight 1" % [after["placed"], before["placed"]]
	return ""


## The shipped robot file with the near-start cap lifted, placing as before #531.
static func _robots_before_531() -> RobotPlan:
	var data: Dictionary = JSON.parse_string(SeedLevel.read_text(SeedLevel.ROBOTS_FILE))
	data["max_near_start"] = 1000
	return RobotPlan.parse_json(JSON.stringify(data), SeedSweep.robot_texts())


## The doors `plan` places over seeds 0..`count` - 1: how many, how many the
## guard holds, and a checksum of where and when they fall.
func _doors(plan: DebrisPlan, count: int, robots: RobotPlan = null) -> Dictionary:
	var robot_plan: RobotPlan = robots if robots != null else SeedSweep.load_robot_plan()
	var modules: Array[ModuleDef] = SeedSweep.load_modules()
	var reactor_plan: ReactorPlan = SeedSweep.load_reactor_plan()
	var bridges: LoopBridges = SeedSweep.load_loop_bridges()
	var radius: float = SeedSweep.ship_radius()
	var placed: int = 0
	var held: int = 0
	var checksum: int = 0
	for level_seed: int in count:
		var generator: MineGenerator = MineGenerator.generate(level_seed, modules,
				SeedSweep.MODULE_COUNT, bridges)
		var level: LevelDef = generator.to_level_def(reactor_plan, radius, robot_plan, plan)
		if level.debris == null:
			continue
		var holds: Array[bool] = DebrisEscape.held_by_guard(level, level.debris, radius)
		for index: int in level.debris.size():
			if not level.debris.is_box(index):
				continue
			placed += 1
			if holds[index]:
				held += 1
			checksum = _checksum(checksum, level_seed, level.debris.positions_mm[index],
					level.debris.after_ticks[index])
	return {"placed": placed, "held": held, "checksum": checksum}


static func _checksum(running: int, level_seed: int, at: Vector3i, ticks: int) -> int:
	return (running * 31 + at.x * 7 + at.y * 11 + at.z * 13 + ticks + level_seed) % 1000000007
