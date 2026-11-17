extends RefCounted

## The bot pilot destroys the reactor and escapes through the entrance (#360,
## RUN-2, RUN-3, GEN-3, DEV-6): gate G3 needs a bot that escapes. The G2
## session is built like the main scene's, with the level's reactor set on
## the sim and the replay here, as #332 may not have merged. The flight must
## replay to its hash (ARC-1, ARC-2).

const G2Level := preload("res://tests/test_m2_g2_level.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Clearing G2 takes about 4,000 ticks (#375) and the countdown at most
## 120 seconds, so this leaves room for both.
const TICK_LIMIT: int = 18000
## A countdown far too short to fly from the reactor back to the entrance.
const SHORT_MELTDOWN_SECONDS: float = 3.0


## Feeds the session the bot's input; the bot needs the session's own `Sim`.
class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## The flight and the ticks it passed its marks on; -1 for a mark not reached.
class Flight extends RefCounted:
	var session: LocalSession = null
	var robots_cleared_tick: int = -1
	var reactor_tick: int = -1
	var escape_tick: int = -1
	## Countdown ticks left when the ship escaped.
	var margin_ticks: int = -1
	## Countdown ticks the meltdown started with.
	var meltdown_ticks: int = -1


## G2 with `reactor` armed on the sim and in the replay, flown by the bot
## until the run ends, the ship is destroyed, or TICK_LIMIT.
static func fly(reactor: ReactorState) -> Flight:
	var level: LevelDef = G2Level.level()
	var source: BotSource = BotSource.new()
	var flight: Flight = Flight.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.set_reactor(reactor.fresh_copy())
	session.replay.reactor = reactor.fresh_copy()
	source.bot = BotPilot.new(session.sim, 0, level)
	flight.session = session
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		if flight.robots_cleared_tick < 0 and G2Level.live_robots(sim) == 0:
			flight.robots_cleared_tick = sim.tick
		if flight.reactor_tick < 0 and sim.reactor.destroyed:
			flight.reactor_tick = sim.tick
			flight.meltdown_ticks = sim.reactor.meltdown_ticks_left
		if flight.escape_tick < 0 and sim.ships[0].escaped:
			flight.escape_tick = sim.tick
			flight.margin_ticks = sim.reactor.meltdown_ticks_left
	return flight


static func g2_reactor() -> ReactorState:
	return G2Level.level().reactor


## A copy of the G2 reactor whose countdown is SHORT_MELTDOWN_SECONDS.
static func short_reactor() -> ReactorState:
	var reactor: ReactorState = g2_reactor().fresh_copy()
	reactor.scales_with_path = false
	reactor.meltdown_seconds = SHORT_MELTDOWN_SECONDS
	return reactor


static func describe(flight: Flight) -> String:
	var sim: Sim = flight.session.sim
	return "robots cleared %d, reactor %d, escape %d, margin %d of %d, hull %.2f, tick %d" % [
		flight.robots_cleared_tick, flight.reactor_tick, flight.escape_tick,
		flight.margin_ticks, flight.meltdown_ticks, sim.ships[0].hull, sim.tick]


func test_the_bot_clears_g2_destroys_the_reactor_and_escapes() -> String:
	if g2_reactor() == null:
		return "the G2 level has no reactor"
	var flight: Flight = fly(g2_reactor())
	var sim: Sim = flight.session.sim
	print("  G2 escape: %s" % describe(flight))
	if flight.robots_cleared_tick < 0:
		return "robots still alive: %s" % describe(flight)
	if not sim.reactor.destroyed:
		return "the reactor is intact: %s" % describe(flight)
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %d, not ESCAPED: %s" % [sim.outcome(), describe(flight)]
	if flight.margin_ticks <= 0:
		return "escaped with no countdown left: %s" % describe(flight)
	# The reactor only goes once the fight is over.
	if flight.reactor_tick < flight.robots_cleared_tick:
		return "the reactor went before the robots: %s" % describe(flight)
	return ""


func test_a_countdown_too_short_to_fly_back_is_lost() -> String:
	var flight: Flight = fly(short_reactor())
	var sim: Sim = flight.session.sim
	if not sim.reactor.destroyed:
		return "the reactor is intact: %s" % describe(flight)
	if sim.outcome() != ExitRule.Outcome.LOST:
		return "outcome %d, not LOST: %s" % [sim.outcome(), describe(flight)]
	return ""


func test_the_escape_replays_to_its_hash_from_text() -> String:
	var flight: Flight = fly(g2_reactor())
	var session: LocalSession = flight.session
	var expected: int = session.sim.state_hash()
	var read: Replay = Replay.from_text(session.replay.to_text())
	if read.error != "":
		return read.error
	if read.reactor == null:
		return "the reactor did not survive the text"
	var sim: Sim = read.run()
	if sim == null:
		return read.run_error
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "read back, the outcome is %d, not ESCAPED" % sim.outcome()
	if sim.state_hash() != expected:
		return "read back, the flight ends on %d, not %d" % [sim.state_hash(), expected]
	return ""


## Without a reactor the escape steps never take over: with every robot gone
## and no goal the bot holds still, as before.
func test_without_a_reactor_the_bot_does_not_escape() -> String:
	var level: LevelDef = G2Level.level()
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	for robot: RobotState in session.sim.robots:
		robot.hull = 0.0
	var input: ShipInput = BotPilot.new(session.sim, 0, level).next_input(0)
	if input.thrust() != Vector3.ZERO or input.afterburner or input.fire_primary:
		return "the bot flies with no reactor and no robots"
	return ""


## With every robot gone and the reactor intact, the bot heads for the
## reactor and holds fire until a shot gets there.
func test_with_the_robots_gone_the_bot_turns_to_the_reactor() -> String:
	var level: LevelDef = G2Level.level()
	var session: LocalSession = LocalSession.for_level(level, 0, null,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	session.sim.set_reactor(level.reactor.fresh_copy())
	for robot: RobotState in session.sim.robots:
		robot.hull = 0.0
	var bot: BotPilot = BotPilot.new(session.sim, 0, level)
	var input: ShipInput = bot.next_input(0)
	if input.thrust() == Vector3.ZERO:
		return "the bot does not move towards the reactor"
	if input.fire_primary:
		return "the bot fires at the reactor through rock"
	var escape: BotEscape = BotEscape.new(session.sim, 0, level.union, LevelRoute.new(level))
	if escape.reactor_shot_reaches(session.sim.ships[0]):
		return "from the start, a shot reaches the reactor through rock"
	return ""
