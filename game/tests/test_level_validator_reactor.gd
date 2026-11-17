extends RefCounted

## The level validator's reactor and escape checks (#357, GEN-3, RUN-3, RUN-5):
## hand-built levels that fail each check name the problem, edge cases at the
## limits pass, the G2 level passes both, the data file needs the new keys, and
## the seed sweep counts failing seeds per check.

const SeedSweep := preload("res://tests/seed_sweep.gd")
const G2_LEVEL: String = "res://data/levels/g2_level.json"
const SHIP_RADIUS: float = 1.0


## The defaults match the shipped file: 10 m/s, 80 % of the countdown.
func _validator() -> LevelValidator:
	return LevelValidator.new()


## A 10 m tunnel along -z from 0 to -100, plus `more` corner pairs, starting at
## z = -3 with the reactor given as JSON fields (position and the rest).
func _level(reactor: Dictionary, more: Array[Vector3] = []) -> LevelDef:
	var corners: Array[Vector3] = [Vector3(-5, -5, -100), Vector3(5, 5, 0)]
	corners.append_array(more)
	var boxes: Array[BoxBounds] = []
	for index: int in range(0, corners.size(), 2):
		boxes.append(BoxBounds.new(corners[index], corners[index + 1]))
	var level: LevelDef = LevelDef.new()
	level.union = BoxUnion.new(boxes)
	level.start_position_mm = Vector3i(0, 0, -3000)
	if not reactor.is_empty():
		var fields: Dictionary = {"radius": 2.5, "hull": 400, "meltdown_seconds": 90}
		fields.merge(reactor, true)
		level.reactor = ReactorState.parse(fields)
		assert(level.reactor.error == "", level.reactor.error)
	return level


## The reactor 60 m down the tunnel from the start: a 6 s escape at 10 m/s.
func _sixty_metres() -> Dictionary:
	return {"position": [0, 0, -63]}


func _has(failures: Array[String], check: String, names: String) -> bool:
	for message: String in failures:
		if message.begins_with(check + ":") and message.contains(names):
			return true
	return false


func _none_from(failures: Array[String], checks: Array[String]) -> String:
	for message: String in failures:
		for check: String in checks:
			if message.begins_with(check + ":"):
				return "unexpected failure: %s" % message
	return ""


func test_data_file_reads_10_mps_and_80_percent() -> String:
	var validator: LevelValidator = SeedSweep.load_validator()
	if validator.error != "":
		return "validator.json rejected: %s" % validator.error
	if not is_equal_approx(validator.escape_speed_mps, 10.0):
		return "escape speed %s, expected 10" % validator.escape_speed_mps
	return "" if is_equal_approx(validator.escape_margin, 0.8) else "margin %s, expected 0.8" % validator.escape_margin


func test_file_without_the_new_keys_is_rejected_naming_both() -> String:
	var validator: LevelValidator = LevelValidator.parse_json("{\"min_passage_ship_diameters\": 2.5}")
	for key: String in ["escape_speed_mps", "escape_margin"]:
		if not validator.error.contains("missing key \"%s\"" % key):
			return "error \"%s\" does not name %s" % [validator.error, key]
	return ""


func test_new_keys_out_of_range_are_rejected() -> String:
	var cases: Dictionary[String, String] = {
		"\"escape_speed_mps\": 0.5, \"escape_margin\": 0.8": "\"escape_speed_mps\" must be 1.0..100.0",
		"\"escape_speed_mps\": 101, \"escape_margin\": 0.8": "\"escape_speed_mps\" must be 1.0..100.0",
		"\"escape_speed_mps\": \"fast\", \"escape_margin\": 0.8": "\"escape_speed_mps\" must be a number",
		"\"escape_speed_mps\": 10, \"escape_margin\": 0.05": "\"escape_margin\" must be 0.1..1.0",
		"\"escape_speed_mps\": 10, \"escape_margin\": 1.5": "\"escape_margin\" must be 0.1..1.0",
	}
	for fields: String in cases:
		var text: String = "{\"min_passage_ship_diameters\": 2.5, %s}" % fields
		var validator: LevelValidator = LevelValidator.parse_json(text)
		if not validator.error.contains(cases[fields]):
			return "%s gave \"%s\", expected %s" % [text, validator.error, cases[fields]]
	var edges: LevelValidator = LevelValidator.parse_json(
			"{\"min_passage_ship_diameters\": 2.5, \"escape_speed_mps\": 100, \"escape_margin\": 0.1}")
	return "" if edges.error == "" else "range ends rejected: %s" % edges.error


func test_sound_level_with_a_reactor_passes() -> String:
	var failures: Array[String] = _validator().validate(_level(_sixty_metres()), SHIP_RADIUS)
	return "" if failures.is_empty() else "failed: %s" % [failures]


func test_level_without_a_reactor_fails_unless_switched_off() -> String:
	var level: LevelDef = _level({})
	var failures: Array[String] = _validator().validate(level, SHIP_RADIUS)
	var expected: Array[String] = ["reactor: the level has no reactor"]
	if failures != expected:
		return "expected only the missing reactor: %s" % [failures]
	failures = _validator().validate(level, SHIP_RADIUS, false)
	return "" if failures.is_empty() else "switched off, still failed: %s" % [failures]


func test_reactor_in_rock_fails_the_reactor_check() -> String:
	var failures: Array[String] = _validator().validate(_level({"position": [20, 0, -50]}), SHIP_RADIUS)
	if not _has(failures, "reactor", "not held by any box with 4.50 m clear"):
		return "no reactor failure: %s" % [failures]
	return _none_from(failures, ["escape"])


func test_reactor_without_a_ship_diameter_clear_fails() -> String:
	# 3 m off the axis of a 10 m tunnel: 2 m to the wall, under 2.5 + 2 m.
	var failures: Array[String] = _validator().validate(_level({"position": [0, 3, -50]}), SHIP_RADIUS)
	return "" if _has(failures, "reactor", "not held") else "a cramped reactor passed: %s" % [failures]


func test_reactor_with_exactly_a_ship_diameter_clear_passes() -> String:
	# 0.5 m off the axis: 4.5 m to the wall, exactly 2.5 + 2 m.
	var failures: Array[String] = _validator().validate(_level({"position": [0, 0.5, -50]}), SHIP_RADIUS)
	return "" if failures.is_empty() else "failed: %s" % [failures]


func test_reactor_in_an_unreachable_box_fails_naming_it() -> String:
	# Box 1 overlaps the tunnel's end 1 m deep: one piece, but never joined.
	var more: Array[Vector3] = [Vector3(-5, -5, -140), Vector3(5, 5, -99)]
	var failures: Array[String] = _validator().validate(_level({"position": [0, 0, -120]}, more), SHIP_RADIUS)
	if not _has(failures, "reactor", "box 1 holds it but cannot be reached from start box 0"):
		return "no reactor failure naming box 1: %s" % [failures]
	return _none_from(failures, ["escape"])


func test_escape_too_long_for_the_timer_fails() -> String:
	# 60 m at 10 m/s is 6 s; 80 % of 7.4 s is 5.92 s.
	var reactor: Dictionary = _sixty_metres()
	reactor["meltdown_seconds"] = 7.4
	var failures: Array[String] = _validator().validate(_level(reactor), SHIP_RADIUS)
	if not _has(failures, "escape", "60.0 m from the reactor in box 0 to the exit takes 6.0 s at 10.0 m/s, over 5.9 s (80% of the 7.4 s countdown)"):
		return "no escape failure with the numbers: %s" % [failures]
	return "" if failures.size() == 1 else "expected only the escape failure: %s" % [failures]


func test_escape_exactly_at_the_margin_passes() -> String:
	# 80 % of 7.5 s is 6 s, the escape's time.
	var reactor: Dictionary = _sixty_metres()
	reactor["meltdown_seconds"] = 7.5
	var failures: Array[String] = _validator().validate(_level(reactor), SHIP_RADIUS)
	return "" if failures.is_empty() else "an escape at the margin failed: %s" % [failures]


func test_escape_is_timed_with_the_scaled_countdown_when_the_level_scales_it() -> String:
	# meltdown_seconds 90 would pass; the scaled countdown is what counts.
	var reactor: Dictionary = _sixty_metres()
	reactor.merge({"meltdown_base_seconds": 0, "meltdown_seconds_per_metre": 0.125,
			"meltdown_min_seconds": 1, "meltdown_max_seconds": 100})
	var failures: Array[String] = _validator().validate(_level(reactor), SHIP_RADIUS)
	if not failures.is_empty():
		return "7.5 s scaled countdown failed: %s" % [failures]
	reactor["meltdown_seconds_per_metre"] = 0.12
	failures = _validator().validate(_level(reactor), SHIP_RADIUS)
	return "" if _has(failures, "escape", "of the 7.2 s countdown") else "7.2 s countdown passed: %s" % [failures]


func test_g2_level_passes_the_reactor_and_escape_checks() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return "G2 rejected: %s" % level.error
	var failures: Array[String] = SeedSweep.load_validator().validate(level, SeedSweep.ship_radius())
	return _none_from(failures, ["reactor", "escape"])


func test_seed_sweep_counts_levels_too_short_for_a_reactor_under_reactor() -> String:
	# Two modules are one join apart, under reactor.json's min_hops of 2.
	var result: Dictionary = SeedSweep.run(1, 5, 2)
	var by_check: Dictionary = result["by_check"]
	if by_check["reactor"] != 5 or result["failed"] != 5:
		return "expected 5 seeds failing reactor: %s" % SeedSweep.summary(result)
	if not SeedSweep.summary(result).contains("reactor 5, escape 0"):
		return "summary does not report the new checks: %s" % SeedSweep.summary(result)
	return "" if (result["failures"][0] as String).contains("reactor: the level has no reactor") \
			else "first failure: %s" % result["failures"][0]
