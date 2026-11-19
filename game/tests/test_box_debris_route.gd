extends RefCounted

## Box-shaped meltdown entries close routes as rocks do (#458, RUN-4, MAP-2,
## RUN-3): a door that seals the shorter way falls and the map's route and the
## bot both take the longer one; a door that would seal the only way is held
## and never solid; a door over half an opening leaves it open when a ship fits.

const SHIP_TUNING_PATH: String = "res://data/ships/default_ship.json"
const SHIP_RADIUS: float = 1.0
## The ring from `test_debris_route_guard.gd`: a near room (box 0) with the
## start, a far room (box 3) and a left (box 1) and right (box 2) corridor. The
## left corridor meets the far room in x -10..-6, y -2..2, z -21..-19.
const LEFT_DOOR: String = '{"position": [-8, 0, -20], "size": [4, 4, 0.5], "after_seconds": 0.05}'
const RIGHT_DOOR: String = '{"position": [8, 0, -20], "size": [4, 4, 0.5], "after_seconds": 0.05}'
## Covers x -10..-8.5 of the left opening, leaving 2.5 m beside it.
const HALF_LEFT_DOOR: String = '{"position": [-9.25, 0, -20], "size": [1.5, 4, 0.5], "after_seconds": 0.05}'
## Parked in the far room nearer the left corridor, so left is the shorter way.
const PARKED: Vector3 = Vector3(-5, 0, -21)
## `test_bot_escape_debris.gd`'s two-route level with a door instead of the rock:
## half a second into the meltdown an 8 m by 8 m door shuts the corridor's near
## opening (x -4..4, y -4..4), and the long way round on the +x side stays open.
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
	"debris": [{"position": [0.0, 0.0, -8.0], "size": [8.0, 8.0, 1.0], "after_seconds": 0.5}]
}"""
const DOOR: int = 0
const LONG_WAY_X: float = 22.0
const TICK_LIMIT: int = 12000


class BotSource extends ShipInputSource:
	var bot: BotPilot = null

	func next_input(tick: int) -> ShipInput:
		return bot.next_input(tick) if bot != null else ShipInput.new()


func _ring() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-10, -2, -4), Vector3(10, 2, 0)),
		BoxBounds.new(Vector3(-10, -2, -21), Vector3(-6, 2, -2)),
		BoxBounds.new(Vector3(6, -2, -21), Vector3(10, 2, -2)),
		BoxBounds.new(Vector3(-10, -2, -23), Vector3(10, 2, -19))]
	return BoxUnion.new(boxes)


## One tick in, on the ring, the reactor already dead and the ship parked.
func _ring_sim(debris_text: String) -> Sim:
	var sim: Sim = Sim.new(458, 1)
	sim.set_walls(_ring())
	sim.set_start_pose(0, Vector3(0, 0, -1), Basis())
	sim.set_reactor(ReactorState.parse_json('{"position": [0, 0, -21], "radius": 0.5,'
		+ ' "hull": 1, "meltdown_seconds": 60, "exit_radius": 1}'))
	sim.set_debris(MeltdownDebris.parse_json(debris_text))
	sim.step(_idle())
	sim.ships[0].position = PARKED
	sim.reactor.apply_damage(1.0)
	return sim


func _idle() -> Array[ShipInput]:
	return [ShipInput.new()]


func _held(sim: Sim, ticks: int) -> Array[SimEvent]:
	var held: Array[SimEvent] = []
	for i: int in ticks:
		sim.step(_idle())
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.DEBRIS_HELD:
				held.append(event)
	return held


func _route(sim: Sim) -> KnownRoute:
	var all: Array[int] = []
	for index: int in sim.walls.boxes.size():
		all.append(index)
	return KnownRoute.find(sim.walls, all, sim.ships[0].position, sim.start_positions[0],
		sim.debris, SHIP_RADIUS)


func _runs_left(route: KnownRoute) -> bool:
	for point: Vector3i in route.points_mm:
		if point.x < -5000:
			return true
	return false


func test_a_door_sealing_the_shorter_way_falls_and_the_map_goes_round() -> String:
	var open: Sim = _ring_sim("[]")
	if not _runs_left(_route(open)):
		return "with no door the map's route does not run left, the test proves nothing"
	var sim: Sim = _ring_sim("[%s]" % LEFT_DOOR)
	if not _held(sim, 10).is_empty() or not sim.debris.is_solid(0):
		return "the door was held although the right corridor stays open"
	var route: KnownRoute = _route(sim)
	if route.length_mm == EscapePath.UNREACHABLE:
		return "no route left"
	if route.blocked_centres_mm != [Vector3i(-8000, 0, -20000)]:
		return "blocked openings at %s" % [route.blocked_centres_mm]
	if _runs_left(route):
		return "the map's route still runs left: %s" % [route.points_mm]
	return ""


func test_a_door_that_would_seal_the_last_way_is_held_and_never_solid() -> String:
	for times: Array in [["0.05", "0.1"], ["0.05", "0.05"]]:
		var right: String = RIGHT_DOOR.replace('"after_seconds": 0.05', '"after_seconds": %s' % times[1])
		var sim: Sim = _ring_sim("[%s, %s]" % [LEFT_DOOR.replace("0.05", times[0]), right])
		var held: Array[SimEvent] = _held(sim, 30)
		if not sim.debris.is_solid(0) or sim.debris.is_solid(1) or not sim.debris.is_skipped(1):
			return "%s: left solid %s, right solid %s" % [times, sim.debris.is_solid(0),
				sim.debris.is_solid(1)]
		if held.size() != 1 or held[0].magnitude != 1.0 or held[0].vector != Vector3(8, 0, -20):
			return "%s: held %s" % [times, held]
		if _route(sim).length_mm == EscapePath.UNREACHABLE:
			return "%s: the ship has no route left" % times
	return ""


func test_a_door_over_half_an_opening_leaves_the_shorter_way_open() -> String:
	var sim: Sim = _ring_sim("[%s, %s]" % [HALF_LEFT_DOOR, RIGHT_DOOR])
	if not _held(sim, 10).is_empty():
		return "a door was held although the left way stays open"
	if not sim.debris.is_solid(0) or not sim.debris.is_solid(1):
		return "a door did not fall"
	var route: KnownRoute = _route(sim)
	if route.length_mm == EscapePath.UNREACHABLE or not _runs_left(route):
		return "the map's route does not run left past the half door: %s" % [route.points_mm]
	return ""


func test_the_bot_route_closes_the_door_opening_and_flies_round() -> String:
	var level: LevelDef = LevelDef.parse_json(TWO_ROUTE_LEVEL)
	if level.error != "":
		return level.error
	var route: LevelRoute = LevelRoute.new(level)
	var debris: MeltdownDebris = level.debris.fresh_copy()
	var from: Vector3 = Vector3(20.0, 0.0, -100.0)
	route.close_blocked(debris, SHIP_RADIUS)
	if route.chain(from, Vector3.ZERO, SHIP_RADIUS) != [2, 1, 0]:
		return "before the door falls the chain is %s" % [route.chain(from, Vector3.ZERO, SHIP_RADIUS)]
	debris.elapsed_ticks = debris.after_ticks[DOOR]
	route.close_blocked(debris, SHIP_RADIUS)
	if not route.is_closed(0, 1) or route.is_closed(1, 2):
		return "closed: near %s, far %s" % [route.is_closed(0, 1), route.is_closed(1, 2)]
	if route.chain(from, Vector3.ZERO, SHIP_RADIUS) != [2, 4, 3, 0]:
		return "with the door down the chain is %s" % [route.chain(from, Vector3.ZERO, SHIP_RADIUS)]
	# A straight leg through the door is not flown, though it passes its centre's
	# side, where a point would not be met.
	var leg_from: Vector3 = Vector3(3.0, 3.0, -20.0)
	var leg_to: Vector3 = Vector3(3.0, 3.0, 5.0)
	if route.waypoints(leg_from, leg_to, SHIP_RADIUS) == [leg_to]:
		return "the straight leg through the door was still flown"
	return ""


func test_the_bot_escapes_the_long_way_without_touching_the_door() -> String:
	var level: LevelDef = LevelDef.parse_json(TWO_ROUTE_LEVEL)
	var source: BotSource = BotSource.new()
	var session: LocalSession = LocalSession.for_level(level, 0, source,
		LocalSession.load_tuning(SHIP_TUNING_PATH))
	source.bot = BotPilot.new(session.sim, 0, level)
	var sim: Sim = session.sim
	var half: Vector3 = level.debris.box_size(DOOR) * 0.5
	var centre: Vector3 = level.debris.position(DOOR)
	var closest: float = INF
	var long_way: bool = false
	while sim.outcome() == ExitRule.Outcome.RUNNING and sim.ships[0].hull > 0.0 \
			and sim.tick < TICK_LIMIT:
		session.advance(ShipState.TICK_DT)
		var ship: ShipState = sim.ships[0]
		if sim.debris.is_solid(DOOR):
			var local: Vector3 = ship.position - centre
			closest = minf(closest, (local - local.clamp(-half, half)).length() - ship.radius)
		long_way = long_way or ship.position.x > LONG_WAY_X
	if not sim.reactor.destroyed:
		return "the reactor was not destroyed by tick %d" % sim.tick
	if not sim.debris.is_solid(DOOR):
		return "the door never fell (held: %s); the test needs it solid" % sim.debris.is_skipped(DOOR)
	if sim.outcome() != ExitRule.Outcome.ESCAPED:
		return "outcome %s at tick %d, hull %.2f" % [ExitRule.Outcome.keys()[sim.outcome()],
			sim.tick, sim.ships[0].hull]
	if closest <= 0.0:
		return "the ship touched the door (closest %.3f m)" % closest
	if not long_way:
		return "the ship did not fly the long way round"
	return ""
