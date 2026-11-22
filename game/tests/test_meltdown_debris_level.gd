extends RefCounted

## Falling debris read from the level file and carried by replays (#355, RUN-4,
## ARC-1, ARC-4): whole millimetres and ticks, bad entries named, G2's shaft
## placeholder, and a replay's debris line. The fixtures are
## `test_meltdown_debris_sim.gd`'s.

const DebrisSim := preload("res://tests/test_meltdown_debris_sim.gd")
const G2_LEVEL: String = "res://data/levels/g2_level.json"
const LEVEL: String = '{"boxes": [{"min": [-10, -10, -100], "max": [10, 10, 10]}],' \
	+ ' "start": {"position": [0, 0, 0], "facing": [0, 0, -1]}, "robots": []'


func test_the_level_reads_debris_in_whole_millimetres_and_ticks() -> String:
	var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": [{"position": [1.0004, -2, -30],'
		+ ' "radius": 1.5, "after_seconds": 2.5}]}')
	if level.error != "":
		return level.error
	var debris: MeltdownDebris = level.debris
	if debris == null or debris.size() != 1:
		return "debris not read"
	if debris.positions_mm[0] != Vector3i(1000, -2000, -30000) or debris.radii_mm[0] != 1500 \
			or debris.after_ticks[0] != 150:
		return "read as %s" % debris.to_json()
	var without: LevelDef = LevelDef.parse_json(LEVEL + "}")
	if without.error != "" or without.debris != null:
		return "a level without debris got some: %s" % without.error
	return ""


func test_bad_debris_is_rejected_naming_the_index_and_key() -> String:
	var good: String = '{"position": [0, 0, -30], "radius": 1, "after_seconds": 1}'
	var cases: Dictionary = {
		'{}': "debris: must be a list",
		'[3]': "debris 0: must be a JSON object",
		'[%s, {"position": [0, 0, 0], "radius": 1, "after_seconds": 1, "mass": 2}]' % good:
			"debris 1: unknown key \"mass\"",
		'[{"position": [0, 0, 0], "radius": 1}]': "debris 0: missing key \"after_seconds\"",
		'[%s, %s, {"position": [0, 0, 0], "radius": 0, "after_seconds": 1}]' % [good, good]:
			"debris 2: radius must be a number above zero",
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": -1}]':
			"debris 0: after_seconds must be a number of at least zero",
		'[{"position": [0, 0, 0], "radius": 1, "after_seconds": 0}]':
			"debris 0: after_seconds must be at least one tick",
		'[{"position": [0, 0], "radius": 1, "after_seconds": 1}]': "debris 0: position",
	}
	var failures: Array[String] = []
	for text: String in cases:
		var level: LevelDef = LevelDef.parse_json(LEVEL + ', "debris": ' + text + "}")
		if not level.error.begins_with(cases[text]):
			failures.append("%s: got '%s'" % [text, level.error])
		elif level.union.boxes.size() != 0:
			failures.append("%s: a rejected level kept its boxes" % text)
	return "\n".join(failures)


## Shoots the reactor, then flies into debris that fell in the way.
func _replay(with_debris: bool) -> Replay:
	var replay: Replay = Replay.new(355, 1)
	replay.set_box(Vector3i(-10000, -10000, -100000), Vector3i(10000, 10000, 10000))
	replay.reactor = ReactorState.parse_json(DebrisSim.REACTOR_JSON)
	replay.loadout = DebrisSim.pulse_loadout()
	if with_debris:
		replay.debris = DebrisSim.parse_debris('[{"position": [0, 0, -12], "radius": 2, "after_seconds": 0.1}]')
	for i: int in 90:
		replay.add_tick(DebrisSim.fire())
	for i: int in 120:
		replay.add_tick(DebrisSim.forward())
	return replay


func test_a_replay_with_debris_reproduces_its_hash_from_text() -> String:
	var replay: Replay = _replay(true)
	var first: Sim = replay.run()
	if first == null or not first.reactor.destroyed:
		return "the run did not destroy the reactor: %s" % replay.run_error
	var without: Sim = _replay(false).run()
	if without.state_hash() == first.state_hash():
		return "debris made no difference to the run"
	if first.ships[0].position.z < -9.0:
		return "the ship flew through the debris to %s" % first.ships[0].position
	replay.expected_hash = first.state_hash()
	var text: String = replay.to_text()
	var lines: PackedStringArray = text.split("\n")
	if not lines[5].begins_with("reactor {") or not lines[6].begins_with("debris ["):
		return "header %s" % str(lines.slice(0, 7))
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	var again: Sim = read.run()
	if again == null or again.state_hash() != read.expected_hash:
		return "the replay read back from text ends elsewhere"
	if read.to_text() != text:
		return "the debris line does not read back to itself"
	return ""


func test_a_debris_line_in_an_older_format_names_the_line() -> String:
	var line: String = 'debris [{"position": [0, 0, -12], "radius": 2, "after_seconds": 1}]'
	var text: String = "meltdown-replay 14\nseed 1\nships 1\n" + line + "\ninputs\n"
	var old: Replay = Replay.from_text(text)
	if old.error != "line 4: a debris line needs format version 15 or later":
		return "got '%s'" % old.error
	var twice: Replay = Replay.from_text(text.replace("replay 14", "replay 15")
		.replace("inputs", line + "\ninputs"))
	if twice.error != "line 5: 'debris' appears twice":
		return "got '%s'" % twice.error
	var bad: Replay = Replay.from_text(text.replace("replay 14", "replay 15").replace('"radius": 2', '"radius": -2'))
	if bad.error != "line 4: debris 0: radius must be a number above zero":
		return "got '%s'" % bad.error
	return ""


## The placeholder in G2's shaft (box 1) leaves at least 5 m beside it on a
## horizontal axis, so a ship of radius 1 can pass with room to spare.
func test_the_g2_level_has_debris_in_the_shaft_with_room_beside_it() -> String:
	var level: LevelDef = LevelDef.parse_json(FileAccess.get_file_as_string(G2_LEVEL))
	if level.error != "":
		return level.error
	if level.debris == null or level.debris.size() != 1:
		return "G2 has no debris"
	var centre: Vector3 = level.debris.position(0)
	var radius: float = level.debris.radius(0)
	var shaft: BoxBounds = level.union.boxes[1]
	if not shaft.holds(centre, radius):
		return "the debris is not in the shaft"
	var widest: float = 0.0
	for axis: int in [0, 2]:
		widest = maxf(widest, shaft.max_corner[axis] - (centre[axis] + radius))
		widest = maxf(widest, (centre[axis] - radius) - shaft.min_corner[axis])
	if widest < 5.0:
		return "only %s m beside the debris" % widest
	return ""
