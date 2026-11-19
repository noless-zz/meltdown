extends RefCounted

## The m2 step for salvage pickup (#600, SLV-1): in a session built like the
## main scene's test tunnel, with its part catalogue and salvage rules, the bot
## destroys the first robot, then flies through the part it drops. The step
## pins the final hash and checks the hold names the part.
##
## Re-recording after an intended change (from the repository root; then paste
## the printed hash into `expected_hash` of the step in `acceptance/suites/m2.json`):
##
##     MELTDOWN_RECORD_M2=pickup_in_test_tunnel godot --headless --path game -s res://tests/run_tests.gd

const SUITE_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "pickup_in_test_tunnel"
const REPLAY_PATH: String = "res://acceptance/replays/pickup_test_tunnel.replay"
const RECORD_SWITCH: String = "MELTDOWN_RECORD_M2"
const RecordSwitch := preload("res://tests/record_switch.gd")
## A minute of flight; the recording needs well under half of it.
const TICK_LIMIT: int = 3600
## Ticks flown on, idle, once the part is held, so the step ends settled.
const SETTLE_TICKS: int = 30
const Main := preload("res://main.gd")
## Written above the recording; `Replay` skips lines starting with `#`.
const REPLAY_HEADER: String = """# The bot destroying a test tunnel robot and flying through its part (#600).
# Re-record from the repository root, then copy the printed hash into m2.json:
#     MELTDOWN_RECORD_M2=pickup_in_test_tunnel godot --headless --path game -s res://tests/run_tests.gd
"""


## The bot until a part floats, then straight for the nearest part until the
## hold has one, then nothing. Set `sim` once the session exists.
class SeekSource extends ShipInputSource:
	var sim: Sim = null
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		if sim == null:
			return ShipInput.new()
		var ship: ShipState = sim.ships[0]
		if not ship.hold.is_empty():
			return ShipInput.new()
		if sim.salvage.is_empty():
			return bot.next_input(tick)
		var target: Vector3 = sim.salvage[0].position
		var local: Vector3 = ship.orientation.inverse() * (target - ship.position)
		var thrust: float = 0.6 if local.normalized().z < -0.8 else 0.0
		return ShipInput.from_floats(Vector3(0.0, 0.0, -thrust), BotPilot.turn_towards(local), false)


## A session like the main scene's in the test tunnel, flown by `SeekSource`
## until the hold has held a part for SETTLE_TICKS, the ship is lost, or TICK_LIMIT.
static func record() -> LocalSession:
	var source: SeekSource = SeekSource.new()
	var session: LocalSession = LocalSession.new(0, source, TestTunnel.interior_box(Main.TUNNEL_OFFSET),
		LocalSession.load_tuning(Main.SHIP_TUNING_PATH), LocalSession.load_spawns(Main.ROBOT_SPAWNS_PATH),
		null, LocalSession.load_parts()).use_salvage_rules(SpawnLoader.load_salvage_rules())
	source.sim = session.sim
	source.bot = BotPilot.new(session.sim)
	var held_ticks: int = 0
	while held_ticks < SETTLE_TICKS and session.sim.ships[0].hull > 0.0 and session.sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		if not session.sim.ships[0].hold.is_empty():
			held_ticks += 1
	return session


static func step() -> AcceptanceStep:
	for found: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if found.id == STEP_ID:
			return found
	return null


## Off unless RECORD_SWITCH is `1` or lists STEP_ID; see the top of this file.
func test_record_when_asked() -> String:
	if not RecordSwitch.asks_for(RECORD_SWITCH, STEP_ID):
		return ""
	var session: LocalSession = record()
	session.replay.expected_hash = session.sim.state_hash()
	var file: FileAccess = FileAccess.open(ProjectSettings.globalize_path(REPLAY_PATH), FileAccess.WRITE)
	if file == null:
		return "could not write %s: %s" % [REPLAY_PATH, error_string(FileAccess.get_open_error())]
	file.store_string(REPLAY_HEADER + session.replay.to_text())
	file.close()
	print("Meltdown: recorded %s: %d ticks, hold %s, hash %d; put the hash in %s" % [REPLAY_PATH,
		session.sim.tick, session.sim.ships[0].hold, session.replay.expected_hash, SUITE_PATH])
	return ""


func test_m2_suite_has_the_pickup_step() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	var wanted: Array[String] = [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_PART_HELD,
		AcceptanceStep.CHECK_SHIP_ALIVE]
	if found.checks != wanted or found.replay_path != REPLAY_PATH or found.level != "":
		return "%s checks %s flying %s on level '%s'" % [STEP_ID, found.checks, found.replay_path,
			found.level]
	return ""


## The replay carries the shipped salvage rules and part catalogue, and run
## twice from the file ends on the suite's hash with a part in the hold.
func test_replay_replays_to_its_hash_with_a_part_held() -> String:
	var found: AcceptanceStep = step()
	if found == null:
		return "m2 has no step %s" % STEP_ID
	var shipped: SalvageRules = SpawnLoader.load_salvage_rules()
	for attempt: int in 2:
		var replay: Replay = Replay.load_file(REPLAY_PATH)
		if replay.error != "":
			return replay.error
		if replay.salvage_rules == null or replay.salvage_rules.values_hash() != shipped.values_hash():
			return "the replay does not carry the shipped salvage rules"
		if replay.parts.is_empty():
			return "the replay has no part catalogue"
		var sim: Sim = replay.run()
		if sim == null:
			return replay.run_error
		if sim.state_hash() != found.expected_hash or sim.state_hash() != replay.expected_hash:
			return "run %d flew to %d; suite expects %d, replay %d (re-record: see the top of this file)" \
				% [attempt + 1, sim.state_hash(), found.expected_hash, replay.expected_hash]
		if sim.ships[0].hold.is_empty():
			return "the hold is empty at the end of the replay"
	return ""


## The replay pins one flight; this checks the bot as it is now still
## destroys a robot and picks up its part.
func test_the_bot_still_picks_up_a_part() -> String:
	var session: LocalSession = record()
	if session.sim.ships[0].hold.is_empty():
		return "no part held after %d ticks, hull %.1f" % [session.sim.tick, session.sim.ships[0].hull]
	return ""


## The acceptance check reads the hold, and fails an empty one.
func test_part_held_check_reads_the_hold() -> String:
	var sim: Sim = Sim.new(0, 1)
	var measurements: Dictionary = {}
	if AcceptanceStateChecks.part_held(sim, measurements)[0] != AcceptanceReport.RESULT_FAIL:
		return "an empty hold passed"
	sim.ships[0].hold.append("needle_gun")
	var result: Array = AcceptanceStateChecks.part_held(sim, measurements)
	if result[0] != AcceptanceReport.RESULT_PASS or measurements["part_held"] != "needle_gun":
		return "a held needle gun gave %s, %s" % [result, measurements]
	return ""
