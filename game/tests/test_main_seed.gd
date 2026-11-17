extends RefCounted

## The main scene flies the generated level for `--seed=<n>` (#382, GEN-1,
## GEN-2, GEN-5). Scenes are instantiated outside the tree, so `_ready` does
## not run; the tests call `use_level` as `_ready` does with the switch's source.

const SEED: int = 7
const G2_FILE: String = "res://data/levels/g2_level.json"
## In range, but no opening is 20 ship diameters wide, so seed 7 fails it.
const STRICT_VALIDATOR: String = "{\"min_passage_ship_diameters\": 20, \"escape_speed_mps\": 10, \"escape_margin\": 0.8}"


func _main() -> Node:
	return (load("res://main.tscn") as PackedScene).instantiate()


## Seed 7 built straight from `MineGenerator`, as the sweep builds it.
func _generated(level_seed: int) -> LevelDef:
	var tuning: ShipTuning = ShipTuning.parse_json(FileAccess.get_file_as_string(SeedLevel.SHIP_FILE))
	var generator: MineGenerator = MineGenerator.generate(level_seed, SeedLevel.load_modules(),
			SeedLevel.MODULE_COUNT, LoopBridges.parse_json(FileAccess.get_file_as_string(SeedLevel.GENERATOR_FILE)))
	return generator.to_level_def(ReactorPlan.parse_json(FileAccess.get_file_as_string(SeedLevel.REACTOR_FILE)),
			tuning.radius)


## The session's walls as one comparable list of corners.
func _corners(boxes: Array[BoxBounds]) -> Array[Vector3]:
	var corners: Array[Vector3] = []
	for box: BoxBounds in boxes:
		corners.append_array([box.min_corner, box.max_corner])
	return corners


func test_switch_reads_seed_argument_then_intent_and_level_wins() -> String:
	var none: PackedStringArray = PackedStringArray()
	var cases: Array[Array] = [
		[none, "", "", ""],
		[PackedStringArray(["--seed=7"]), "", "", "seed:7"],
		[none, "", " 12 ", "seed:12"],
		[PackedStringArray(["--seed=3", "--seed=0"]), "", "", "seed:0"],
		[PackedStringArray(["--seed=5"]), "", "9", "seed:5"],
		[PackedStringArray(["--level=g2", "--seed=7"]), "", "", G2_FILE],
		[PackedStringArray(["--seed=7"]), "g2", "", G2_FILE],
		[none, "g2", "7", G2_FILE],
		[PackedStringArray(["--acceptance=all"]), "", "", ""],
	]
	for case: Array in cases:
		var got: String = LevelSwitch.requested_source(case[0], case[1], case[2])
		if got != case[3]:
			return "args %s, intents \"%s\"/\"%s\": got \"%s\", expected \"%s\"" % [
					case[0], case[1], case[2], got, case[3]]
	# The test runner is started without either switch.
	if LevelSwitch.requested_path() != "":
		return "a run without switches asks for %s" % LevelSwitch.requested_path()
	return ""


func test_a_bad_seed_is_ignored_and_the_tunnel_stays() -> String:
	for bad: String in ["-1", "abc", "7.5", "+7", "1e3", "7 7", "1234567890123456789"]:
		var source: String = LevelSwitch.requested_source(PackedStringArray(["--seed=" + bad]), "", "")
		if source != "":
			return "--seed=%s gave \"%s\"" % [bad, source]
		if LevelSwitch.requested_source(PackedStringArray(), "", bad) != "":
			return "intent seed %s was accepted" % bad
	var main: Node = _main()
	var before: LocalSession = main.get("session")
	var flown: bool = main.call("use_level", "seed:x")
	var same: bool = before == main.get("session")
	var tunnel_ok: bool = main.get_node_or_null(LevelSwitch.TUNNEL_NODE) != null
	main.free()
	if flown or not same or not tunnel_ok:
		return "a bad seed source replaced the tunnel"
	return ""


func test_seed_7_flies_the_generated_walls_start_and_reactor() -> String:
	var main: Node = _main()
	var flown: bool = main.call("use_level", LevelSwitch.requested_source(
			PackedStringArray(["--seed=%d" % SEED]), "", ""))
	var session: LocalSession = main.get("session")
	var tunnel_gone: bool = main.get_node_or_null(LevelSwitch.TUNNEL_NODE) == null
	var want: LevelDef = _generated(SEED)
	var problem: String = ""
	if not flown:
		problem = "use_level refused seed %d" % SEED
	elif want.error != "" or want.reactor == null:
		problem = "seed %d builds no flyable level with a reactor: %s" % [SEED, want.error]
	elif session.sim.walls == null or _corners(session.sim.walls.boxes) != _corners(want.union.boxes):
		problem = "session walls are not the generator's %d boxes" % want.union.boxes.size()
	elif not tunnel_gone:
		problem = "the test tunnel is still drawn"
	if problem == "":
		var ship: ShipState = session.current_ship()
		if not ship.position.is_equal_approx(want.start_position()):
			problem = "ship starts at %s, generator says %s" % [ship.position, want.start_position()]
		elif not (-ship.orientation.z).is_equal_approx(want.start_facing()):
			problem = "ship faces %s, generator says %s" % [-ship.orientation.z, want.start_facing()]
		elif session.sim.reactor == null:
			problem = "the session has no reactor"
		elif session.sim.reactor.position_mm != want.reactor.position_mm:
			problem = "reactor at %s, generator says %s" % [session.sim.reactor.position_mm,
					want.reactor.position_mm]
	main.free()
	return problem


func test_the_same_seed_twice_gives_the_same_walls() -> String:
	var first: LevelDef = LevelSwitch.load_level("seed:%d" % SEED)
	var second: LevelDef = LevelSwitch.load_level("seed:%d" % SEED)
	var other: LevelDef = LevelSwitch.load_level("seed:%d" % (SEED + 1))
	if first == null or second == null or other == null:
		return "a seed was rejected"
	if _corners(first.union.boxes) != _corners(second.union.boxes):
		return "seed %d gave different walls twice" % SEED
	if first.start_position_mm != second.start_position_mm \
			or first.reactor.position_mm != second.reactor.position_mm:
		return "seed %d gave a different start or reactor twice" % SEED
	if _corners(first.union.boxes) == _corners(other.union.boxes):
		return "seeds %d and %d gave the same walls" % [SEED, SEED + 1]
	return ""


func test_exit_radius_comes_from_the_defaults_file() -> String:
	var level: LevelDef = LevelSwitch.load_level("seed:%d" % SEED)
	var defaults: LevelDefaults = LevelSwitch.load_defaults()
	if level == null or defaults == null:
		return "seed or defaults rejected"
	if level.exit_radius_mm != defaults.exit_radius_mm or level.reactor.exit_radius_mm != defaults.exit_radius_mm:
		return "exit radius %d / reactor %d, defaults say %d" % [level.exit_radius_mm,
				level.reactor.exit_radius_mm, defaults.exit_radius_mm]
	return ""


func test_a_level_that_fails_the_validator_is_not_flown() -> String:
	if SeedLevel.load_level(SEED, LevelSwitch.DEFAULTS_FILE, STRICT_VALIDATOR) != null:
		return "a level failing the validator was handed over"
	if SeedLevel.load_level(SEED, LevelSwitch.DEFAULTS_FILE) == null:
		return "seed %d fails the shipped validator" % SEED
	return ""


func test_level_g2_wins_over_seed_7() -> String:
	var main: Node = _main()
	var flown: bool = main.call("use_level", LevelSwitch.requested_source(
			PackedStringArray(["--level=g2", "--seed=%d" % SEED]), "", ""))
	var session: LocalSession = main.get("session")
	var g2: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))
	var same: bool = session.sim.walls != null \
			and _corners(session.sim.walls.boxes) == _corners(g2.union.boxes)
	main.free()
	if not flown:
		return "use_level refused --level=g2 --seed=7"
	if not same:
		return "--level=g2 --seed=7 did not fly G2's walls"
	return ""


func test_main_stays_under_300_lines() -> String:
	var lines: int = FileAccess.get_file_as_string("res://main.gd").split("\n").size()
	# A trailing newline adds one empty element.
	if lines - 1 > 300:
		return "main.gd has %d lines" % (lines - 1)
	return ""
