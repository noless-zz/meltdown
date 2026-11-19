extends RefCounted

## `LocalSession.for_level` carries the level's reactor into the simulation and
## its replay (#332, RUN-2, ARC-2, DEV-6), so the main scene's G2 flies with it.

const G2Level := preload("res://tests/test_m2_g2_level.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## A part directory with no files: the catalogue is empty, so the pinned hash
## below cannot depend on how a machine lists a directory (#381).
const NO_PARTS_DIR: String = "res://tests/no_parts_here"
## One box, one drone, no reactor.
const PLAIN_LEVEL: String = """{
	"boxes": [{"min": [-12.0, -12.0, -40.0], "max": [12.0, 12.0, 6.0]}],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [{"id": "drone", "position": [0.0, 0.0, -30.0], "facing": [0.0, 0.0, 1.0]}]
}"""
const PLAIN_TICKS: int = 120
## The hash of PLAIN_LEVEL after PLAIN_TICKS of ForwardSource, taken on `main`
## before #332; a level without a reactor must keep it. Re-measured after #612
## gave the drone its own bursting weapon.
const PLAIN_HASH: int = 1663502524


## Full thrust ahead with a slow yaw, so the ship moves and turns.
class ForwardSource extends ShipInputSource:
	func next_input(_tick: int) -> ShipInput:
		var input: ShipInput = ShipInput.new()
		input.thrust_q = Vector3i(0, 0, -1000)
		input.turn_q = Vector3i(0, 200, 0)
		return input


func test_the_g2_session_arms_the_level_reactor() -> String:
	var g2: LevelDef = G2Level.level()
	if g2.error != "" or g2.reactor == null:
		return "the G2 level has no reactor: %s" % g2.error
	var session: LocalSession = LocalSession.for_level(g2, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	var live: ReactorState = session.sim.reactor
	var recorded: ReactorState = session.replay.reactor
	if live == null or recorded == null:
		return "reactor on the sim %s, in the replay %s" % [live != null, recorded != null]
	if live == g2.reactor or recorded == g2.reactor or live == recorded:
		return "the sim, the replay and the level must each hold their own reactor"
	if live.position_mm != g2.reactor.position_mm or recorded.position_mm != g2.reactor.position_mm:
		return "the reactor sits at %s and %s, the level puts it at %s" % [
			live.position_mm, recorded.position_mm, g2.reactor.position_mm]
	if live.hull != live.max_hull or live.max_hull != g2.reactor.max_hull or live.destroyed:
		return "the reactor starts with hull %s of %s" % [live.hull, live.max_hull]
	if session.sim.tick != 0:
		return "the reactor was set after tick %d" % session.sim.tick
	return ""


## Damage in the live run must not reach the copy a replay starts from.
func test_damage_to_the_live_reactor_stays_out_of_the_replay() -> String:
	var g2: LevelDef = G2Level.level()
	var session: LocalSession = LocalSession.for_level(g2, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.reactor.apply_damage(50.0)
	if session.replay.reactor.hull != session.replay.reactor.max_hull:
		return "the replay's reactor took the live damage: hull %s" % session.replay.reactor.hull
	if g2.reactor.hull != g2.reactor.max_hull:
		return "the level's reactor took the live damage: hull %s" % g2.reactor.hull
	return ""


## The bot flies a while in the G2 session; the replay, written to text and
## read back, ends on the session's hash.
func test_a_g2_flight_replays_from_text_to_the_session_hash() -> String:
	var g2: LevelDef = G2Level.level()
	var source: G2Level.BotSource = G2Level.BotSource.new()
	var session: LocalSession = LocalSession.for_level(g2, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, g2)
	for tick: int in 900:
		session.advance(ShipState.TICK_DT)
	var text: String = session.replay.to_text()
	if not text.contains("\nreactor "):
		return "the replay text has no reactor line"
	var read: Replay = Replay.from_text(text)
	if read.error != "":
		return read.error
	var sim: Sim = read.run()
	if sim == null:
		return read.run_error
	if sim.state_hash() != session.sim.state_hash():
		return "read back, the flight ends on %d, the session on %d" % [
			sim.state_hash(), session.sim.state_hash()]
	return ""


## A level without a reactor flies as before: no reactor, no reactor line, and
## the hash it had before #332.
func test_a_level_without_a_reactor_keeps_its_session_hash() -> String:
	var plain: LevelDef = LevelDef.parse_json(PLAIN_LEVEL)
	if plain.error != "" or plain.reactor != null:
		return "the plain level: error '%s', reactor %s" % [plain.error, plain.reactor != null]
	var session: LocalSession = LocalSession.for_level(plain, 0, ForwardSource.new(), null,
		LocalSession.ROBOT_DIR, NO_PARTS_DIR)
	if session.sim.reactor != null or session.replay.reactor != null:
		return "a reactor appeared in a level without one"
	for tick: int in PLAIN_TICKS:
		session.advance(ShipState.TICK_DT)
	if session.replay.to_text().contains("\nreactor "):
		return "the replay text has a reactor line"
	if session.sim.state_hash() != PLAIN_HASH:
		return "the plain level ends on %d, before #332 it ended on %d" % [
			session.sim.state_hash(), PLAIN_HASH]
	return ""
