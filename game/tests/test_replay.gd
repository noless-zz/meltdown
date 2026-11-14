extends RefCounted

const BASIC_FLIGHT: String = "res://tests/replays/basic_flight.replay"
const SCRATCH_PATH: String = "user://test_replay_roundtrip.replay"
const TICKS: int = 600


## Scripted flight with no randomness: accelerate, turn while strafing, roll
## and climb, then coast. `basic_flight.replay` was generated from this with
## seed 20261114 and one ship.
func _scripted_input(tick: int, ship: int) -> ShipInput:
	var side: int = 1 if ship % 2 == 0 else -1
	if tick < 120:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO)
	if tick < 300:
		return ShipInput.new(Vector3i(300 * side, 0, -800), Vector3i(0, 700 * side, 0))
	if tick < 480:
		# Changes every tick so that a replay which drops or reorders lines fails.
		var wave: int = (tick * 37) % 401 - 200
		return ShipInput.new(Vector3i(wave, 500, -1000), Vector3i(-350, wave, 900 * side))
	return ShipInput.new()


func _record(run_seed: int, ship_count: int) -> Replay:
	var replay: Replay = Replay.new(run_seed, ship_count)
	var sim: Sim = Sim.new(run_seed, ship_count)
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = []
		for ship: int in ship_count:
			inputs.append(_scripted_input(tick, ship))
		replay.add_tick(inputs)
		sim.step(inputs)
	replay.expected_hash = sim.state_hash()
	return replay


func test_record_save_reload_replay_gives_same_hash() -> String:
	var recorded: Replay = _record(42, 2)
	var save_error: Error = recorded.save(SCRATCH_PATH)
	if save_error != OK:
		return "could not save replay: %s" % error_string(save_error)
	var loaded: Replay = Replay.load_file(SCRATCH_PATH)
	DirAccess.remove_absolute(SCRATCH_PATH)
	if loaded.error != "":
		return "reload failed: %s" % loaded.error
	if loaded.frames.size() != TICKS:
		return "expected %d ticks after reload, got %d" % [TICKS, loaded.frames.size()]
	var sim: Sim = loaded.run()
	if sim.tick != TICKS:
		return "replay simulated %d ticks, expected %d" % [sim.tick, TICKS]
	if sim.state_hash() != recorded.expected_hash:
		return "replayed hash %d differs from recorded hash %d" % [sim.state_hash(), recorded.expected_hash]
	return ""


func test_text_round_trip_is_exact() -> String:
	var recorded: Replay = _record(-5, 2)
	var text: String = recorded.to_text()
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return loaded.error
	if loaded.run_seed != -5 or loaded.ship_count != 2 or loaded.expected_hash != recorded.expected_hash:
		return "header changed in the round trip"
	if loaded.to_text() != text:
		return "text changed in the round trip"
	return ""


func test_header_has_version_and_seed_then_one_line_per_tick() -> String:
	var lines: PackedStringArray = _record(42, 1).to_text().strip_edges().split("\n")
	if lines[0] != "meltdown-replay 1":
		return "first line is '%s'" % lines[0]
	if lines[1] != "seed 42":
		return "second line is '%s'" % lines[1]
	var start: int = lines.find("inputs") + 1
	if start == 0 or lines.size() - start != TICKS:
		return "expected %d input lines after the header" % TICKS
	return ""


func test_basic_flight_replay_keeps_its_hash() -> String:
	var replay: Replay = Replay.load_file(BASIC_FLIGHT)
	if replay.error != "":
		return "%s: %s" % [BASIC_FLIGHT, replay.error]
	if replay.expected_hash == Replay.NO_HASH:
		return "%s has no hash line" % BASIC_FLIGHT
	if replay.frames.size() != TICKS:
		return "%s has %d ticks, expected %d" % [BASIC_FLIGHT, replay.frames.size(), TICKS]
	var actual: int = replay.run().state_hash()
	if actual != replay.expected_hash:
		return ("simulation behaviour changed: %s now ends with hash %d, the file expects %d. "
			+ "If the change is intended, update the hash line and say why in the pull request."
			) % [BASIC_FLIGHT, actual, replay.expected_hash]
	return ""


func test_basic_flight_replay_matches_the_script() -> String:
	# Guards the committed file itself: an edited input line fails here even if
	# someone also edits the hash to match.
	var replay: Replay = Replay.load_file(BASIC_FLIGHT)
	if replay.error != "":
		return replay.error
	var scripted: Replay = _record(replay.run_seed, replay.ship_count)
	scripted.expected_hash = replay.expected_hash
	if replay.to_text() != scripted.to_text():
		return "%s no longer matches _scripted_input" % BASIC_FLIGHT
	return ""


func test_changed_input_changes_the_hash() -> String:
	var replay: Replay = _record(42, 1)
	var inputs: Array[ShipInput] = [ShipInput.new(Vector3i(0, 0, -999), Vector3i.ZERO)]
	replay.frames[10] = inputs
	if replay.run().state_hash() == replay.expected_hash:
		return "changing one input did not change the final hash"
	return ""


func test_frame_of_the_wrong_size_fails_the_run() -> String:
	# Frames can be edited in memory after add_tick has checked them.
	var replay: Replay = _record(42, 2)
	var short_frame: Array[ShipInput] = [ShipInput.new()]
	replay.frames[10] = short_frame
	if replay.run() != null:
		return "run() returned a Sim although tick 10 has one input for two ships"
	if not replay.run_error.begins_with("tick 10:"):
		return "run_error does not name the tick: '%s'" % replay.run_error
	var long_frame: Array[ShipInput] = [ShipInput.new(), ShipInput.new(), ShipInput.new()]
	replay.frames[10] = long_frame
	if replay.run() != null:
		return "run() returned a Sim although tick 10 has three inputs for two ships"
	return ""


func test_run_error_is_cleared_by_a_complete_run() -> String:
	var replay: Replay = _record(42, 1)
	var good_frame: Array = replay.frames[5]
	var empty_frame: Array[ShipInput] = []
	replay.frames[5] = empty_frame
	if replay.run() != null or replay.run_error == "":
		return "an empty frame did not fail the run"
	replay.frames[5] = good_frame
	var sim: Sim = replay.run()
	if sim == null or replay.run_error != "":
		return "a repaired replay still fails: '%s'" % replay.run_error
	if sim.state_hash() != replay.expected_hash:
		return "a repaired replay gives another hash"
	return ""


func test_negative_hash_is_rejected_with_its_line_number() -> String:
	for value: String in ["-1", "-4190313060"]:
		var replay: Replay = Replay.from_text(
			"meltdown-replay 1\nseed 1\nships 1\nhash %s\ninputs\n0 0 0 0 0 0\n" % value)
		if replay.error == "":
			return "accepted 'hash %s'" % value
		if not replay.error.begins_with("line 4:"):
			return "error for 'hash %s' does not name line 4: '%s'" % [value, replay.error]
	return ""


func test_missing_hash_line_means_no_expected_hash() -> String:
	var replay: Replay = Replay.from_text(
		"meltdown-replay 1\nseed 1\nships 1\ninputs\n0 0 0 0 0 0\n")
	if replay.error != "":
		return replay.error
	if replay.expected_hash != Replay.NO_HASH:
		return "expected NO_HASH without a hash line, got %d" % replay.expected_hash
	var zero: Replay = Replay.from_text(
		"meltdown-replay 1\nseed 1\nships 1\nhash 0\ninputs\n0 0 0 0 0 0\n")
	if zero.error != "" or zero.expected_hash != 0:
		return "'hash 0' is a valid hash and must be kept"
	return ""


func test_bad_text_is_rejected_with_a_message() -> String:
	var cases: Dictionary[String, String] = {
		"empty": "",
		"wrong version": "meltdown-replay 2\nseed 1\nships 1\ninputs\n",
		"no format line": "seed 1\nships 1\ninputs\n",
		"no seed": "meltdown-replay 1\nships 1\ninputs\n",
		"no inputs section": "meltdown-replay 1\nseed 1\nships 1\n",
		"too few numbers": "meltdown-replay 1\nseed 1\nships 1\ninputs\n0 0 0 0 0\n",
		"not a number": "meltdown-replay 1\nseed 1\nships 1\ninputs\n0 0 0 0 0 x\n",
		"fractional number": "meltdown-replay 1\nseed 1\nships 1\ninputs\n0 0 0.5 0 0 0\n",
		"wrong ship count": "meltdown-replay 1\nseed 1\nships 2\ninputs\n0 0 0 0 0 0\n",
		"unknown header": "meltdown-replay 1\nseed 1\nships 1\nwind 3\ninputs\n",
	}
	for name: String in cases:
		if Replay.from_text(cases[name]).error == "":
			return "accepted bad replay text: %s" % name
	return ""


func test_comments_and_blank_lines_are_ignored() -> String:
	var replay: Replay = Replay.from_text(
		"# a note\nmeltdown-replay 1\nseed 9\nships 1\n\ninputs\n# tick 0\n0 0 -1000 0 0 0\n")
	if replay.error != "":
		return replay.error
	if replay.frames.size() != 1 or replay.run_seed != 9:
		return "comment or blank line was not skipped"
	return ""


func test_missing_file_reports_an_error() -> String:
	if Replay.load_file("res://tests/replays/does_not_exist.replay").error == "":
		return "loading a missing file gave no error"
	return ""
