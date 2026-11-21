extends RefCounted

## The escape still fits the countdown with meltdown entries fallen (#493,
## GEN-3, RUN-4, RUN-5): on a hand-built level with two routes, a door that
## sends the escape the long way over the margin fails `debris_escape`, is named
## in the message, and is the one entry `DebrisEscape.trim` drops; when the long
## way still fits the door stays. Generated levels: trimming moves no
## `output_hash`, reactor or robot; over seeds 0..999 every level passes
## `LevelValidator` (the new check included) and the debris sweep; with a
## tighter margin entries are dropped, only entries, and every level passes. The
## check reports under its own name in `SeedSweep`.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SeedLevelCache := preload("res://tests/seed_level_cache.gd")
const SHIP_RADIUS: float = 1.0
## `test_box_debris_route.gd`'s two-route level: the short way runs down the
## corridor from z -6 to -60 (104.5 m from the reactor to the start), the long
## way round on the +x side (120.1 m). Entry 0 is a door across the corridor's
## near opening; entry 1 a rock in the far room's corner that blocks nothing.
## The countdown is a flat 60 s.
const TWO_ROUTE_LEVEL: String = """{
	"boxes": [
		{"min": [-10.0, -6.0, -10.0], "max": [10.0, 6.0, 10.0]},
		{"min": [-4.0, -4.0, -60.0], "max": [4.0, 4.0, -6.0]},
		{"min": [-10.0, -6.0, -120.0], "max": [30.0, 6.0, -56.0]},
		{"min": [6.0, -6.0, -10.0], "max": [30.0, 6.0, 10.0]},
		{"min": [22.0, -6.0, -60.0], "max": [30.0, 6.0, -6.0]}
	],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [20, 0, -100], "radius": 2, "hull": 40, "meltdown_seconds": 60},
	"debris": [
		{"position": [0.0, 0.0, -8.0], "size": [8.0, 8.0, 1.0], "after_seconds": 0.5},
		{"position": [-7.0, 0.0, -117.0], "radius": 1.5, "after_seconds": 1}
	]
}"""
const DOOR: int = 0
const ROCK: int = 1
const SPEED: float = 10.0
## 11.4 s of the 60 s countdown: 114 m, enough for the short way only.
const TIGHT_MARGIN: float = 0.19
## 6 s: too little even for the clear short way (104.5 m).
const SLOW_MARGIN: float = 0.1
## The shipped margin: 48 s, enough for the long way too.
const SHIPPED_MARGIN: float = 0.8
const SEEDS: int = 1000
## A margin under the generated levels' worst escape with debris fallen but
## over their worst clear escape, so some levels must lose entries and every
## one can. Since #912 put the reactor far from the start, escapes are longer
## and the window is narrow: the worst clear escape in seeds 0..299 is 34.1% of
## its countdown (seed 83), and at 0.36 one seed still loses an entry, at 0.38
## none does.
const SQUEEZED_MARGIN: float = 0.35
const SQUEEZED_SEEDS: int = 300
const TIME_LIMIT_MS: int = 90000
## Generated levels whose held entries are compared with the guard's.
const GUARD_SEEDS: int = 200


func _two_routes() -> LevelDef:
	return LevelDef.parse_json(TWO_ROUTE_LEVEL)


func _validator(margin: float) -> LevelValidator:
	return LevelValidator.parse_json(JSON.stringify({"min_passage_ship_diameters": 2.5,
			"escape_speed_mps": SPEED, "escape_margin": margin}))


func test_a_door_that_forces_the_long_way_over_the_margin_fails_and_is_named() -> String:
	var level: LevelDef = _two_routes()
	if level.error != "":
		return "level: %s" % level.error
	var message: String = DebrisEscape.failure(level, level.debris, SHIP_RADIUS, SPEED, TIGHT_MARGIN)
	if not message.begins_with("debris_escape: ") or not message.ends_with("lengthened by entries 0"):
		return "message \"%s\"" % message
	var found: Array[String] = _validator(TIGHT_MARGIN).validate(level, SHIP_RADIUS)
	if found.size() != 1 or found[0] != message:
		return "validator: %s" % [found]
	var without: LevelDef = _two_routes()
	without.debris = null
	if not _validator(TIGHT_MARGIN).validate(without, SHIP_RADIUS).is_empty():
		return "the level fails the tight margin without debris: the test level is wrong"
	return ""


func test_trimming_drops_only_the_door_that_lengthens_the_escape() -> String:
	var level: LevelDef = _two_routes()
	var debris: MeltdownDebris = level.debris
	var dropped: int = DebrisEscape.trim(level, debris, SHIP_RADIUS, SPEED, TIGHT_MARGIN)
	if dropped != 1 or debris.size() != 1 or debris.is_box(0) \
			or debris.positions_mm[0] != Vector3i(-7000, 0, -117000):
		return "dropped %d, left %s" % [dropped, debris.to_json()]
	if not _validator(TIGHT_MARGIN).validate(level, SHIP_RADIUS).is_empty():
		return "the trimmed level still fails"
	return ""


func test_a_door_stays_when_the_long_way_still_fits() -> String:
	var level: LevelDef = _two_routes()
	if DebrisEscape.failure(level, level.debris, SHIP_RADIUS, SPEED, SHIPPED_MARGIN) != "":
		return "the long way fails the shipped margin"
	var dropped: int = DebrisEscape.trim(level, level.debris, SHIP_RADIUS, SPEED, SHIPPED_MARGIN)
	if dropped != 0 or level.debris.size() != 2:
		return "dropped %d of 2 entries" % dropped
	return "" if _validator(SHIPPED_MARGIN).validate(level, SHIP_RADIUS).is_empty() else "validator fails"


## A clear escape already over the margin is the `escape` check's failure; no
## entry is blamed or dropped for it.
func test_a_too_slow_clear_escape_drops_nothing() -> String:
	var level: LevelDef = _two_routes()
	var dropped: int = DebrisEscape.trim(level, level.debris, SHIP_RADIUS, SPEED, SLOW_MARGIN)
	if dropped != 0 or level.debris.size() != 2:
		return "dropped %d" % dropped
	var found: Array[String] = _validator(SLOW_MARGIN).validate(level, SHIP_RADIUS)
	if found.size() != 1 or not found[0].begins_with("escape: "):
		return "validator: %s" % [found]
	return ""


## A door the guard holds never lengthens the escape: with the long way's
## corridor gone, the door on the short way is the last route and stays up.
func test_a_held_door_does_not_count() -> String:
	var level: LevelDef = _two_routes()
	var boxes: Array[BoxBounds] = level.union.boxes.duplicate()
	boxes.remove_at(4)
	level.union = BoxUnion.new(boxes)
	var held: Array[bool] = DebrisEscape.held_by_guard(level, level.debris, SHIP_RADIUS)
	var expected: Array[bool] = [true, false]
	if held != expected:
		return "held %s" % [held]
	var message: String = DebrisEscape.failure(level, level.debris, SHIP_RADIUS, SPEED, TIGHT_MARGIN)
	return "" if message == "" else message


## `DebrisEscape.held_by_guard` holds exactly the entries the guard itself
## holds, on the hand-built level and over seeds 0..`GUARD_SEEDS - 1`.
func test_held_entries_match_the_route_guard() -> String:
	var radius: float = SeedSweep.ship_radius()
	var level: LevelDef = _two_routes()
	var boxes: Array[BoxBounds] = level.union.boxes.duplicate()
	boxes.remove_at(4)
	level.union = BoxUnion.new(boxes)
	var levels: Array[LevelDef] = [level]
	var inputs: SeedLevel = SeedLevel.load_inputs()
	for level_seed: int in GUARD_SEEDS:
		levels.append(inputs.level_of(inputs.generate(level_seed)))
	var compared: int = 0
	for index: int in levels.size():
		var each: LevelDef = levels[index]
		if each.reactor == null or each.debris == null:
			continue
		compared += 1
		var held: Array[bool] = DebrisEscape.held_by_guard(each, each.debris, radius)
		var guard: Array[bool] = _held_by_the_guard(each, radius)
		if held != guard:
			return "level %d: held %s, the guard holds %s" % [index - 1, held, guard]
	return "" if compared > GUARD_SEEDS / 2 else "only %d levels compared" % compared


## The guard itself, as `SeedSweep.debris_route` runs it.
func _held_by_the_guard(level: LevelDef, radius: float) -> Array[bool]:
	var sim: Sim = Sim.new(0, 1)
	sim.set_walls(level.union)
	sim.set_start_pose(0, level.start_position(), Basis())
	sim.ships[0].radius = radius
	sim.ships[0].position = level.reactor.position()
	var reactor: ReactorState = level.reactor.fresh_copy()
	reactor.destroyed = true
	sim.set_reactor(reactor)
	sim.set_debris(level.debris.fresh_copy())
	var due: Array[int] = []
	for ticks: int in sim.debris.after_ticks:
		if not due.has(ticks):
			due.append(ticks)
	due.sort()
	var events: Array[SimEvent] = []
	for ticks: int in due:
		sim.debris.elapsed_ticks = ticks - 1
		DebrisRouteGuard.advance(sim, events)
	var held: Array[bool] = []
	for index: int in level.debris.size():
		held.append(sim.debris.is_skipped(index))
	return held


func test_fire_never_lengthens_the_escape() -> String:
	var level: LevelDef = _two_routes()
	var fire: Array[int] = [5000, 0]
	level.debris.fire_milli_dps = fire
	var message: String = DebrisEscape.failure(level, level.debris, SHIP_RADIUS, SPEED, TIGHT_MARGIN)
	return "" if message == "" else message


func test_the_check_is_listed_and_counted_by_name() -> String:
	if not LevelValidator.CHECKS.has(DebrisEscape.CHECK):
		return "CHECKS: %s" % [LevelValidator.CHECKS]
	var result: Dictionary = SeedSweep.run(0, 2)
	if not (result["by_check"] as Dictionary).has(DebrisEscape.CHECK):
		return "by_check: %s" % [result["by_check"]]
	return "" if SeedSweep.summary(result).contains("escape 0, debris_escape 0") \
			else SeedSweep.summary(result)


## The shipped data over seeds 0..999: trimming leaves `output_hash`, the
## reactor and the robots as they were, and the debris too except where it
## drops entries; every level passes the validator and the debris sweep.
func test_seeds_0_to_999_pass_with_debris_fallen() -> String:
	var started: int = Time.get_ticks_msec()
	var inputs: SeedLevel = SeedLevel.load_inputs()
	var counts: Array[int] = [0, 0]
	var problem: String = _sweep(inputs, SEEDS, counts, true)
	if problem != "":
		return problem
	print("  shipped margin over seeds 0..%d: %d entries dropped on %d seeds"
			% [SEEDS - 1, counts[1], counts[0]])
	var elapsed: int = Time.get_ticks_msec() - started
	return "" if elapsed <= TIME_LIMIT_MS else "took %d ms, limit %d" % [elapsed, TIME_LIMIT_MS]


## With a margin tight enough that debris breaks some escapes, entries are
## dropped on those levels and every level then passes.
func test_a_tighter_margin_drops_entries_and_every_level_passes() -> String:
	var text: String = JSON.stringify({"min_passage_ship_diameters": 2.5,
			"escape_speed_mps": SPEED, "escape_margin": SQUEEZED_MARGIN})
	var inputs: SeedLevel = SeedLevel.load_inputs(text)
	var counts: Array[int] = [0, 0]
	var problem: String = _sweep(inputs, SQUEEZED_SEEDS, counts)
	if problem != "":
		return problem
	print("  margin %.2f over seeds 0..%d: %d entries dropped on %d seeds"
			% [SQUEEZED_MARGIN, SQUEEZED_SEEDS - 1, counts[1], counts[0]])
	return "" if counts[0] > 0 else "no entry dropped: the margin is not tight enough to test"


## Builds seeds 0..`count - 1` with and without trimming and checks them;
## `counts` gets the seeds and the entries trimming dropped. With `shared`, the
## inputs are the shipped ones and the generators and levels are those shared
## with the other sweeps (#956).
func _sweep(inputs: SeedLevel, count: int, counts: Array[int], shared: bool = false) -> String:
	if inputs.error != "":
		return inputs.error
	var untrimmed: DebrisPlan = DebrisPlan.parse_json(SeedLevel.read_text(SeedLevel.DEBRIS_FILE))
	untrimmed.escape_validator = null
	var radius: float = inputs.tuning.radius
	for level_seed: int in count:
		var generator: MineGenerator = SeedLevelCache.generator(level_seed) if shared \
				else inputs.generate(level_seed)
		var hash_before: int = SeedLevelCache.generated_hash(level_seed) if shared \
				else generator.output_hash()
		var drawn: LevelDef = generator.to_level_def(inputs.reactor_plan, radius, inputs.robot_plan,
				untrimmed)
		var level: LevelDef = SeedLevelCache.level(level_seed) if shared else inputs.level_of(generator)
		var problem: String = _only_entries_dropped(drawn, level)
		if problem == "" and generator.output_hash() != hash_before:
			problem = "output_hash moved"
		if problem == "":
			var found: Array[String] = inputs.validate(level, generator)
			problem = "" if found.is_empty() else found[0]
		if problem == "" and level.debris != null:
			var held: Array[int] = []
			problem = SeedSweep.debris_route(level, radius, held)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
		var before: int = 0 if drawn.debris == null else drawn.debris.size()
		var after: int = 0 if level.debris == null else level.debris.size()
		if after < before:
			counts[0] += 1
			counts[1] += before - after
	return ""


## The reactor and the robots as drawn, and the debris the drawn entries in
## order with some left out.
func _only_entries_dropped(drawn: LevelDef, level: LevelDef) -> String:
	if (drawn.reactor == null) != (level.reactor == null) \
			or (drawn.reactor != null and drawn.reactor.to_json() != level.reactor.to_json()):
		return "the reactor moved"
	if drawn.robots.spawns.size() != level.robots.spawns.size():
		return "the robots changed"
	for index: int in drawn.robots.spawns.size():
		if drawn.robots.spawns[index].position_mm != level.robots.spawns[index].position_mm:
			return "robot %d moved" % index
	if level.debris == null:
		return ""
	if drawn.debris == null:
		return "trimming added debris"
	var next: int = 0
	for index: int in level.debris.size():
		while next < drawn.debris.size() and not _same_entry(drawn.debris, next, level.debris, index):
			next += 1
		if next == drawn.debris.size():
			return "entry %d is not one drawn" % index
		next += 1
	return ""


func _same_entry(a: MeltdownDebris, i: int, b: MeltdownDebris, j: int) -> bool:
	return a.positions_mm[i] == b.positions_mm[j] and a.radii_mm[i] == b.radii_mm[j] \
			and a.after_ticks[i] == b.after_ticks[j] and a.box_size(i) == b.box_size(j)
