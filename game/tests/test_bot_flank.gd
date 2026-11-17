extends RefCounted

## The bot pilot finds a firing line round an intact reactor (#375, CMB-3,
## RUN-2, DEV-6). Since #345 a reactor stops shots both ways, so the G2 warden
## behind it on the tunnel's axis was out of reach; the bot now flies to a
## point off that line and fires from there. Flights with a reactor must still
## replay to their hash (ARC-1, ARC-2).

const G2Level := preload("res://tests/test_m2_g2_level.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
const TICK_LIMIT: int = 14400
## One box with the ship at the origin facing -z, a drone 30 m ahead and a
## reactor halfway, so every straight shot between them meets the reactor.
const BOX_LEVEL: String = """{
	"boxes": [{"min": [-12.0, -12.0, -40.0], "max": [12.0, 12.0, 6.0]}],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [{"id": "drone", "position": [0.0, 0.0, -30.0], "facing": [0.0, 0.0, 1.0]}],
	"reactor": {"position": [0.0, 0.0, -15.0], "radius": 2.5, "hull": 400.0, "meltdown_seconds": 90.0}
}"""
const BOX_TICK_LIMIT: int = 3600


## Feeds the session the bot's input; the bot needs the session's own `Sim`.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## A session of `level` with its reactor armed on the sim and in the replay,
## flown by the bot until every robot is destroyed, the ship is, or `limit`.
static func fly(level: LevelDef, limit: int) -> LocalSession:
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.set_reactor(level.reactor.fresh_copy())
	session.replay.reactor = level.reactor.fresh_copy()
	source.bot = BotPilot.new(session.sim, 0, level)
	while G2Level.live_robots(session.sim) > 0 and session.sim.ships[0].hull > 0.0 \
			and session.sim.tick < limit:
		session.advance(ShipState.TICK_DT)
	return session


static func box_level() -> LevelDef:
	return LevelDef.parse_json(BOX_LEVEL)


func test_the_bot_clears_g2_with_the_reactor_armed() -> String:
	var g2: LevelDef = G2Level.level()
	if g2.error != "" or g2.reactor == null:
		return "the G2 level has no reactor: %s" % g2.error
	var session: LocalSession = fly(g2, TICK_LIMIT)
	var sim: Sim = session.sim
	if G2Level.live_robots(sim) > 0 or sim.ships[0].hull <= 0.0:
		return "%d robots alive, hull %.1f after %d ticks" % [
			G2Level.live_robots(sim), sim.ships[0].hull, sim.tick]
	if sim.reactor.destroyed:
		return "the reactor was destroyed on the way"
	return ""


func test_a_drone_behind_the_reactor_in_one_box_is_destroyed() -> String:
	var level: LevelDef = box_level()
	if level.error != "":
		return level.error
	var session: LocalSession = fly(level, BOX_TICK_LIMIT)
	var sim: Sim = session.sim
	if G2Level.live_robots(sim) > 0:
		return "the drone is still alive after %d ticks" % sim.tick
	if sim.ships[0].hull <= 0.0:
		return "the ship was destroyed"
	# The bot fires only on a clear line, so no shot of its own met the reactor.
	if sim.reactor.hull != sim.reactor.max_hull:
		return "the reactor took fire: hull %s" % sim.reactor.hull
	return ""


## At the start the only thing between the ship and the drone is the reactor,
## so the flank is what clears the box, not a line that was open anyway.
func test_in_the_box_the_reactor_blocks_the_first_line() -> String:
	var level: LevelDef = box_level()
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.set_reactor(level.reactor.fresh_copy())
	var bot: BotPilot = BotPilot.new(session.sim, 0, level)
	var ship: ShipState = session.sim.ships[0]
	var drone: RobotState = session.sim.robots[0]
	if bot.shot_reaches(ship, drone.position):
		return "a shot reaches the drone through the reactor"
	var flank: BotFlank = BotFlank.new(session.sim, level.union, LevelRoute.new(level))
	if not flank.reactor_blocks(ship.position, drone.position, 120.0):
		return "the reactor is not what blocks the line"
	return ""


## The chosen point is inside the walls with room, clear of the reactor, and
## the same twice over.
func test_the_firing_point_is_clear_and_deterministic() -> String:
	var level: LevelDef = box_level()
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.set_reactor(level.reactor.fresh_copy())
	var ship: ShipState = session.sim.ships[0]
	var target: Vector3 = session.sim.robots[0].position
	var points: Array[Vector3] = []
	for attempt: int in 2:
		var flank: BotFlank = BotFlank.new(session.sim, level.union, LevelRoute.new(level))
		points.append(flank.firing_point(ship, target, 120.0, 180.0))
	if points[0] == Vector3.INF:
		return "no firing point found"
	if points[0] != points[1]:
		return "two choices differ: %s and %s" % [points[0], points[1]]
	if not level.union.holds(points[0], ship.radius):
		return "the point %s is not held by the walls" % points[0]
	if session.sim.reactor.segment_entry(points[0], target) >= 0.0:
		return "the line from %s still meets the reactor" % points[0]
	return ""


## Without a reactor, or with a destroyed one, there is nothing to flank.
func test_no_flank_without_an_intact_reactor() -> String:
	var level: LevelDef = box_level()
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	var ship: ShipState = session.sim.ships[0]
	var drone: RobotState = session.sim.robots[0]
	var flank: BotFlank = BotFlank.new(session.sim, level.union, LevelRoute.new(level))
	if flank.point_for(ship, drone, false) != Vector3.INF:
		return "a flank was chosen with no reactor"
	var reactor: ReactorState = level.reactor.fresh_copy()
	session.sim.set_reactor(reactor)
	reactor.apply_damage(reactor.max_hull)
	if flank.point_for(ship, drone, false) != Vector3.INF:
		return "a flank was chosen round a destroyed reactor"
	return ""


## The G2 flight with the reactor, written to text and read back, replays to
## the same hash.
func test_the_flank_flight_replays_to_its_hash_from_text() -> String:
	var session: LocalSession = fly(G2Level.level(), TICK_LIMIT)
	var expected: int = session.sim.state_hash()
	var read: Replay = Replay.from_text(session.replay.to_text())
	if read.error != "":
		return read.error
	if read.reactor == null:
		return "the reactor did not survive the text"
	var sim: Sim = read.run()
	if sim == null:
		return read.run_error
	if sim.state_hash() != expected:
		return "read back, the flight ends on %d, not %d" % [sim.state_hash(), expected]
	return ""
