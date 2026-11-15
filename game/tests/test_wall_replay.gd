extends RefCounted

## The committed wall-hit replay and the replay format's box line.

const WALL_HIT: String = "res://tests/replays/wall_hit.replay"
const TICKS: int = 300
const SEED: int = 20261115
const BOX_MIN_MM: Vector3i = Vector3i(-4000, -3000, -25000)
const BOX_MAX_MM: Vector3i = Vector3i(4000, 3000, 5000)


## Scripted flight with no randomness: full thrust down the box, an
## afterburner burst, a strafe and yaw into the side wall, then a drift.
## `wall_hit.replay` was generated from this.
func _scripted_input(tick: int) -> ShipInput:
	if tick < 60:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO)
	if tick < 120:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i.ZERO, true)
	if tick < 240:
		var wave: int = (tick * 53) % 301 - 150
		return ShipInput.new(Vector3i(700, wave, -700), Vector3i(0, 300 + wave, 0))
	return ShipInput.new()


func _record() -> Replay:
	var replay: Replay = Replay.new(SEED, 1)
	replay.set_box(BOX_MIN_MM, BOX_MAX_MM)
	var sim: Sim = Sim.new(SEED, 1, replay.bounds())
	for tick: int in TICKS:
		var inputs: Array[ShipInput] = [_scripted_input(tick)]
		replay.add_tick(inputs)
		sim.step(inputs)
	replay.expected_hash = sim.state_hash()
	return replay


func test_wall_hit_replay_keeps_its_hash() -> String:
	var replay: Replay = Replay.load_file(WALL_HIT)
	if replay.error != "":
		return "%s: %s" % [WALL_HIT, replay.error]
	if replay.expected_hash == Replay.NO_HASH or not replay.has_box:
		return "%s needs a hash line and a box line" % WALL_HIT
	if replay.frames.size() != TICKS:
		return "%s has %d ticks, expected %d" % [WALL_HIT, replay.frames.size(), TICKS]
	var sim: Sim = replay.run()
	if sim.state_hash() != replay.expected_hash:
		return ("simulation behaviour changed: %s now ends with hash %d, the file expects %d. "
			+ "If the change is intended, update the hash line and say why in the pull request."
			) % [WALL_HIT, sim.state_hash(), replay.expected_hash]
	if sim.ships[0].hull >= sim.ships[0].max_hull:
		return "%s no longer hits a wall hard enough to take damage" % WALL_HIT
	return ""


func test_wall_hit_replay_matches_the_script() -> String:
	var replay: Replay = Replay.load_file(WALL_HIT)
	if replay.error != "":
		return replay.error
	var scripted: Replay = _record()
	scripted.expected_hash = replay.expected_hash
	if replay.to_text() != scripted.to_text():
		return "%s no longer matches _scripted_input" % WALL_HIT
	return ""


func test_box_line_round_trips() -> String:
	var text: String = _record().to_text()
	var loaded: Replay = Replay.from_text(text)
	if loaded.error != "":
		return loaded.error
	if not loaded.has_box or loaded.box_min_mm != BOX_MIN_MM or loaded.box_max_mm != BOX_MAX_MM:
		return "box changed in the round trip"
	if loaded.to_text() != text:
		return "text changed in the round trip"
	var bounds: BoxBounds = loaded.bounds()
	if bounds.min_corner != Vector3(-4.0, -3.0, -25.0) or bounds.max_corner != Vector3(4.0, 3.0, 5.0):
		return "box corners read as %s and %s" % [bounds.min_corner, bounds.max_corner]
	return ""


func test_replay_without_box_has_no_walls() -> String:
	var replay: Replay = Replay.from_text("meltdown-replay 3\nseed 1\nships 1\ninputs\n0 0 0 0 0 0 0\n")
	if replay.error != "" or replay.has_box or replay.bounds() != null:
		return "a replay without a box line has walls"
	if replay.to_text().contains("box"):
		return "a replay without walls writes a box line"
	return ""


func test_bad_box_lines_are_rejected() -> String:
	var cases: Dictionary[String, String] = {
		"box in version 2": "meltdown-replay 2\nseed 1\nships 1\nbox 0 0 0 1 1 1\ninputs\n",
		"five numbers": "meltdown-replay 3\nseed 1\nships 1\nbox 0 0 0 1 1\ninputs\n",
		"not a number": "meltdown-replay 3\nseed 1\nships 1\nbox 0 0 0 1 x 1\ninputs\n",
		"min above max": "meltdown-replay 3\nseed 1\nships 1\nbox 0 0 2 1 1 1\ninputs\n",
		"twice": "meltdown-replay 3\nseed 1\nships 1\nbox 0 0 0 1 1 1\nbox 0 0 0 1 1 1\ninputs\n",
		"before the format line": "box 0 0 0 1 1 1\nmeltdown-replay 3\nseed 1\nships 1\ninputs\n",
	}
	for name: String in cases:
		if Replay.from_text(cases[name]).error == "":
			return "accepted a bad box line: %s" % name
	return ""
