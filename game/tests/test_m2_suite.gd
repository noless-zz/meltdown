extends RefCounted

## The m2 acceptance suite (DEV-6, decision record 0005, #270): its first step
## flies a replay of the bot pilot (#248) clearing the six robots of the test
## tunnel, and must end on the pinned hash with no robot left.
##
## Re-recording after an intended change to the simulation, the ship or robot
## data, or the level (one command, from the repository root; the switch takes
## a comma-separated list of step ids, see `record_switch.gd`, and
## `MELTDOWN_RECORD_M2=1` records every m2 step):
##
##     MELTDOWN_RECORD_M2=bot_clears_test_tunnel godot --headless --path game -s res://tests/run_tests.gd
##
## It flies the bot in the main scene's session, overwrites
## `acceptance/replays/bot_test_tunnel.replay` and prints the new hash; paste
## that hash into `expected_hash` of the step in `acceptance/suites/m2.json`.

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "bot_clears_test_tunnel"
const REPLAY_PATH: String = "res://acceptance/replays/bot_test_tunnel.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
## The issue's limit: two minutes of flight.
const TICK_LIMIT: int = 7200
const Main := preload("res://main.gd")


## Hands the session the bot's input. The bot needs the session's own `Sim`,
## which exists only once the session does, so it is set afterwards.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## Flies the bot in a session built like the main scene's (same seed, walls,
## ship file and level file) until every robot is destroyed or TICK_LIMIT.
static func record() -> LocalSession:
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH))
	source.bot = BotPilot.new(session.sim)
	while _live_robots(session.sim) > 0 and session.sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
	return session


static func _live_robots(sim: Sim) -> int:
	var live: int = 0
	for robot: RobotState in sim.robots:
		if robot.is_alive():
			live += 1
	return live


func _step() -> AcceptanceStep:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	for step: AcceptanceStep in suite.steps:
		if step.id == STEP_ID:
			return step
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var error: Error = session.replay.save(ProjectSettings.globalize_path(REPLAY_PATH))
	if error != OK:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(error)]
	print("Meltdown: recorded %s: %d ticks, %d robots left, hash %d; put the hash in %s" % [
		REPLAY_PATH, session.sim.tick, _live_robots(session.sim), session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m2_suite_has_the_bot_step() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = _step()
	if step == null:
		return "m2 has no step %s" % STEP_ID
	if step.checks != [AcceptanceStep.CHECK_FINAL_HASH]:
		return "%s checks %s" % [STEP_ID, step.checks]
	if step.replay_path != REPLAY_PATH:
		return "%s flies %s" % [STEP_ID, step.replay_path]
	return ""


## The step fails if the simulation drifts from the recording, or if the
## recording no longer ends with the tunnel cleared.
func test_bot_replay_clears_the_tunnel_on_the_suite_hash() -> String:
	var step: AcceptanceStep = _step()
	if step == null:
		return "m2 has no step %s" % STEP_ID
	var replay: Replay = Replay.load_file(REPLAY_PATH)
	if replay.error != "":
		return replay.error
	if replay.frames.size() > TICK_LIMIT:
		return "the replay is %d ticks, over the limit of %d" % [replay.frames.size(), TICK_LIMIT]
	if replay.robots.size() != LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH).size():
		return "the replay starts with %d robots, the level file has %d" % [
			replay.robots.size(), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH).size()]
	var sim: Sim = replay.run()
	if sim == null:
		return replay.run_error
	var actual: int = sim.state_hash()
	if actual != step.expected_hash or actual != replay.expected_hash:
		return "flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" % [
			actual, step.expected_hash, replay.expected_hash]
	if _live_robots(sim) > 0:
		return "%d robots are still alive at the end of the replay" % _live_robots(sim)
	return ""


## The replay pins one past flight; this checks the bot as it is now still
## wins, so a change to the bot or the robots that stops it is caught here.
func test_the_bot_still_clears_the_tunnel() -> String:
	var session: LocalSession = record()
	if _live_robots(session.sim) > 0:
		return "%d robots still alive after %d ticks" % [_live_robots(session.sim), session.sim.tick]
	return ""
