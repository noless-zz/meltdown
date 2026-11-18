extends RefCounted

## The bot's escape routes round fallen meltdown debris (#443, RUN-4, RUN-3,
## DEV-6 gate G3): an opening that solid debris blocks, by the test `KnownRoute`
## uses, is closed to the bot's route, held entries leave it open, and nothing
## changes before the reactor dies. `bot_escape_sweep.gd --debris` flies the
## generated levels with their debris and still escapes at G3's rate.

const Sweep := preload("res://tests/bot_escape_sweep.gd")
const SeedSweepRef := preload("res://tests/seed_sweep.gd")
const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Start room (box 0), a short corridor straight to the reactor room (box 1, then
## box 2) and a longer way round on the +x side (boxes 3 and 4). Fewest boxes
## is the short way, so the bot flies in through the corridor and shoots the
## reactor (off the corridor's line, so not from the start) from the corridor's
## far end. Half a second into the meltdown a rock falls into the corridor's
## near opening, about 45 m ahead of the bot; the long way stays open, so the route
## guard lets it fall.
const TWO_ROUTE_LEVEL: String = """{
	"boxes": [
		{"min": [-10.0, -6.0, -10.0], "max": [10.0, 6.0, 10.0]},
		{"min": [-4.0, -4.0, -60.0], "max": [4.0, 4.0, -6.0]},
		{"min": [-10.0, -6.0, -120.0], "max": [30.0, 6.0, -56.0]},
		{"min": [6.0, -6.0, -10.0], "max": [30.0, 6.0, 10.0]},
		{"min": [22.0, -6.0, -60.0], "max": [30.0, 6.0, -6.0]}
	],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [20, 0, -100], "radius": 2, "hull": 40, "meltdown_seconds": 60},
	"debris": [{"position": [0.0, 0.0, -8.0], "radius": 4.0, "after_seconds": 0.5}]
}"""
const ROCK: int = 0
## The rock blocks the opening between the start room and the corridor.
const START_ROOM: int = 0
const CORRIDOR: int = 1
const REACTOR_ROOM: int = 2
## The long way's far side: past this x the ship is in box 4.
const LONG_WAY_X: float = 22.0
const TICK_LIMIT: int = 12000
const SEEDS: int = 20
const FIRST_SEED: int = 1
## As in `test_bot_escape_sweep.gd`: about ten seconds on a desktop.
const TIME_LIMIT_MS: int = 60000


class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## How the hand-built flight went.
class Flight extends RefCounted:
	var sim: Sim = null
	## Closest the ship's surface came to the rock's once it was solid, metres.
	var closest: float = INF
	var took_long_way: bool = false


static func _level() -> LevelDef:
	return LevelDef.parse_json(TWO_ROUTE_LEVEL)


static func _fly(level: LevelDef) -> Flight:
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, level)
	var flight: Flight = Flight.new()
	flight.sim = session.sim
	var sim: Sim = session.sim
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		var ship: ShipState = sim.ships[0]
		if sim.debris != null and sim.debris.is_solid(ROCK):
			var gap: float = ship.position.distance_to(sim.debris.position(ROCK)) \
				- ship.radius - sim.debris.radius(ROCK)
			flight.closest = minf(flight.closest, gap)
		if ship.position.x > LONG_WAY_X:
			flight.took_long_way = true
	return flight


func test_the_level_parses_with_its_rock() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return level.error
	if level.debris == null or level.debris.size() != 1:
		return "expected one debris entry"
	return ""


func test_the_bot_escapes_the_long_way_without_touching_the_rock() -> String:
	var flight: Flight = _fly(_level())
	var sim: Sim = flight.sim
	if not sim.reactor.destroyed:
		return "the reactor was not destroyed by tick %d" % sim.tick
	if not sim.debris.is_solid(ROCK):
		return "the rock never fell (held: %s); the test needs it solid" % sim.debris.is_skipped(ROCK)
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %s at tick %d, hull %.2f" % [ExitRule.Outcome.keys()[sim.outcome()],
			sim.tick, sim.ships[0].hull]
	if flight.closest <= 0.0:
		return "the ship touched the rock (closest %.3f m)" % flight.closest
	if not flight.took_long_way:
		return "the ship did not fly the long way round"
	return ""


func test_without_the_rock_the_bot_escapes_the_short_way() -> String:
	var level: LevelDef = _level()
	level.debris = null
	var flight: Flight = _fly(level)
	if flight.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %s" % ExitRule.Outcome.keys()[flight.sim.outcome()]
	if flight.took_long_way:
		return "with no rock the bot still flew the long way"
	return ""


func test_a_solid_rock_closes_the_opening_it_blocks() -> String:
	var level: LevelDef = _level()
	var route: LevelRoute = LevelRoute.new(level)
	var debris: MeltdownDebris = level.debris.fresh_copy()
	route.close_blocked(debris, 1.0)
	if route.is_closed(START_ROOM, CORRIDOR):
		return "the opening closed before the meltdown"
	var from: Vector3 = Vector3(20.0, 0.0, -100.0)
	var short_way: Array[int] = route.chain(from, Vector3.ZERO, 1.0)
	if short_way != [REACTOR_ROOM, CORRIDOR, 0]:
		return "before the rock falls the chain is %s" % [short_way]
	debris.elapsed_ticks = debris.after_ticks[ROCK]
	route.close_blocked(debris, 1.0)
	if not route.is_closed(START_ROOM, CORRIDOR) or not route.is_closed(CORRIDOR, START_ROOM):
		return "the solid rock left the opening open"
	if route.is_closed(CORRIDOR, REACTOR_ROOM):
		return "the far opening closed too"
	var long_way: Array[int] = route.chain(from, Vector3.ZERO, 1.0)
	if long_way != [REACTOR_ROOM, 4, 3, 0]:
		return "with the rock down the chain is %s" % [long_way]
	return ""


func test_a_held_rock_leaves_the_opening_open() -> String:
	var level: LevelDef = _level()
	var route: LevelRoute = LevelRoute.new(level)
	var debris: MeltdownDebris = level.debris.fresh_copy()
	debris.elapsed_ticks = debris.after_ticks[ROCK]
	debris.skipped[ROCK] = true
	route.close_blocked(debris, 1.0)
	if route.is_closed(START_ROOM, CORRIDOR):
		return "a held entry closed the opening"
	var chain: Array[int] = route.chain(Vector3(20.0, 0.0, -100.0), Vector3.ZERO, 1.0)
	if chain != [REACTOR_ROOM, CORRIDOR, 0]:
		return "with the rock held the chain is %s" % [chain]
	return ""


func test_a_straight_line_through_the_rock_is_not_flown() -> String:
	var level: LevelDef = _level()
	var route: LevelRoute = LevelRoute.new(level)
	var debris: MeltdownDebris = level.debris.fresh_copy()
	var from: Vector3 = Vector3(0.0, 0.0, -20.0)
	var to: Vector3 = Vector3(0.0, 0.0, 5.0)
	if route.waypoints(from, to, 1.0) != [to]:
		return "the straight leg was not flown with no rock"
	debris.elapsed_ticks = debris.after_ticks[ROCK]
	route.close_blocked(debris, 1.0)
	if route.waypoints(from, to, 1.0) == [to]:
		return "the straight leg through the rock was still flown"
	return ""


func test_the_debris_sweep_escapes_at_the_g3_rate_the_same_twice() -> String:
	var first: Dictionary = Sweep.run(FIRST_SEED, SEEDS, false, true)
	var line: String = Sweep.summary(first)
	print("  %s" % line)
	print("  %s" % Sweep.details(first))
	if first["ms"] > TIME_LIMIT_MS:
		return "took %d ms, over %d" % [first["ms"], TIME_LIMIT_MS]
	if not line.ends_with(',"debris":true}'):
		return "the summary does not say debris: %s" % line
	if first["cleared"] < 1:
		return "no level cleared: %s" % ", ".join(first["failures"])
	if first["rate"] < Sweep.REQUIRED_RATE:
		return "rate %.4f under %.2f: %s" % [first["rate"], Sweep.REQUIRED_RATE,
				", ".join(first["failures"])]
	var second: Dictionary = Sweep.run(FIRST_SEED, SEEDS, false, true)
	if Sweep.summary(second) != line:
		return "\"%s\" then \"%s\"" % [line, Sweep.summary(second)]
	if first["failures"] != second["failures"]:
		return "failures differ: %s then %s" % [first["failures"], second["failures"]]
	return ""


func test_the_debris_summary_has_the_agreed_shape() -> String:
	var result: Dictionary = {"seeds": 7, "cleared": 6, "escaped": 5, "looped": 2,
			"robots": false, "debris": true, "robots_destroyed": 0, "rate": 5.0 / 6.0}
	var expected: String = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"looped":2,"rate":0.8333,"debris":true}'
	if Sweep.summary(result) != expected:
		return "summary \"%s\", expected \"%s\"" % [Sweep.summary(result), expected]
	result["robots"] = true
	result["robots_destroyed"] = 3
	result["lost_before_reactor"] = 2
	result["timed_out"] = 0
	var lost: Array[Dictionary] = [{"seed": 1, "tick": 420, "awake": 3},
			{"seed": 4, "tick": 2400, "awake": 6}]
	result["lost"] = lost
	# The nightly sweep's shape, which tools/bot_escape_rate.sh parses (#495, #534).
	expected = 'MELTDOWN_BOT_ESCAPE {"seeds":7,"cleared":6,"escaped":5,"looped":2,"rate":0.8333,"robots_destroyed":3,"lost_before_reactor":2,"timed_out":0,"robots":true,"lost_under_10_s":1,"lost_10_to_60_s":1,"lost_over_60_s":0,"lost_awake_median":4.5,"debris":true}'
	if Sweep.summary(result) != expected:
		return "summary \"%s\", expected \"%s\"" % [Sweep.summary(result), expected]
	if JSON.parse_string(expected.trim_prefix(Sweep.SUMMARY_TAG + " ")) == null:
		return "the summary's JSON does not parse"
	return ""


func test_the_debris_level_is_built_with_debris() -> String:
	var plan: DebrisPlan = Sweep.load_debris_plan()
	if plan.error != "":
		return "debris.json: %s" % plan.error
	var level: LevelDef = Sweep.build_level(FIRST_SEED, SeedSweepRef.load_modules(),
		SeedSweepRef.load_reactor_plan(), SeedSweepRef.ship_radius(),
		SeedSweepRef.load_loop_bridges(), null, plan)
	if level.debris == null or level.debris.size() == 0:
		return "seed %d was built with no debris" % FIRST_SEED
	return ""
