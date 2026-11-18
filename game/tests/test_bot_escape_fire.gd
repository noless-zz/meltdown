extends RefCounted

## The bot's escape prefers a route without fire when it is not much longer
## (#498, RUN-4, CMB-2, DEV-6): fire on the shorter of two near-equal routes is
## flown round, fire on the only route is flown through, and a level without
## fire flies exactly as before. The map route stays as it was: fire is
## passable for `KnownRoute` (see `test_meltdown_fire_route.gd`).

const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
## Start room (box 0), two 6 m corridors to the reactor room, on the -x side
## (box 1) and the +x side (box 3), the reactor room (box 2) and an alcove off
## it holding the reactor (box 4), round a corner so the bot has to enter the
## room to shoot it. From there both ways out are about as long; the bot takes
## the -x one, by the lower box index. Once the reactor dies a fire fills the -x
## corridor.
const RING_LEVEL: String = """{
	"boxes": [
		{"min": [-14.0, -6.0, -10.0], "max": [14.0, 6.0, 10.0]},
		{"min": [-11.0, -3.0, -62.0], "max": [-5.0, 3.0, -6.0]},
		{"min": [-14.0, -6.0, -110.0], "max": [14.0, 6.0, -58.0]},
		{"min": [5.0, -3.0, -62.0], "max": [11.0, 3.0, -6.0]},
		{"min": [10.0, -6.0, -110.0], "max": [60.0, 6.0, -90.0]}
	],
	"start": {"position": [0.0, 0.0, 0.0], "facing": [0.0, 0.0, -1.0]},
	"robots": [],
	"reactor": {"position": [50, 0, -100], "radius": 2, "hull": 40, "meltdown_seconds": 60},
	"debris": [{"position": [-8.0, 0.0, -30.0], "size": [6.0, 6.0, 4.0], "after_seconds": 0.1,
		"kind": "fire", "damage_per_second": 5}]
}"""
const FIRE: int = 0
const LEFT_CORRIDOR: int = 1
const RIGHT_CORRIDOR: int = 3
const TICK_LIMIT: int = 12000
## Waypoints from the reactor room to the start, by the -x and the +x corridor.
const LEFT_WAY: Array[Vector3] = [Vector3(-8, 0, -60), Vector3(-8, 0, -8), Vector3.ZERO]
const RIGHT_WAY: Array[Vector3] = [Vector3(8, 0, -60), Vector3(8, 0, -8), Vector3.ZERO]
## `Sim.state_hash` once the bot has escaped the ring level without its fire,
## recorded on `main` before #498 (at ecf07d4).
const NO_FIRE_FINAL_HASH: int = 1145033555
const NO_FIRE_FINAL_TICK: int = 1251


class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


## How the flight went.
class Flight extends RefCounted:
	var sim: Sim = null
	## Ticks the ship's centre spent inside burning fire.
	var burnt_ticks: int = 0
	var used_right: bool = false
	var used_left_after_death: bool = false


static func _level(fire: bool, right_way: bool) -> LevelDef:
	var level: LevelDef = LevelDef.parse_json(RING_LEVEL)
	if not fire:
		level.debris = null
	if not right_way:
		var data: Dictionary = JSON.parse_string(RING_LEVEL)
		(data["boxes"] as Array).remove_at(RIGHT_CORRIDOR)
		level = LevelDef.parse_json(JSON.stringify(data))
		if not fire:
			level.debris = null
	return level


static func _fly(level: LevelDef) -> Flight:
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, level)
	var flight: Flight = Flight.new()
	flight.sim = session.sim
	var sim: Sim = session.sim
	var boxes: Array[BoxBounds] = level.union.boxes
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		var ship: ShipState = sim.ships[0]
		if sim.debris != null and sim.debris.is_burning(FIRE) \
				and MeltdownFire.contains(sim.debris, FIRE, ship.position):
			flight.burnt_ticks += 1
		if ship.position.x > 4.0 and ship.position.z > -56.0 and ship.position.z < -12.0:
			flight.used_right = true
		if sim.reactor.destroyed and boxes[LEFT_CORRIDOR].holds(ship.position, 0.0) \
				and ship.position.z > -50.0 and ship.position.z < -15.0:
			flight.used_left_after_death = true
	return flight


static func _outcome(sim: Sim) -> String:
	return "outcome %s at tick %d, hull %.2f" % [ExitRule.Outcome.keys()[sim.outcome()],
		sim.tick, sim.ships[0].hull]


func test_the_ring_level_parses() -> String:
	for fire: bool in [true, false]:
		for right_way: bool in [true, false]:
			var level: LevelDef = _level(fire, right_way)
			if level.error != "":
				return level.error
			if (level.debris != null) != fire:
				return "fire %s: debris %s" % [fire, level.debris]
			if level.union.boxes.size() != (5 if right_way else 4):
				return "right way %s: %d boxes" % [right_way, level.union.boxes.size()]
	return ""


func test_fire_on_the_shorter_way_is_flown_round() -> String:
	var flight: Flight = _fly(_level(true, true))
	var sim: Sim = flight.sim
	if not sim.reactor.destroyed:
		return "the reactor was not destroyed by tick %d" % sim.tick
	if not sim.debris.is_burning(FIRE):
		return "the fire never lit; the test needs it burning"
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return _outcome(sim)
	if flight.burnt_ticks > 0:
		return "the ship was in the fire for %d ticks" % flight.burnt_ticks
	if not flight.used_right:
		return "the ship did not fly out the +x way"
	return ""


func test_fire_on_the_only_way_is_flown_through() -> String:
	var flight: Flight = _fly(_level(true, false))
	var sim: Sim = flight.sim
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return _outcome(sim)
	if flight.burnt_ticks == 0:
		return "the ship never crossed the fire on the only way out"
	return ""


func test_without_fire_the_bot_flies_as_before() -> String:
	var flight: Flight = _fly(_level(false, true))
	var sim: Sim = flight.sim
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return _outcome(sim)
	if flight.used_right:
		return "with no fire the bot flew the +x way"
	if not flight.used_left_after_death:
		return "with no fire the bot did not fly back down the -x corridor"
	if sim.tick != NO_FIRE_FINAL_TICK or sim.state_hash() != NO_FIRE_FINAL_HASH:
		return "escaped at tick %d with hash %d, expected tick %d and hash %d" % [sim.tick,
			sim.state_hash(), NO_FIRE_FINAL_TICK, NO_FIRE_FINAL_HASH]
	return ""


## The ring level's route and its debris with the fire `ticks_to_fire` ticks
## from lighting (0: burning).
static func _route_and_fire(ticks_to_fire: int) -> Array:
	var level: LevelDef = _level(true, true)
	var debris: MeltdownDebris = level.debris.fresh_copy()
	debris.elapsed_ticks = debris.after_ticks[FIRE] - ticks_to_fire
	return [LevelRoute.new(level), debris]



func test_a_route_ignores_fire_until_told_to_weigh_it() -> String:
	var pair: Array = _route_and_fire(0)
	var route: LevelRoute = pair[0]
	var from: Vector3 = Vector3(0, 0, -90)
	if route.waypoints(from, Vector3.ZERO, 1.0) != LEFT_WAY:
		return "unweighed route %s" % [route.waypoints(from, Vector3.ZERO, 1.0)]
	route.weigh_fire(pair[1], 15.0, 1.5)
	if route.waypoints(from, Vector3.ZERO, 1.0) != RIGHT_WAY:
		return "weighed route %s" % [route.waypoints(from, Vector3.ZERO, 1.0)]
	route.weigh_fire(null, 15.0, 1.5)
	if route.waypoints(from, Vector3.ZERO, 1.0) != LEFT_WAY:
		return "route after weighing stopped %s" % [route.waypoints(from, Vector3.ZERO, 1.0)]
	return ""


func test_a_detour_longer_than_the_factor_is_not_taken() -> String:
	var pair: Array = _route_and_fire(0)
	var route: LevelRoute = pair[0]
	# From the left of the room the right way is longer than the left one.
	var from: Vector3 = Vector3(-6, 0, -90)
	route.weigh_fire(pair[1], 15.0, 1.0)
	if route.waypoints(from, Vector3.ZERO, 1.0) != LEFT_WAY:
		return "factor 1.0 took %s" % [route.waypoints(from, Vector3.ZERO, 1.0)]
	route.weigh_fire(pair[1], 15.0, 1.5)
	if route.waypoints(from, Vector3.ZERO, 1.0) != RIGHT_WAY:
		return "factor 1.5 took %s" % [route.waypoints(from, Vector3.ZERO, 1.0)]
	return ""


func test_fire_due_before_the_ship_arrives_counts_and_later_fire_does_not() -> String:
	var from: Vector3 = Vector3(0, 0, -90)
	# The leg through the fire ends about 83 m along: some five seconds at 15 m/s.
	var soon: Array = _route_and_fire(120)
	(soon[0] as LevelRoute).weigh_fire(soon[1], 15.0, 1.5)
	if (soon[0] as LevelRoute).waypoints(from, Vector3.ZERO, 1.0) != RIGHT_WAY:
		return "fire due in two seconds was flown into"
	var late: Array = _route_and_fire(1200)
	(late[0] as LevelRoute).weigh_fire(late[1], 15.0, 1.5)
	if (late[0] as LevelRoute).waypoints(from, Vector3.ZERO, 1.0) != LEFT_WAY:
		return "fire due in twenty seconds turned the route"
	return ""


func test_fire_holding_the_ship_does_not_turn_it_back() -> String:
	var pair: Array = _route_and_fire(0)
	var route: LevelRoute = pair[0]
	route.weigh_fire(pair[1], 15.0, 1.5)
	var inside: Vector3 = Vector3(-8, 0, -30)
	var points: Array[Vector3] = route.waypoints(inside, Vector3.ZERO, 1.0)
	if points != [Vector3(-8, 0, -8), Vector3.ZERO]:
		return "from inside the fire the route is %s" % [points]
	return ""
