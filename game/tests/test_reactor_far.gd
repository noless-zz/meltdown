extends RefCounted

## The reactor is placed far from the start (#912, GEN-1, GEN-2, GEN-3, RUN-3,
## RUN-5, ARC-4): over seeds 0..999 no reactor is in or next to the start's
## module and every level passes `reactor_far`; the escape-path lengths of the
## old rule (furthest in joins from the first module) and the new are printed;
## the same seed gives the same level; the check fails a reactor moved next to
## the start or short of the fraction; and `EscapePath.lengths_mm` gives
## `length_mm`'s lengths.

const FIRST_SEED: int = 0
const SEEDS: int = 1000
const VALID: Dictionary = {"radius": 2.5, "hull": 400, "meltdown_seconds": 90, "min_hops": 2,
		"min_escape_fraction": 0.6}


func _inputs() -> SeedLevel:
	return SeedLevel.load_inputs()


## The level with only its reactor: robots and debris do not move it.
func _level(inputs: SeedLevel, generator: MineGenerator) -> LevelDef:
	return generator.to_level_def(inputs.reactor_plan, inputs.tuning.radius)


func _rejects(data: Dictionary, names: String) -> String:
	var plan: ReactorPlan = ReactorPlan.parse_json(JSON.stringify(data))
	if plan.error == "":
		return "%s accepted" % JSON.stringify(data)
	return "" if plan.error.contains(names) else "error \"%s\" does not name %s" % [plan.error, names]


func test_data_file_reads_the_fraction() -> String:
	var plan: ReactorPlan = _inputs().reactor_plan
	if plan.error != "":
		return "reactor.json: %s" % plan.error
	if not is_equal_approx(plan.min_escape_fraction, 0.6) or plan.min_hops != 2:
		return "read fraction %s, %d hops" % [plan.min_escape_fraction, plan.min_hops]
	return ""


func test_bad_fraction_or_hops_is_rejected_naming_the_key() -> String:
	for case: Array in [["min_escape_fraction", -0.1], ["min_escape_fraction", 1.5],
			["min_escape_fraction", "far"], ["min_hops", 1]]:
		var data: Dictionary = VALID.duplicate()
		data[case[0]] = case[1]
		var problem: String = _rejects(data, case[0])
		if problem != "":
			return problem
	var missing: Dictionary = VALID.duplicate()
	missing.erase("min_escape_fraction")
	var plan: ReactorPlan = ReactorPlan.parse_json(JSON.stringify(VALID))
	if plan.error != "" or not is_equal_approx(plan.min_escape_fraction, 0.6):
		return "valid plan: %s" % plan.error
	return _rejects(missing, "\"min_escape_fraction\"")


## Joins from the start's placement through the placement tree alone, worked
## out here, not by `ReactorFar`, which also follows loop bridges.
func _tree_hops(generator: MineGenerator, from: int, to: int) -> int:
	var up_from: Array[int] = [from]
	while generator.placements[up_from.back()].parent >= 0:
		up_from.append(generator.placements[up_from.back()].parent)
	var at: int = to
	var climbed: int = 0
	while not up_from.has(at):
		at = generator.placements[at].parent
		climbed += 1
	return climbed + up_from.find(at)


## The old rule's reactor (#356): centre of the largest box of the placement
## furthest in joins from the first module, ties to the later placement.
func _old_centre(generator: MineGenerator) -> Vector3i:
	var depth: Array[int] = []
	var furthest: int = 0
	for index: int in generator.placements.size():
		var parent: int = generator.placements[index].parent
		depth.append(0 if parent < 0 else depth[parent] + 1)
		if depth[index] >= depth[furthest]:
			furthest = index
	var placement: ModulePlacement = generator.placements[furthest]
	var best: int = placement.first_box
	var most: int = -1
	for box: int in range(placement.first_box, placement.end_box):
		var size: Vector3i = generator.max_mm[box] - generator.min_mm[box]
		if size.x * size.y * size.z > most:
			most = size.x * size.y * size.z
			best = box
	return (generator.min_mm[best] + generator.max_mm[best]) / 2


func _spread(lengths: Array[int]) -> String:
	lengths.sort()
	return "min %.1f m, median %.1f m, max %.1f m" % [lengths[0] / 1000.0,
			lengths[lengths.size() / 2] / 1000.0, lengths.back() / 1000.0]


func test_thousand_seeds_put_the_reactor_far_from_the_start() -> String:
	var inputs: SeedLevel = _inputs()
	var before: Array[int] = []
	var after: Array[int] = []
	for level_seed: int in range(FIRST_SEED, FIRST_SEED + SEEDS):
		var generator: MineGenerator = inputs.generate(level_seed)
		var level: LevelDef = _level(inputs, generator)
		if level.reactor == null:
			return "seed %d: %s" % [level_seed, generator.reactor_note]
		var start: int = GeneratedLevel.start_placement(generator)
		var joins: int = _tree_hops(generator, start, generator.reactor_placement)
		if joins < 2:
			return "seed %d: reactor in placement %d, %d joins from the start's %d" \
					% [level_seed, generator.reactor_placement, joins, start]
		var far: String = ReactorFar.failure(level, inputs.tuning.radius,
				inputs.reactor_plan.min_escape_fraction)
		if far != "":
			return "seed %d: %s" % [level_seed, far]
		after.append(EscapePath.length_mm(level.union, level.reactor.position(), level.start_position()))
		var old: Vector3 = Vector3(_old_centre(generator)) / float(RobotSpawn.SCALE)
		before.append(EscapePath.length_mm(level.union, old, level.start_position()))
	print("  reactor escape path over seeds %d..%d: before (furthest from the first module) %s; after %s"
			% [FIRST_SEED, FIRST_SEED + SEEDS - 1, _spread(before), _spread(after)])
	return ""


func test_same_seed_gives_the_same_level() -> String:
	var inputs: SeedLevel = _inputs()
	for level_seed: int in [31, 43, 205]:
		var first: MineGenerator = inputs.generate(level_seed)
		var a: LevelDef = _level(inputs, first)
		var second: MineGenerator = inputs.generate(level_seed)
		var b: LevelDef = _level(inputs, second)
		if first.output_hash() != second.output_hash():
			return "seed %d: output_hash differs" % level_seed
		if a.reactor == null or b.reactor == null or a.reactor.position_mm != b.reactor.position_mm:
			return "seed %d: reactors differ" % level_seed
	return ""


func test_seed_31_reactor_left_the_start() -> String:
	# The owner's seed: the escape took about six seconds before #912.
	var inputs: SeedLevel = _inputs()
	var generator: MineGenerator = inputs.generate(31)
	var level: LevelDef = _level(inputs, generator)
	var old: Vector3 = Vector3(_old_centre(generator)) / float(RobotSpawn.SCALE)
	var was: int = EscapePath.length_mm(level.union, old, level.start_position())
	var now: int = EscapePath.length_mm(level.union, level.reactor.position(), level.start_position())
	return "" if now > was else "seed 31: %d mm now, %d mm before" % [now, was]


## A generated level with its reactor moved to `module`'s largest box centre.
func _moved(inputs: SeedLevel, level_seed: int, module: int) -> LevelDef:
	var level: LevelDef = _level(inputs, inputs.generate(level_seed))
	var box: BoxBounds = level.union.boxes[ReactorFar.largest_box(level, module)]
	level.reactor.position_mm = EscapePath.to_mm((box.min_corner + box.max_corner) / 2.0)
	return level


func test_check_fails_a_reactor_in_or_next_to_the_start_module() -> String:
	var inputs: SeedLevel = _inputs()
	var level: LevelDef = _level(inputs, inputs.generate(43))
	var start: int = ReactorFar.module_at(level, level.start_position_mm)
	var joined: Array = ReactorFar.module_links(level)[start]
	if joined.is_empty():
		return "seed 43: the start's module is joined to nothing"
	var radius: float = inputs.tuning.radius
	var inside: String = ReactorFar.failure(_moved(inputs, 43, start), radius, 0.0)
	if not inside.begins_with("reactor_far:") or not inside.contains("which is the start's module"):
		return "reactor in the start module: \"%s\"" % inside
	var next: String = ReactorFar.failure(_moved(inputs, 43, joined[0]), radius, 0.0)
	if not next.begins_with("reactor_far:") or not next.contains("joined to the start's module"):
		return "reactor next to the start module: \"%s\"" % next
	# The same through the validator, under the check's own name.
	var found: Array[String] = inputs.validate(_moved(inputs, 43, start), inputs.generate(43))
	for message: String in found:
		if message.begins_with(ReactorFar.CHECK + ":"):
			return ""
	return "the validator did not report reactor_far: %s" % [found]


func test_check_fails_a_reactor_short_of_the_fraction() -> String:
	var inputs: SeedLevel = _inputs()
	var radius: float = inputs.tuning.radius
	for level_seed: int in range(0, 50):
		var level: LevelDef = _level(inputs, inputs.generate(level_seed))
		var found: ReactorFar = ReactorFar.survey(level, level.reactor.radius_mm, radius, 2)
		if found.modules.size() < 2:
			continue
		var shortest: int = 0
		for index: int in found.paths_mm.size():
			if found.paths_mm[index] < found.paths_mm[shortest]:
				shortest = index
		if found.paths_mm[shortest] >= found.longest_mm():
			continue
		var moved: LevelDef = _moved(inputs, level_seed, found.modules[shortest])
		if ReactorFar.failure(moved, radius, 0.0) != "":
			return "seed %d: a far module failed with no fraction" % level_seed
		var short: String = ReactorFar.failure(moved, radius, 1.0)
		return "" if short.begins_with("reactor_far:") and short.contains("below 100%") \
				else "seed %d: \"%s\"" % [level_seed, short]
	return "no seed in 0..49 has two far modules of different paths"


func test_lengths_mm_matches_length_mm() -> String:
	var inputs: SeedLevel = _inputs()
	for level_seed: int in range(0, 20):
		var level: LevelDef = _level(inputs, inputs.generate(level_seed))
		var points: Array[Vector3i] = []
		for box: BoxBounds in level.union.boxes:
			points.append(EscapePath.to_mm((box.min_corner + box.max_corner) / 2.0))
		points.append(Vector3i(999999, 0, 0))
		var together: Array[int] = EscapePath.lengths_mm(level.union, level.start_position(), points)
		for index: int in points.size():
			var alone: int = EscapePath.length_mm(level.union,
					Vector3(points[index]) / float(RobotSpawn.SCALE), level.start_position())
			if together[index] != alone:
				return "seed %d point %d: %d together, %d alone" % [level_seed, index, together[index], alone]
	return ""
