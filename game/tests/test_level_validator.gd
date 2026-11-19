extends RefCounted

## The level validator (#317, GEN-3, GEN-2, GEN-5, ARC-1): generated levels
## convert to a `LevelDef`, seeds 1 to 1,000 all pass in under 20 s, and hand-
## built broken levels fail with a message naming the check and the box.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const SEEDS: int = 1000
const TIME_LIMIT_MS: int = 20000
const SHIP_RADIUS: float = 1.0


func _validator() -> LevelValidator:
	return LevelValidator.new()


## These hand-built levels have no reactor; its checks are in
## `test_level_validator_reactor.gd`.
func _check(level: LevelDef, radius: float) -> Array[String]:
	return _validator().validate(level, radius, false)


## A level of the given boxes (corner pairs, metres) starting at `start`.
func _level(corners: Array[Vector3], start: Vector3) -> LevelDef:
	var boxes: Array[BoxBounds] = []
	for index: int in range(0, corners.size(), 2):
		boxes.append(BoxBounds.new(corners[index], corners[index + 1]))
	var level: LevelDef = LevelDef.new()
	level.union = BoxUnion.new(boxes)
	level.start_position_mm = Vector3i((start * float(RobotSpawn.SCALE)).round())
	return level


## Box 0: a 10 m tunnel along -z from 0 to -30.
func _tunnel() -> Array[Vector3]:
	return [Vector3(-5, -5, -30), Vector3(5, 5, 0)]


func _has(failures: Array[String], check: String, names: String) -> bool:
	for message: String in failures:
		if message.begins_with(check + ":") and message.contains(names):
			return true
	return false


func test_data_file_reads_2_5_diameters_and_5_m_for_the_ship() -> String:
	var validator: LevelValidator = SeedSweep.load_validator()
	if validator.error != "":
		return "validator.json rejected: %s" % validator.error
	if not is_equal_approx(validator.min_passage_ship_diameters, 2.5):
		return "read %s diameters, expected 2.5" % validator.min_passage_ship_diameters
	var narrowest: float = validator.min_passage(SeedSweep.ship_radius())
	return "" if is_equal_approx(narrowest, 5.0) else "min passage %s m, expected 5" % narrowest


func test_bad_data_files_are_rejected_with_a_reason() -> String:
	var cases: Dictionary[String, String] = {
		"{\"min_passage_ship_diameters\": 2.5, \"extra\": 1}": "unknown key \"extra\"",
		"{}": "missing key \"min_passage_ship_diameters\"",
		"{\"min_passage_ship_diameters\": \"wide\", \"escape_speed_mps\": 10, \"escape_margin\": 0.8}": "must be a number",
		"{\"min_passage_ship_diameters\": 0.5, \"escape_speed_mps\": 10, \"escape_margin\": 0.8}": "must be 1.0..20.0",
		"[1]": "top level",
	}
	for text: String in cases:
		var validator: LevelValidator = LevelValidator.parse_json(text)
		if not validator.error.contains(cases[text]):
			return "%s gave \"%s\", expected it to mention %s" % [text, validator.error, cases[text]]
	return ""


func test_generated_level_converts_with_start_inside_the_first_open_connector() -> String:
	var generator: MineGenerator = MineGenerator.generate(7, SeedSweep.load_modules(), SeedSweep.MODULE_COUNT)
	var level: LevelDef = generator.to_level_def()
	if level.error != "":
		return "conversion failed: %s" % level.error
	if level.union.boxes.size() != generator.union.boxes.size():
		return "%d boxes, generator has %d" % [level.union.boxes.size(), generator.union.boxes.size()]
	if generator.open_owner[0].x != 0:
		return "seed 7's oldest open connector is not on the first module; pick another seed"
	var opening: ModuleConnector = generator.open_connectors[0]
	var inward: Vector3i = -ModuleTurns.outward(opening)
	if level.start_facing_mm != inward * RobotSpawn.SCALE:
		return "facing %s, expected %s (inward)" % [level.start_facing_mm, inward]
	var expected: Vector3i = opening.position_mm + inward * MineGenerator.START_INSET_MM
	if level.start_position_mm != expected:
		return "start %s, expected %s" % [level.start_position_mm, expected]
	if not level.robots.spawns.is_empty() or level.reactor != null:
		return "a generated level should have no robots or reactor yet"
	return "" if level.union.holds(level.start_position(), LevelDef.CLEARANCE_M) else "start not held"


func test_level_with_no_open_connector_is_empty_with_an_error() -> String:
	var generator: MineGenerator = MineGenerator.new()
	var level: LevelDef = generator.to_level_def()
	if level.error == "":
		return "no error for a level with no open connector"
	return "" if level.union.boxes.is_empty() else "a failed level still has boxes"


func test_sound_hand_built_level_passes() -> String:
	var corners: Array[Vector3] = _tunnel()
	corners.append_array([Vector3(-5, -5, -40), Vector3(25, 5, -28)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	return "" if failures.is_empty() else "failed: %s" % [failures]


func test_gap_fails_the_piece_check_naming_the_box() -> String:
	var corners: Array[Vector3] = _tunnel()
	corners.append_array([Vector3(-5, -5, -60), Vector3(5, 5, -31)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	if not _has(failures, "piece", "box 1"):
		return "no piece failure naming box 1: %s" % [failures]
	return "" if _has(failures, "reachable", "box 1") else "box 1 not reported unreachable: %s" % [failures]


func test_boxes_that_only_touch_are_a_gap() -> String:
	var corners: Array[Vector3] = _tunnel()
	corners.append_array([Vector3(-5, -5, -60), Vector3(5, 5, -30)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	return "" if _has(failures, "piece", "box 1") else "touching boxes passed: %s" % [failures]


func test_too_narrow_opening_fails_the_passage_check_naming_both_boxes() -> String:
	var corners: Array[Vector3] = _tunnel()
	# Crossed along z: 4 m across y, 10 m across x, 10 m deep. A 4 m side
	# must count as a width even when it is the region's thinnest.
	corners.append_array([Vector3(-5, -2, -60), Vector3(5, 2, -20)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	if not _has(failures, "passage", "boxes 0 and 1"):
		return "no passage failure naming boxes 0 and 1: %s" % [failures]
	if not failures[0].contains("4.00 x 10.00 m"):
		return "message does not give the opening's widths: %s" % failures[0]
	return "" if not _has(failures, "piece", "box 1") else "narrow but connected box called a gap"


func test_opening_exactly_at_the_minimum_passes() -> String:
	var corners: Array[Vector3] = _tunnel()
	corners.append_array([Vector3(-2.5, -2.5, -60), Vector3(2.5, 2.5, -25)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	return "" if failures.is_empty() else "a 5 x 5 m opening failed: %s" % [failures]


func test_box_entered_only_through_a_sliver_is_unreachable() -> String:
	var corners: Array[Vector3] = _tunnel()
	# Shares a 10 x 10 m face 1 m deep: one piece, wide, but a ship cannot be
	# held by both boxes at once, so it never crosses (LevelDef.joined).
	corners.append_array([Vector3(-5, -5, -60), Vector3(5, 5, -29)])
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -3)), SHIP_RADIUS)
	if not _has(failures, "reachable", "box 1 cannot be reached from start box 0"):
		return "no reachable failure for box 1: %s" % [failures]
	return "" if failures.size() == 1 else "expected only the reachable failure: %s" % [failures]


func test_start_outside_every_box_fails_the_start_check() -> String:
	var failures: Array[String] = _check(_level(_tunnel(), Vector3(0, 0, -0.5)), SHIP_RADIUS)
	return "" if _has(failures, "start", "not held") else "no start failure: %s" % [failures]


func test_reachability_counts_from_the_box_holding_the_start() -> String:
	var corners: Array[Vector3] = _tunnel()
	corners.append_array([Vector3(-5, -5, -60), Vector3(5, 5, -29), Vector3(-5, -5, -80), Vector3(5, 5, -50)])
	# Start in box 2: box 1 is reachable from it, box 0 only through a sliver.
	var failures: Array[String] = _check(_level(corners, Vector3(0, 0, -70)), SHIP_RADIUS)
	var expected: Array[String] = ["reachable: box 0 cannot be reached from start box 2"]
	return "" if failures == expected else "unexpected failures: %s" % [failures]


func test_empty_level_fails() -> String:
	var failures: Array[String] = _check(LevelDef.new(), SHIP_RADIUS)
	return "" if _has(failures, "piece", "no boxes") else "empty level passed: %s" % [failures]


func test_seeds_1_to_1000_pass_in_under_20_s() -> String:
	var result: Dictionary = SeedSweep.run(1, SEEDS)
	print(SeedSweep.summary(result))
	print(SeedSweep.timing(result))
	if result["failed"] != 0:
		return "%d seeds failed, first: %s" % [result["failed"], result["failures"]]
	if result["passed"] != SEEDS:
		return "%d of %d seeds passed" % [result["passed"], SEEDS]
	if result["ms"] > TIME_LIMIT_MS:
		return "took %d ms, limit %d" % [result["ms"], TIME_LIMIT_MS]
	return ""


func test_summary_line_reads_counts_and_time() -> String:
	var line: String = SeedSweep.summary({"seeds": 3, "passed": 2, "failed": 1, "short": 0, "ms": 12})
	var expected: String = "level validator: 3 seeds, 2 passed, 1 failed, 0 stopped short, 12 ms"
	if line != expected:
		return "got \"%s\"" % line
	line = SeedSweep.summary({"seeds": 3, "passed": 2, "failed": 1, "short": 0, "ms": 12,
			"by_check": {"reactor": 0, "escape": 1}})
	expected += "; failing seeds by check: reactor 0, escape 1"
	return "" if line == expected else "got \"%s\"" % line
