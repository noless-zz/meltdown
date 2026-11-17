extends RefCounted

## The main scene's session writes the level's start pose into its replay
## (#340, ARC-2, GEN-5), so a level that does not start at the origin facing -z
## replays from its saved text to the session's own hash.

const FLIGHT_TICKS: int = 90
const G2_FILE: String = "res://data/levels/g2_level.json"
## G2 flown FLIGHT_TICKS with `FlySource` before #340, when the replay had no
## start line. G2 starts at the origin facing -z, so the line must not move it.
const G2_HASH_BEFORE_START_LINE: int = 1180548112
const G2_START_LINE: String = "start 0 0 0 0 0 0 -1000"
## Starts off the origin facing +x, with room ahead to fly into.
const OFF_ORIGIN_LEVEL: String = '{"boxes": [{"min": [-10, -10, -10], "max": [100, 20, 30]}],' \
	+ ' "start": {"position": [3, 2, 10], "facing": [1, 0, 0]}, "robots": []}'


## Forward thrust with a slow yaw and pitch, so position and turn both depend
## on the start orientation.
class FlySource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(150, 250, 0))


func _fly(level: LevelDef) -> LocalSession:
	var session: LocalSession = LocalSession.for_level(level, 340, FlySource.new())
	for i: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	return session


func _g2() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE))


func _without_start_lines(text: String) -> PackedStringArray:
	var kept: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		if not line.begins_with("start "):
			kept.append(line)
	return kept


func test_off_origin_level_starts_at_its_start_pose() -> String:
	var level: LevelDef = LevelDef.parse_json(OFF_ORIGIN_LEVEL)
	if level.error != "":
		return level.error
	var session: LocalSession = LocalSession.for_level(level, 340, FlySource.new())
	var ship: ShipState = session.sim.ships[0]
	if not ship.position.is_equal_approx(Vector3(3, 2, 10)):
		return "the ship starts at %s" % ship.position
	if not (-ship.orientation.z).is_equal_approx(Vector3.RIGHT):
		return "the ship starts facing %s" % -ship.orientation.z
	if not session.replay.start_positions_mm.has(0):
		return "the replay has no start line"
	if session.replay.start_positions_mm[0] != Vector3i(3000, 2000, 10000) \
			or session.replay.start_facings_mm[0] != Vector3i(1000, 0, 0):
		return "the replay starts at %s facing %s" % [session.replay.start_positions_mm[0],
			session.replay.start_facings_mm[0]]
	return ""


func test_off_origin_flight_replays_from_text_to_the_session_hash() -> String:
	var level: LevelDef = LevelDef.parse_json(OFF_ORIGIN_LEVEL)
	if level.error != "":
		return level.error
	var session: LocalSession = _fly(level)
	if session.sim.tick != FLIGHT_TICKS:
		return "the session ran %d ticks" % session.sim.tick
	var replay: Replay = Replay.from_text(session.replay.to_text())
	if replay.error != "":
		return replay.error
	var sim: Sim = replay.run()
	if sim == null:
		return replay.run_error
	if sim.state_hash() != session.sim.state_hash():
		return "the replay flew to %d, the session to %d" % [sim.state_hash(), session.sim.state_hash()]
	if not sim.ships[0].position.is_equal_approx(session.sim.ships[0].position):
		return "the replay ended at %s, the session at %s" % [sim.ships[0].position,
			session.sim.ships[0].position]
	return ""


## The start line is the only change to G2's replay: without it the text
## replays exactly as before, and the hash is today's.
func test_g2_replay_gains_only_the_start_line() -> String:
	var session: LocalSession = _fly(_g2())
	var text: String = session.replay.to_text()
	var starts: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		if line.begins_with("start "):
			starts.append(line)
	if session.sim.state_hash() != G2_HASH_BEFORE_START_LINE:
		return "G2 flew to %d, before the start line %d" % [session.sim.state_hash(),
			G2_HASH_BEFORE_START_LINE]
	if starts != PackedStringArray([G2_START_LINE]):
		return "G2's replay has start lines %s, expected [%s]" % [starts, G2_START_LINE]
	var stripped: String = "\n".join(_without_start_lines(text))
	var replay: Replay = Replay.from_text(stripped)
	if replay.error != "":
		return replay.error
	if replay.to_text() != stripped:
		return "G2's replay text changed beyond the start line"
	var sim: Sim = replay.run()
	if sim == null:
		return replay.run_error
	if sim.state_hash() != G2_HASH_BEFORE_START_LINE:
		return "without its start line G2 replays to %d" % sim.state_hash()
	return ""
