extends RefCounted

## The first seeded mine generator (#294, GEN-1, GEN-2, GEN-5, ARC-1, ARC-2):
## the same seed gives the same level, different seeds differ, and over 1,000
## seeds every level is one piece, every join meets exactly and no two modules
## overlap except through their doorway.

const MODULES_DIR: String = "res://data/modules/"
const MODULE_COUNT: int = 10
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 10000


func _modules() -> Array[ModuleDef]:
	var modules: Array[ModuleDef] = []
	var files: PackedStringArray = DirAccess.get_files_at(MODULES_DIR)
	files.sort()
	for file: String in files:
		if file.ends_with(".json"):
			modules.append(ModuleDef.parse_json(FileAccess.get_file_as_string(MODULES_DIR + file)))
	return modules


func _by_id(modules: Array[ModuleDef]) -> Dictionary[String, ModuleDef]:
	var found: Dictionary[String, ModuleDef] = {}
	for module: ModuleDef in modules:
		found[module.id] = module
	return found


func test_turns_are_the_24_rotations_with_identity_first() -> String:
	var rows: Array[Array] = ModuleTurns.rows()
	if rows.size() != ModuleTurns.COUNT:
		return "%d turns, expected 24" % rows.size()
	var probe: Vector3i = Vector3i(1, 20, 300)
	if ModuleTurns.apply(0, probe) != probe:
		return "turn 0 moves %s to %s" % [probe, ModuleTurns.apply(0, probe)]
	var seen: Array[Vector3i] = []
	for turn: int in ModuleTurns.COUNT:
		var turned: Vector3i = ModuleTurns.apply(turn, probe)
		if seen.has(turned):
			return "turn %d repeats an earlier turn" % turn
		seen.append(turned)
	var four: Array[int] = ModuleTurns.turns_between(Vector3i(0, 1, 0), Vector3i(0, 0, -1))
	return "" if four.size() == 4 else "%d turns point +y along -z, expected 4" % four.size()


func test_same_seed_gives_the_same_level_and_hash() -> String:
	var modules: Array[ModuleDef] = _modules()
	var first: MineGenerator = MineGenerator.generate(4242, modules, MODULE_COUNT)
	var second: MineGenerator = MineGenerator.generate(4242, modules, MODULE_COUNT)
	if first.output_hash() != second.output_hash():
		return "hashes differ: %d and %d" % [first.output_hash(), second.output_hash()]
	if first.min_mm != second.min_mm or first.max_mm != second.max_mm:
		return "same seed, different boxes"
	if first.placements.size() != second.placements.size():
		return "same seed, different module counts"
	for index: int in first.placements.size():
		var a: ModulePlacement = first.placements[index]
		var b: ModulePlacement = second.placements[index]
		if a.module_id != b.module_id or a.turn != b.turn or a.offset_mm != b.offset_mm:
			return "placement %d differs" % index
	return ""


func test_two_seeds_give_different_levels() -> String:
	var modules: Array[ModuleDef] = _modules()
	var a: MineGenerator = MineGenerator.generate(1, modules, MODULE_COUNT)
	var b: MineGenerator = MineGenerator.generate(2, modules, MODULE_COUNT)
	if a.output_hash() == b.output_hash():
		return "seeds 1 and 2 give the same hash"
	return "" if a.min_mm != b.min_mm else "seeds 1 and 2 give the same boxes"


func test_output_lists_placements_boxes_and_open_connectors() -> String:
	var modules: Array[ModuleDef] = _modules()
	var level: MineGenerator = MineGenerator.generate(7, modules, MODULE_COUNT)
	if level.note != "":
		return "stopped short: %s" % level.note
	if level.placements.size() != MODULE_COUNT:
		return "%d modules placed" % level.placements.size()
	if level.union.boxes.size() != level.min_mm.size():
		return "union has %d boxes, millimetre list %d" % [level.union.boxes.size(), level.min_mm.size()]
	var catalogue: Dictionary[String, ModuleDef] = _by_id(modules)
	var connectors: int = 0
	for placement: ModulePlacement in level.placements:
		connectors += catalogue[placement.module_id].connectors.size()
	# Each join uses two connectors.
	var expected: int = connectors - 2 * (MODULE_COUNT - 1)
	if level.open_connectors.size() != expected:
		return "%d open connectors, expected %d" % [level.open_connectors.size(), expected]
	var first: ModulePlacement = level.placements[0]
	if first.turn != 0 or first.offset_mm != Vector3i.ZERO or first.door_box != -1:
		return "first module is not placed as authored at the origin"
	return ""


func test_stops_short_and_says_so() -> String:
	var tunnel: ModuleDef = ModuleDef.parse_json(JSON.stringify({
		"id": "dead_end",
		"boxes": [{"min": [-5, -5, -30], "max": [5, 5, 0]}],
		"connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "small"}],
	}))
	var level: MineGenerator = MineGenerator.generate(3, [tunnel], 5)
	if level.placements.size() != 2:
		return "%d dead ends placed, expected 2" % level.placements.size()
	if not level.note.contains("stopped after 2 of 5"):
		return "note is \"%s\"" % level.note
	var empty: MineGenerator = MineGenerator.generate(3, [], 5)
	return "" if empty.placements.is_empty() and empty.note != "" else "an empty module list placed something"


func test_a_walled_in_opening_gives_up_after_bounded_tries() -> String:
	# A 20 m tube whose one opening is ringed by fins standing past its face:
	# the gap between them is under 9 m, so no 20 m module can join there.
	var fin_z: Array = [-5, 10]
	var walled: ModuleDef = ModuleDef.parse_json(JSON.stringify({
		"id": "walled",
		"boxes": [
			{"min": [-10, -10, -30], "max": [10, 10, 0]},
			{"min": [4.5, -12, fin_z[0]], "max": [12, 12, fin_z[1]]},
			{"min": [-12, -12, fin_z[0]], "max": [-4.5, 12, fin_z[1]]},
			{"min": [-12, 4.5, fin_z[0]], "max": [12, 12, fin_z[1]]},
			{"min": [-12, -12, fin_z[0]], "max": [12, -4.5, fin_z[1]]},
		],
		"connectors": [{"position": [0, 0, 0], "axis": "+z", "size": "small"}],
	}))
	if walled.error != "":
		return "test module rejected: %s" % walled.error
	var level: MineGenerator = MineGenerator.generate(9, [walled], 3)
	if level.placements.size() != 1:
		return "%d modules placed through a walled-in opening" % level.placements.size()
	var expected: String = "no placement fit in %d tries" % MineGenerator.MAX_TRIES
	return "" if level.note.contains(expected) else "note is \"%s\"" % level.note


func test_thousand_seeds_are_whole_exact_and_apart() -> String:
	var modules: Array[ModuleDef] = _modules()
	var catalogue: Dictionary[String, ModuleDef] = _by_id(modules)
	var started: int = Time.get_ticks_msec()
	var short: int = 0
	for level_seed: int in SEEDS:
		var level: MineGenerator = MineGenerator.generate(level_seed, modules, MODULE_COUNT)
		if level.note != "":
			short += 1
		var problem: String = _check_level(level, catalogue)
		if problem != "":
			return "seed %d: %s" % [level_seed, problem]
	var elapsed: int = Time.get_ticks_msec() - started
	if elapsed > TIME_LIMIT_MS:
		return "%d seeds took %d ms, limit %d" % [SEEDS, elapsed, TIME_LIMIT_MS]
	return "" if short == 0 else "%d of %d seeds stopped short of %d modules" % [short, SEEDS, MODULE_COUNT]


func _check_level(level: MineGenerator, catalogue: Dictionary[String, ModuleDef]) -> String:
	var owner: Array[int] = []
	owner.resize(level.min_mm.size())
	owner.fill(-1)
	for index: int in level.placements.size():
		var placement: ModulePlacement = level.placements[index]
		for box: int in range(placement.first_box, placement.end_box):
			owner[box] = index
	for index: int in range(1, level.placements.size()):
		var problem: String = _check_join(level, catalogue, index)
		if problem != "":
			return problem
	for a: int in owner.size():
		for b: int in range(a + 1, owner.size()):
			if owner[a] < 0 or owner[b] < 0 or owner[a] == owner[b]:
				continue
			if MineGenerator.overlaps(level.min_mm[a], level.max_mm[a], level.min_mm[b], level.max_mm[b]):
				return "modules %d and %d overlap (boxes %d and %d)" % [owner[a], owner[b], a, b]
	for index: int in level.placements.size():
		var door: int = level.placements[index].door_box
		if door < 0:
			continue
		for box: int in owner.size():
			if box == door or owner[box] == index or owner[box] == level.placements[index].parent:
				continue
			if MineGenerator.overlaps(level.min_mm[door], level.max_mm[door], level.min_mm[box], level.max_mm[box]):
				return "doorway of module %d overlaps box %d" % [index, box]
	return _check_one_piece(level)


## The two joined connectors meet exactly (same place and size, axes opposite)
## and the doorway is joined to a box of each module.
func _check_join(level: MineGenerator, catalogue: Dictionary[String, ModuleDef], index: int) -> String:
	var child: ModulePlacement = level.placements[index]
	var parent: ModulePlacement = level.placements[child.parent]
	var mine: ModuleConnector = MineGenerator.placed_connector(catalogue[child.module_id],
			child.connector, child.turn, child.offset_mm)
	var theirs: ModuleConnector = MineGenerator.placed_connector(catalogue[parent.module_id],
			child.parent_connector, parent.turn, parent.offset_mm)
	if mine.position_mm != theirs.position_mm:
		return "module %d joins at %s, its parent's opening is at %s" % [index, mine.position_mm, theirs.position_mm]
	if mine.size_class != theirs.size_class:
		return "module %d joins a %s opening with a %s one" % [index, theirs.size_class, mine.size_class]
	if ModuleTurns.outward(mine) != -ModuleTurns.outward(theirs):
		return "module %d faces %s into an opening facing %s" % [index, mine.axis_name, theirs.axis_name]
	var door: BoxBounds = level.union.boxes[child.door_box]
	for placement: ModulePlacement in [child, parent]:
		var joined: bool = false
		for box: int in range(placement.first_box, placement.end_box):
			if LevelDef.joined(door, level.union.boxes[box]):
				joined = true
		if not joined:
			return "doorway of module %d is not joined to %s" % [index, placement.module_id]
	return ""


## Every box reachable from box 0 through `LevelDef.joined`.
func _check_one_piece(level: MineGenerator) -> String:
	var boxes: Array[BoxBounds] = level.union.boxes
	var reached: Array[bool] = []
	reached.resize(boxes.size())
	reached.fill(false)
	reached[0] = true
	var queue: Array[int] = [0]
	while not queue.is_empty():
		var index: int = queue.pop_front()
		for other: int in boxes.size():
			if not reached[other] and LevelDef.joined(boxes[index], boxes[other]):
				reached[other] = true
				queue.append(other)
	var missing: int = reached.count(false)
	return "" if missing == 0 else "%d boxes not joined to box 0" % missing
