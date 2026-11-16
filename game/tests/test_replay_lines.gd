extends RefCounted

## The box, tuning and tick lines moved from `Replay` into `ReplayLines`
## (#129). These pin the text so the move cannot change the format.

## Written by `Replay.to_text()` before the split, for `_sample()`.
const EXPECTED_TEXT: String = "meltdown-replay 13\nseed 7\nships 2\nhash 42\n" \
	+ "box -5000 -4000 -40000 5000 4000 1\n" \
	+ "tuning {\"max_speed\":23.456789012345,\"acceleration\":40.0,\"damping\":2.0," \
	+ "\"max_energy\":100.0,\"afterburner_max_speed\":35.0,\"afterburner_acceleration\":80.0," \
	+ "\"afterburner_drain\":25.0,\"energy_recharge\":12.5,\"afterburner_restart_energy\":25.0," \
	+ "\"max_hull\":100.0,\"radius\":1.0,\"wall_restitution\":0.5,\"wall_damage_per_speed\":0.5," \
	+ "\"wall_damage_min_speed\":4.0,\"max_shield\":50.0,\"shield_recharge\":5.0," \
	+ "\"shield_energy_cost\":1.0}\n" \
	+ "inputs\n1 2 3 4 5 6 1 0 1 0 | 0 0 0 0 0 0 0 0 0 0\n-7 0 1000 0 -250 0 0 1 0 1 | 0 0 -1000 0 0 0 1 1 1 0\n"

const HEADER: String = "meltdown-replay 6\nseed 1\nships 1\n"


func _sample() -> Replay:
	var tuning: ShipTuning = ShipTuning.new()
	# Not a round number, so a tuning line written with less precision fails.
	tuning.max_speed = 23.456789012345
	var replay: Replay = Replay.new(7, 2)
	replay.set_box(Vector3i(-5000, -4000, -40000), Vector3i(5000, 4000, 1))
	replay.tuning = tuning
	replay.expected_hash = 42
	var first: Array[ShipInput] = [
		ShipInput.new(Vector3i(1, 2, 3), Vector3i(4, 5, 6), true, false, true), ShipInput.new()]
	var second: Array[ShipInput] = [
		ShipInput.new(Vector3i(-7, 0, 1000), Vector3i(0, -250, 0), false, true, false, true),
		ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO, true, true, true)]
	replay.add_tick(first)
	replay.add_tick(second)
	return replay


func test_box_and_tuning_text_matches_the_text_before_the_split() -> String:
	var text: String = _sample().to_text()
	if text != EXPECTED_TEXT:
		return "text changed:\n%s" % text
	return ""


func test_box_and_tuning_replay_round_trips_to_the_same_text() -> String:
	var text: String = _sample().to_text()
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return "reload failed: " + loaded.error
	if not loaded.has_box or loaded.tuning == null:
		return "box or tuning lost on reload"
	if loaded.tuning.max_speed != 23.456789012345:
		return "max_speed read back as %s" % loaded.tuning.max_speed
	if loaded.to_text() != text:
		return "round trip changed the text:\n%s" % loaded.to_text()
	return ""


## Each input gives the message `from_text` gave before the split.
func test_rejections_keep_their_messages() -> String:
	var cases: Dictionary[String, String] = {
		"box 0 0 0 1 1 1\n" + HEADER + "inputs\n":
			"line 1: the first line must be 'meltdown-replay <version>'",
		"tuning {}\n" + HEADER + "inputs\n":
			"line 1: the first line must be 'meltdown-replay <version>'",
		"meltdown-replay 2\nseed 1\nships 1\nbox 0 0 0 1 1 1\ninputs\n":
			"line 4: a box line needs format version 3 or later",
		"meltdown-replay 4\nseed 1\nships 1\ntuning {}\ninputs\n":
			"line 4: a tuning line needs format version 5 or later",
		HEADER + "box 0 0 0 1 1 1\nbox 0 0 0 1 1 1\ninputs\n": "line 5: 'box' appears twice",
		HEADER + "box 0 0 0 1 1\ninputs\n": "line 4: box needs six whole numbers",
		HEADER + "box 0 0 x 1 1 1\ninputs\n": "line 4: 'x' is not a whole number",
		HEADER + "box 0 0 0 1 1 0\ninputs\n":
			"line 4: box min corner must be below its max corner on every axis",
		HEADER + "tuning {\"bogus\":1}\ninputs\n": "line 4: tuning: unknown key \"bogus\"",
		HEADER + "tuning {}\ninputs\n": "line 4: tuning: missing key \"max_speed\"",
		HEADER + "inputs\n0 0 0 0 0 0 0 0 2\n": "line 5: fire must be 0 or 1, found 2",
		HEADER + "inputs\n0 0 0 0 0 0 0 0\n": "line 5: each ship needs 9 numbers, found 8",
		HEADER + "inputs\n0 0 0 0 0 0 0 0 0 | 0 0 0 0 0 0 0 0 0\n":
			"line 5: expected inputs for 1 ships, found 2",
	}
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if replay.error != cases[text]:
			failures.append("%s: got '%s'" % [text.c_escape(), replay.error])
	return "\n".join(failures)


func test_numbers_per_ship_follows_the_format_versions() -> String:
	var expected: Array[int] = [6, 7, 7, 8, 8, 9, 9, 9, 9, 9, 10, 10, 10]
	for version: int in range(1, Replay.FORMAT_VERSION + 1):
		if ReplayLines.numbers_per_ship(version) != expected[version - 1]:
			return "version %d: %d numbers" % [version, ReplayLines.numbers_per_ship(version)]
	return ""
