extends RefCounted

## The one place that says how the m3 suite's G2 escape step gets its level
## (#578, ARC-2, DEV-6, decision record 0005): what the recorder writes and
## what the suite step flies.
##
## The recorder flies the bot in a session that `LocalSession.for_level`
## builds from `data/levels/g2_level.json` (`test_bot_escape.gd`, `fly`), and
## writes that session's replay. The suite step, a `level` step with no seed,
## flies the replay's own copy of the level through
## `ReplayInputSource.new_session` (`acceptance_runner.gd`, `_start_step`).
## So the two agree only while the stored replay was written from the current
## level file. The G2 escape replay was recorded (#405) before
## `for_level` carried a level's debris into the session and its replay
## (#449), so it flew G2 without its debris while a fresh recording flew it
## with them.
##
## Both the recorder (`test_m3_suite.gd`) and the agreement test
## (`test_m3_g2_setup.gd`) take the recorder's flight from `flight()`, so the
## test checks the very setup the recorder writes.

const BotEscapeTest := preload("res://tests/test_bot_escape.gd")
const REPLAY_PATH: String = "res://acceptance/replays/bot_g2_escape.replay"
const STEP_ID: String = "bot_g2_escape"

## One bot flight per test run; the escape takes about 4,000 ticks.
static var _flight: BotEscapeTest.Flight = null


## The recorder's flight: the bot through G2 with the level's own reactor.
static func flight() -> BotEscapeTest.Flight:
	if _flight == null:
		_flight = BotEscapeTest.fly(BotEscapeTest.g2_reactor())
	return _flight


## The replay the recorder would write now. Its level lines are copies the run
## never moves, so they read as they did before the first tick.
static func recorder_replay() -> Replay:
	return flight().session.replay


## The replay the suite step flies, set up as the runner sets up a step with a
## level and no seed. When the file cannot be read, the loaded replay with
## its `error` set.
static func step_replay(path: String = REPLAY_PATH) -> Replay:
	var replay: Replay = Replay.load_file(path)
	if replay.error != "":
		return replay
	return ReplayInputSource.new(replay).new_session().replay


## The debris list a replay carries, as its JSON, or "" for none.
static func debris_text(replay: Replay) -> String:
	if replay.debris == null or replay.debris.size() == 0:
		return ""
	return replay.debris.to_json()


## Where the two setups differ, or "" when they give the same level.
static func differences(recorder: Replay, step: Replay) -> String:
	var found: PackedStringArray = PackedStringArray()
	var recorder_hash: int = level_hash(recorder)
	var step_hash: int = level_hash(step)
	if recorder_hash != step_hash:
		found.append("level hash: recorder %d, step %d" % [recorder_hash, step_hash])
	if debris_text(recorder) != debris_text(step):
		found.append("debris: recorder '%s', step '%s'" % [debris_text(recorder), debris_text(step)])
	return "; ".join(found)


## `AcceptanceStepLevel.level_hash` without the expected-hash line, which the
## recorder sets only after its flight and which is not part of the level.
static func level_hash(replay: Replay) -> int:
	var expected: int = replay.expected_hash
	replay.expected_hash = Replay.NO_HASH
	var hashed: int = AcceptanceStepLevel.level_hash(replay)
	replay.expected_hash = expected
	return hashed
