extends RefCounted

## An acceptance replay flies with its level's debris (#456, RUN-4, DEV-6,
## ARC-2): a G2 flight recorded through `LocalSession.for_level` with the
## reactor destroyed and debris falling, read back from text and flown through
## `ReplayInputSource`, ends on the live session's hash (decision record 0005).

const G2Level := preload("res://tests/test_m2_g2_level.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Clearing G2, shooting the reactor and escaping takes about 4,900 ticks (#375).
const TICK_LIMIT: int = 12000
## G2's one entry falls ten seconds into the meltdown, but the bot is out of
## the mine about 6.5 seconds in. Brought forward to one second, it is down
## (or held by the route guard) for most of the escape, which the replay must
## then fly the same way.
const FALL_TICK: int = 60


## Hands the session the bot's input; the bot needs the session's own `Sim`.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## The live flight and its replay text, recorded once for the whole file.
class Recording extends RefCounted:
	var session: LocalSession = null
	var text: String = ""
	var error: String = ""


static var _recording: Recording = null


## The bot flies G2, with its debris falling at FALL_TICK, in a session built
## like the main scene's until it escapes, dies or reaches TICK_LIMIT.
static func _record() -> Recording:
	if _recording != null:
		return _recording
	_recording = Recording.new()
	var level: LevelDef = G2Level.level()
	if level == null or level.error != "" or level.debris == null or level.debris.size() == 0:
		_recording.error = "the G2 level did not load with debris"
		return _recording
	level.debris.after_ticks[0] = FALL_TICK
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, level)
	var sim: Sim = session.sim
	while sim.tick < TICK_LIMIT and sim.ships[0].hull > 0.0 \
			and sim.outcome() == ExitRule.Outcome.RUNNING:
		session.advance(ShipState.TICK_DT)
	if not sim.reactor.destroyed:
		_recording.error = "the bot never destroyed the reactor (tick %d)" % sim.tick
		return _recording
	if sim.debris.elapsed_ticks < sim.debris.after_ticks[0]:
		_recording.error = "the flight ended %d meltdown ticks in, before the debris fell at %d" % [
			sim.debris.elapsed_ticks, sim.debris.after_ticks[0]]
		return _recording
	if not sim.debris.is_solid(0) and not sim.debris.is_skipped(0):
		_recording.error = "the entry is neither solid nor held after its time"
		return _recording
	session.replay.expected_hash = sim.state_hash()
	_recording.session = session
	_recording.text = session.replay.to_text()
	return _recording


static func _fly(replay: Replay) -> LocalSession:
	var source: ReplayInputSource = ReplayInputSource.new(replay)
	var session: LocalSession = source.new_session()
	while session.sim.tick < source.tick_count():
		session.advance(ShipState.TICK_DT)
	return session


static func _without_debris_line(text: String) -> String:
	var kept: PackedStringArray = []
	for line: String in text.split("\n"):
		if not line.begins_with("debris "):
			kept.append(line)
	return "\n".join(kept)


func test_the_replay_session_gets_its_own_copies_of_the_debris() -> String:
	var recording: Recording = _record()
	if recording.error != "":
		return recording.error
	var replay: Replay = Replay.from_text(recording.text)
	if replay.error != "" or replay.debris == null:
		return "the replay text did not read back with debris: '%s'" % replay.error
	var session: LocalSession = ReplayInputSource.new(replay).new_session()
	var live: MeltdownDebris = session.sim.debris
	var recorded: MeltdownDebris = session.replay.debris
	if live == null or recorded == null:
		return "debris on the sim %s, in the session's replay %s" % [live != null, recorded != null]
	if live == replay.debris or recorded == replay.debris or live == recorded:
		return "the sim, the session's replay and the source replay must each hold their own debris"
	for copy: MeltdownDebris in [live, recorded]:
		if copy.positions_mm != replay.debris.positions_mm or copy.radii_mm != replay.debris.radii_mm \
				or copy.after_ticks != replay.debris.after_ticks or copy.elapsed_ticks != 0:
			return "a copy differs from the replay's debris"
	if session.sim.tick != 0:
		return "the debris was set after tick %d" % session.sim.tick
	return ""


func test_a_g2_replay_with_falling_debris_ends_on_the_live_hash() -> String:
	var recording: Recording = _record()
	if recording.error != "":
		return recording.error
	if not recording.text.contains("\ndebris "):
		return "the recorded replay has no debris line"
	var replay: Replay = Replay.from_text(recording.text)
	if replay.error != "":
		return replay.error
	var session: LocalSession = _fly(replay)
	var live_hash: int = recording.session.sim.state_hash()
	if session.sim.debris == null \
			or session.sim.debris.elapsed_ticks != recording.session.sim.debris.elapsed_ticks:
		return "the replayed debris clock does not match the live one"
	if session.sim.state_hash() != live_hash:
		return "through ReplayInputSource the flight ends on %d, the live session on %d" % [
			session.sim.state_hash(), live_hash]
	if session.sim.state_hash() != replay.expected_hash:
		return "the flight ends on %d, its recorded hash is %d" % [session.sim.state_hash(),
			replay.expected_hash]
	return ""


func test_the_same_replay_without_its_debris_line_misses_the_hash() -> String:
	var recording: Recording = _record()
	if recording.error != "":
		return recording.error
	var replay: Replay = Replay.from_text(_without_debris_line(recording.text))
	if replay.error != "":
		return replay.error
	if replay.debris != null:
		return "the debris line was not removed"
	var session: LocalSession = _fly(replay)
	if session.sim.debris != null or session.replay.debris != null:
		return "a replay without a debris line gave the session debris"
	if session.sim.state_hash() == recording.session.sim.state_hash():
		return "without its debris the flight still ends on the live hash %d" % \
			recording.session.sim.state_hash()
	return ""
