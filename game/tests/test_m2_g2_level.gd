extends RefCounted

## The m2 suite's G2 step (DEV-6, gate G2, #334): a replay of the bot pilot
## clearing the hand-built G2 level, its six boxes and one robot of each of the
## six types, with the ship still alive at the end.
##
## Re-recording after an intended change to the simulation, the bot, the ship
## or robot data, or the level (one command, from the repository root; it
## also re-records the test tunnel replay, see `test_m2_suite.gd`):
##
##     MELTDOWN_RECORD_M2=1 godot --headless --path game -s res://tests/run_tests.gd
##
## It flies the bot in a session built as the main scene builds one for
## `--level=g2`, overwrites `acceptance/replays/bot_g2_level.replay` and prints
## the new hash; paste that hash into `expected_hash` of the step in
## `acceptance/suites/m2.json`. The replay carries no reactor: the format has
## none yet (#310).

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "bot_clears_g2_level"
const REPLAY_PATH: String = "res://acceptance/replays/bot_g2_level.replay"
const LEVEL: String = "g2"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
## Four minutes of flight; the bot needs a little over one.
const TICK_LIMIT: int = 14400
const ROBOT_TYPES: Array[String] = ["needler", "drone", "skimmer", "glider", "hauler", "warden"]
const Main := preload("res://main.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot pilot clearing the G2 level (#334), flown in the m2 suite.
# Re-record from the repository root, then copy the printed hash into m2.json:
#     MELTDOWN_RECORD_M2=1 godot --headless --path game -s res://tests/run_tests.gd
"""


## Hands the session the bot's input. The bot needs the session's own `Sim`,
## which exists only once the session does, so it is set afterwards.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


static func level() -> LevelDef:
	return LevelSwitch.load_level(LevelSwitch.path_for(LEVEL))


## Flies the bot, routing through the level, in a session built like the main
## scene's for `--level=g2` (`main.use_level`) until every robot is destroyed,
## the ship is, or TICK_LIMIT.
static func record() -> LocalSession:
	var g2: LevelDef = level()
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(g2, 0, source,
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, g2)
	while live_robots(session.sim) > 0 and session.sim.ships[0].hull > 0.0 and session.sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	return session


static func live_robots(sim: Sim) -> int:
	var live: int = 0
	for robot: RobotState in sim.robots:
		if robot.is_alive():
			live += 1
	return live


static func step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for found: AcceptanceStep in suite.steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless RECORD_SWITCH is set; see the top of this file.
func test_record_when_asked() -> String:
	if OS.get_environment(RECORD_SWITCH) != "1":
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(REPLAY_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(REPLAY_HEADER + session.replay.to_text())
	file.close()
	print("Meltdown: recorded %s: %d ticks, %d robots left, hull %.2f, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, live_robots(session.sim), session.sim.ships[0].hull,
		session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m2_suite_has_the_g2_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var g2_step: AcceptanceStep = step()
	if g2_step == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_ROBOTS_CLEARED,
		AcceptanceStep.CHECK_SHIP_ALIVE]
	if g2_step.checks != wanted:
		return "%s checks %s" % [STEP_ID, g2_step.checks]
	if g2_step.replay_path != REPLAY_PATH or g2_step.level != LEVEL:
		return "%s flies %s on level '%s'" % [STEP_ID, g2_step.replay_path, g2_step.level]
	return ""


## The replay starts in the level's six boxes with one robot of each type, as
## `LocalSession.for_level` arms them.
func test_replay_starts_in_the_g2_level_with_six_robot_types() -> String:
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	var g2: LevelDef = level()
	if replay.box_mins_mm.size() != g2.union.boxes.size():
		return "the replay has %d boxes, the level %d" % [replay.box_mins_mm.size(), g2.union.boxes.size()]
	var types: Array[String] = []
	for spawn: RobotSpawn in replay.robots:
		types.append(spawn.def.id)
		if spawn.weapon == null:
			return "the %s starts unarmed" % spawn.def.id
	if types != ROBOT_TYPES:
		return "the replay starts with %s" % [types]
	if replay.frames.size() > TICK_LIMIT:
		return "the replay is %d ticks, over the limit of %d" % [replay.frames.size(), TICK_LIMIT]
	return ""


## Run twice from the file: both end on the suite's hash, every robot
## destroyed and the hull above zero.
func test_replay_replays_to_its_hash_twice() -> String:
	var g2_step: AcceptanceStep = step()
	if g2_step == null:
		return "m2 has no step %s" % STEP_ID
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		var actual: int = sim.state_hash()
		if actual != g2_step.expected_hash or actual != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" % [
				attempt + 1, actual, g2_step.expected_hash, replay.expected_hash]
		if live_robots(sim) > 0:
			return "%d robots are still alive at the end of the replay" % live_robots(sim)
		if sim.ships[0].hull <= 0.0:
			return "the ship is destroyed at the end of the replay"
	return ""


## The replay pins one past flight; this checks the bot as it is now still
## wins, so a change to the bot, the robots or the level that stops it is
## caught here.
func test_the_bot_still_clears_the_g2_level() -> String:
	var session: LocalSession = record()
	if live_robots(session.sim) > 0 or session.sim.ships[0].hull <= 0.0:
		return "%d robots alive, hull %.1f after %d ticks" % [
			live_robots(session.sim), session.sim.ships[0].hull, session.sim.tick]
	return ""
