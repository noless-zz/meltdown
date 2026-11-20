extends RefCounted

## An acceptance replay flies from its start line (#401, DEV-6, RUN-3, ARC-1):
## a level that does not start at the origin facing -z, as generated levels
## will not (#382), replays through `ReplayInputSource` to its recorded hash.

const FLIGHT_TICKS: int = 90
const G2_REPLAY: String = "res://acceptance/replays/bot_g2_level.replay"
const G2_HASH: int = 1416572801
## Off the origin and turned 90 degrees (facing +x), with room ahead to fly into.
const TURNED_LEVEL: String = '{"boxes": [{"min": [-10, -10, -10], "max": [100, 20, 30]}],' \
	+ ' "start": {"position": [3, 2, 10], "facing": [1, 0, 0]}, "robots": []}'


## Forward thrust with a slow yaw and pitch, so both where the ship ends and
## how it ends turned depend on the start pose.
class FlySource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		return ShipInput.new(Vector3i(0, 0, -1000), Vector3i(150, 250, 0))


## The turned level flown live, with its end hash written into the replay, read
## back from text as an acceptance step reads its file.
func _recorded_turned_replay() -> Replay:
	var level: LevelDef = LevelDef.parse_json(TURNED_LEVEL)
	if level.error != "":
		push_error(level.error)
		return null
	var session: LocalSession = LocalSession.for_level(level, 401, FlySource.new())
	for i: int in FLIGHT_TICKS:
		session.advance(ShipState.TICK_DT)
	session.replay.expected_hash = session.sim.state_hash()
	return Replay.from_text(session.replay.to_text())


func _fly(source: ReplayInputSource) -> LocalSession:
	var session: LocalSession = source.new_session()
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	return session


func test_turned_off_origin_replay_starts_at_its_start_pose() -> String:
	var replay: Replay = _recorded_turned_replay()
	if replay == null or replay.error != "":
		return "the turned level's replay did not load"
	var session: LocalSession = ReplayInputSource.new(replay).new_session()
	var ship: ShipState = session.sim.ships[0]
	if not ship.position.is_equal_approx(Vector3(3, 2, 10)):
		return "the ship starts at %s" % ship.position
	if not (-ship.orientation.z).is_equal_approx(Vector3.RIGHT):
		return "the ship starts facing %s" % -ship.orientation.z
	if not session.current_ship().position.is_equal_approx(ship.position) \
			or not session.previous_ship().position.is_equal_approx(ship.position):
		return "the view snapshots still hold the origin"
	if ReplayStartLine.lines(session.replay) != ReplayStartLine.lines(replay):
		return "the session's own replay lost the start line: %s" % ReplayStartLine.lines(session.replay)
	return ""


func test_turned_off_origin_replay_ends_on_its_recorded_hash() -> String:
	var replay: Replay = _recorded_turned_replay()
	if replay == null or replay.error != "":
		return "the turned level's replay did not load"
	if replay.frames.size() != FLIGHT_TICKS:
		return "the replay holds %d frames" % replay.frames.size()
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = _fly(source)
	if source.overrun_ticks != 0:
		return "%d ticks ran past the replay" % source.overrun_ticks
	if session.sim.state_hash() != replay.expected_hash:
		return "the replay source flew to %d, the recording to %d" % [session.sim.state_hash(),
			replay.expected_hash]
	return ""


func test_replay_without_start_line_starts_at_the_origin_facing_forward() -> String:
	var replay: Replay = Replay.load_file("res://acceptance/replays/basic_flight.replay")
	if replay.error != "":
		return replay.error
	if not replay.start_positions_mm.is_empty():
		return "basic_flight unexpectedly has a start line"
	var session: LocalSession = ReplayInputSource.new(replay).new_session()
	var ship: ShipState = session.sim.ships[0]
	if not ship.position.is_equal_approx(Vector3.ZERO) or ship.orientation != Basis.IDENTITY:
		return "the ship starts at %s turned %s" % [ship.position, ship.orientation]
	if not session.replay.start_positions_mm.is_empty():
		return "the session gained a start line"
	return ""


func test_g2_replay_still_ends_on_its_pinned_hash() -> String:
	var replay: Replay = Replay.load_file(G2_REPLAY)
	if replay.error != "":
		return replay.error
	if replay.expected_hash != G2_HASH:
		return "the G2 replay file expects %d" % replay.expected_hash
	var session: LocalSession = _fly(ReplayInputSource.new(replay))
	if session.sim.state_hash() != G2_HASH:
		return "the G2 replay flew to %d, expected %d" % [session.sim.state_hash(), G2_HASH]
	return ""
