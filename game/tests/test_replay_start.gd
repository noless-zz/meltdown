extends RefCounted

## A replay records each ship's start pose (#328, ARC-2, GEN-5): a ship that
## starts away from the origin replays to the live run's hash, a replay without
## a start line still starts at the origin facing -z, and an older version
## refuses the line.

const SEED: int = 328
const TICKS: int = 240
const START: Vector3 = Vector3(3.0, -2.0, 10.0)
const FACING: Vector3 = Vector3(1.0, 0.0, 0.0)


## Thrust, a turn, a reset to the start half way, then more flight, so the
## start pose is used both at the first tick and on the reset.
func _input(tick: int) -> ShipInput:
	if tick == TICKS / 2:
		return ShipInput.new(Vector3i.ZERO, Vector3i.ZERO, false, true)
	if tick % 60 < 30:
		return ShipInput.new(Vector3i(200, 0, -1000), Vector3i(0, 400, 150))
	return ShipInput.new(Vector3i(0, 300, -700), Vector3i(-250, 0, 0))


## Flies the live sim and records the same ticks; `start` decides whether the
## ship is put at START facing FACING first.
func _record(start: bool) -> Array:
	var replay: Replay = Replay.new(SEED, 1)
	var sim: Sim = Sim.new(SEED, 1)
	if start:
		replay.set_start_pose(0, START, FACING)
		sim.set_start_pose(0, START, Basis.looking_at(FACING, Vector3.UP))
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_input(tick)]
		replay.add_tick(inputs)
		sim.step(inputs)
	replay.expected_hash = sim.state_hash()
	return [replay, sim]


func test_a_ship_starting_away_from_the_origin_replays_to_the_live_hash() -> String:
	var recorded: Array = _record(true)
	var replay: Replay = recorded[0]
	var text: String = replay.to_text()
	if not text.contains("\nstart 0 3000 -2000 10000 1000 0 0\n"):
		return "no start line in:\n%s" % text.substr(0, 200)
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return "reload failed: %s" % loaded.error
	var sim: Sim = loaded.run()
	if sim == null or sim.state_hash() != replay.expected_hash:
		return "replayed hash differs from the live run's %d" % replay.expected_hash
	var at_origin: Sim = _record(false)[1]
	if at_origin.state_hash() == replay.expected_hash:
		return "the start pose made no difference to the hash"
	return ""


func test_the_first_tick_starts_at_the_recorded_pose() -> String:
	var replay: Replay = Replay.new(SEED, 1)
	replay.set_start_pose(0, START, FACING)
	var sim: Sim = Replay.from_text(replay.to_text()).run()
	var ship: ShipState = sim.ships[0]
	if ship.position != START or not (-ship.orientation.z).is_equal_approx(FACING):
		return "ship at %s facing %s" % [ship.position, -ship.orientation.z]
	if sim.start_positions[0] != START:
		return "resets to %s" % sim.start_positions[0]
	return ""


func test_without_the_line_the_hash_is_unchanged() -> String:
	var recorded: Array = _record(false)
	var replay: Replay = recorded[0]
	if replay.to_text().contains("\nstart "):
		return "a start line was written without a start pose"
	var plain: Sim = recorded[1]
	var now: Sim = Replay.from_text(replay.to_text()).run()
	var older: Sim = Replay.from_text(replay.to_text().replace(
		"meltdown-replay %d" % ReplayRulesLine.PLAIN_VERSION, "meltdown-replay 13")).run()
	if now.state_hash() != plain.state_hash() or older.state_hash() != plain.state_hash():
		return "hashes %d and %d, a plain sim %d" % [now.state_hash(), older.state_hash(),
			plain.state_hash()]
	if now.ships[0].position == START or now.start_positions[0] != Vector3.ZERO:
		return "a replay without a start line did not start at the origin"
	return ""


func test_a_start_line_in_an_older_version_names_the_line() -> String:
	var text: String = "meltdown-replay 13\nseed 1\nships 1\nstart 0 0 0 0 0 0 -1000\ninputs\n"
	var replay: Replay = Replay.from_text(text)
	if replay.error != "line 4: a start line needs format version 14 or later":
		return "got '%s'" % replay.error
	return ""


func test_bad_start_lines_are_refused() -> String:
	var head: String = "meltdown-replay 14\nseed 1\nships 2\n"
	var cases: Dictionary[String, String] = {
		head + "start 2 0 0 0 0 0 -1000\ninputs\n":
			"line 4: start ship index must be 0 to 1, found 2",
		head + "start 0 0 0 0 0 0 0\ninputs\n": "line 4: start facing must not be zero",
		head + "start 0 0 0 0 1000\ninputs\n":
			"line 4: start needs a ship index, a position and a facing",
		head + "start 0 0 0 x 0 0 -1000\ninputs\n": "line 4: 'x' is not a whole number",
		head + "start 1 0 0 0 0 0 -1000\nstart 1 5 0 0 0 0 -1000\ninputs\n":
			"line 5: 'start 1' appears twice",
		"meltdown-replay 14\nseed 1\nstart 0 0 0 0 0 0 -1000\nships 1\ninputs\n":
			"line 3: a start line must come after the ships line",
		head + "start 0 20000000 0 0 0 0 -1000\ninputs\n":
			"line 4: start position must be within 10000.0 m of the origin",
	}
	var failures: PackedStringArray = PackedStringArray()
	for text: String in cases:
		var replay: Replay = Replay.from_text(text)
		if replay.error != cases[text]:
			failures.append("%s: got '%s'" % [text.c_escape(), replay.error])
	return "\n".join(failures)


func test_each_ship_keeps_its_own_start_and_set_start_pose_checks_its_input() -> String:
	var replay: Replay = Replay.new(SEED, 2)
	if replay.set_start_pose(2, START, FACING) or replay.set_start_pose(-1, START, FACING) \
			or replay.set_start_pose(0, START, Vector3.ZERO):
		return "an index outside the ships or a zero facing was accepted"
	replay.set_start_pose(1, Vector3(0.0004, 1.2345, -7.0), Vector3(0.0, 0.0, 2.0))
	var lines: PackedStringArray = ReplayStartLine.lines(replay)
	if lines != PackedStringArray(["start 1 0 1235 -7000 0 0 1000"]):
		return "lines %s" % str(lines)
	var sim: Sim = Replay.from_text(replay.to_text()).run()
	if sim.ships[0].position != Vector3.ZERO \
			or not sim.ships[1].position.is_equal_approx(Vector3(0.0, 1.235, -7.0)):
		return "ships at %s and %s" % [sim.ships[0].position, sim.ships[1].position]
	return ""


func test_a_diagonal_facing_reads_back_to_the_same_orientation() -> String:
	var replay: Replay = Replay.new(SEED, 1)
	replay.set_start_pose(0, START, Vector3(1.0, 1.0, -1.0))
	var loaded: Replay = Replay.from_text(replay.to_text())
	if loaded.start_facings_mm[0] != Vector3i(577, 577, -577):
		return "facing %s" % loaded.start_facings_mm[0]
	if ReplayStartLine.orientation(loaded, 0) != ReplayStartLine.orientation(replay, 0):
		return "the orientation changed on the way through the text"
	return ""


func test_replay_gd_stays_under_three_hundred_lines() -> String:
	var lines: int = FileAccess.get_file_as_string("res://core/replay.gd").split("\n").size()
	if lines >= 300:
		return "replay.gd has %d lines" % lines
	return ""
