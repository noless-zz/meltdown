extends RefCounted

## Generated debris falls within the meltdown countdown (#437, RUN-4, RUN-5,
## GEN-3, ARC-4): `latest_fall_fraction` in `debris.json` caps every fall time
## at that fraction of the countdown the level's escape path gives. A fall time
## past the cap is drawn again below it from its own generator, so only fall
## times change: the spots, radii, `output_hash`, the reactor and the robots
## stay as they were. The validator, distance and `DebrisRouteGuard` sweep in
## `test_generated_debris.gd` runs on the same shipped data.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const DEBRIS_FILE: String = "res://data/gen/debris.json"
const SEEDS: int = 1000
const SEED: int = 42


func _shipped() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEBRIS_FILE))


func _plan(data: Dictionary) -> DebrisPlan:
	return DebrisPlan.parse_json(JSON.stringify(data))


## The countdown in ticks for `level`'s reactor-to-start escape, worked out
## apart from `DebrisPlan.fall_limit_ticks`.
func _countdown(level: LevelDef) -> int:
	var path_mm: int = EscapePath.length_mm(level.union, level.reactor.position(),
			level.start_position())
	return level.reactor.meltdown_ticks_for_path(path_mm)


func test_shipped_fraction_reads() -> String:
	var plan: DebrisPlan = _plan(_shipped())
	if plan.error != "":
		return "debris.json: %s" % plan.error
	if plan.latest_fall_fraction < DebrisPlan.MIN_FALL_FRACTION \
			or plan.latest_fall_fraction > DebrisPlan.MAX_FALL_FRACTION:
		return "latest_fall_fraction %s out of range" % plan.latest_fall_fraction
	for edge: float in [0.1, 1.0]:
		var data: Dictionary = _shipped()
		data["latest_fall_fraction"] = edge
		if _plan(data).error != "":
			return "%s was rejected: %s" % [edge, _plan(data).error]
	return ""


## Seeds 0..999 with the shipped files: every entry falls within the fraction
## of its level's countdown; against the raw draws (the same plan under an
## hour-long countdown, which no draw reaches), only fall times past the cap
## differ; and the level built without
## debris has the same `output_hash`, reactor and robots. Prints the fall times
## as a fraction of the countdown.
func test_every_seed_falls_within_the_countdown() -> String:
	var inputs: SeedLevel = SeedLevel.load_inputs()
	if inputs.error != "":
		return inputs.error
	var shipped: DebrisPlan = inputs.debris_plan
	var radius: float = inputs.tuning.radius
	var fractions: Array[float] = []
	var redrawn: int = 0
	for level_seed: int in SEEDS:
		var generator: MineGenerator = inputs.generate(level_seed)
		var bare: LevelDef = generator.to_level_def(inputs.reactor_plan, radius, inputs.robot_plan)
		var hash_before: int = generator.output_hash()
		var level: LevelDef = generator.to_level_def(inputs.reactor_plan, radius, inputs.robot_plan,
				shipped)
		var problem: String = _unchanged(bare, level, hash_before, generator.output_hash())
		if problem == "" and level.debris != null:
			var countdown: int = _countdown(level)
			var cap: float = countdown * shipped.latest_fall_fraction
			var a: MeltdownDebris = level.debris
			var b: MeltdownDebris = _raw(shipped, generator, level, radius, inputs.robot_plan)
			if b == null or a.positions_mm != b.positions_mm or a.radii_mm != b.radii_mm:
				problem = "the cap moved or resized debris"
			for index: int in a.size():
				if problem != "":
					break
				fractions.append(a.after_ticks[index] / float(countdown))
				if a.after_ticks[index] > cap:
					problem = "entry %d falls at %d ticks, past %.1f of the %d-tick countdown" \
							% [index, a.after_ticks[index], cap, countdown]
				elif b.after_ticks[index] <= cap and a.after_ticks[index] != b.after_ticks[index]:
					problem = "entry %d inside the cap was drawn again" % index
				elif a.after_ticks[index] != b.after_ticks[index]:
					redrawn += 1
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
	if fractions.is_empty() or redrawn == 0:
		return "%d entries, %d drawn again: the cap was never exercised" % [fractions.size(), redrawn]
	fractions.sort()
	print("  debris fall time over seeds 0..%d as a fraction of the countdown: min %.3f, median %.3f, max %.3f (%d entries, %d drawn again)"
			% [SEEDS - 1, fractions[0], fractions[fractions.size() / 2], fractions[-1],
			fractions.size(), redrawn])
	return ""


## `plan`'s draws for `level` before any cap: placed under an hour-long countdown.
func _raw(plan: DebrisPlan, generator: MineGenerator, level: LevelDef, radius: float,
		robot_plan: RobotPlan) -> MeltdownDebris:
	var reactor: ReactorState = level.reactor
	var long: ReactorState = reactor.fresh_copy()
	long.scales_with_path = false
	long.meltdown_seconds = DebrisPlan.MAX_AFTER_SECONDS
	level.reactor = long
	var raw: MeltdownDebris = plan.place(generator, level, radius, robot_plan)
	level.reactor = reactor
	return raw


func _unchanged(bare: LevelDef, level: LevelDef, hash_before: int, hash_after: int) -> String:
	if hash_before != hash_after:
		return "placing debris changed output_hash"
	if (bare.reactor == null) != (level.reactor == null) \
			or (bare.reactor != null and bare.reactor.to_json() != level.reactor.to_json()):
		return "the reactor changed when debris was placed"
	if bare.robots.spawns.size() != level.robots.spawns.size():
		return "%d robots without debris, %d with" % [bare.robots.spawns.size(), level.robots.spawns.size()]
	for index: int in bare.robots.spawns.size():
		if bare.robots.spawns[index].position_mm != level.robots.spawns[index].position_mm \
				or bare.robots.spawns[index].id != level.robots.spawns[index].id:
			return "robot %d changed when debris was placed" % index
	return ""


## A 20 s countdown with half of it allowed: entries drawn past 10 s are drawn
## again inside it, on the same spots; with the lowest fall time already past
## the cap, every entry falls on the cap.
func test_a_short_countdown_moves_late_entries_inside_it() -> String:
	var generator: MineGenerator = MineGenerator.generate(SEED, SeedSweep.load_modules(),
			SeedSweep.MODULE_COUNT, SeedSweep.load_loop_bridges())
	var radius: float = SeedSweep.ship_radius()
	var level: LevelDef = generator.to_level_def(SeedSweep.load_reactor_plan(), radius)
	level.reactor.scales_with_path = false
	level.reactor.meltdown_seconds = 20.0
	var data: Dictionary = {"count": [5, 5], "radius": [1, 1], "after_seconds": [5, 60],
			"min_start_distance": 0, "min_reactor_distance": 0, "min_robot_distance": 0,
			"latest_fall_fraction": 0.5}
	var whole: MeltdownDebris = _raw(_plan(data), generator, level, radius, null)
	var half_plan: DebrisPlan = _plan(data)
	if half_plan.fall_limit_ticks(level) != 600:
		return "limit %d ticks, expected 600" % half_plan.fall_limit_ticks(level)
	var half: MeltdownDebris = half_plan.place(generator, level, radius)
	if whole == null or half == null or whole.positions_mm != half.positions_mm:
		return "the cap changed where debris sits"
	var moved: int = 0
	for index: int in half.size():
		if half.after_ticks[index] > 600 or half.after_ticks[index] < 300:
			return "entry %d falls at %d ticks, outside 300..600" % [index, half.after_ticks[index]]
		if whole.after_ticks[index] > 600:
			moved += 1
		elif whole.after_ticks[index] != half.after_ticks[index]:
			return "entry %d was inside the cap and still moved" % index
	if moved == 0:
		return "no entry of seed %d was drawn past 10 s: %s" % [SEED, whole.to_json()]
	data["after_seconds"] = [30, 30]
	var late: MeltdownDebris = _plan(data).place(generator, level, radius)
	for ticks: int in late.after_ticks:
		if ticks != 600:
			return "an entry whose lowest time is past the cap falls at %d ticks, not 600" % ticks
	return ""
