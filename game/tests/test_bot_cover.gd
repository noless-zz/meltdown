extends RefCounted

## The bot pilot's cover (#492): which points a robot can hit, how many robots
## can hit the ship, and the nearest point out of every line of fire. The G2
## level is the playground: a corridor (box 0) turning down a shaft (box 1).

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
const SHIP: String = "res://data/ships/default_ship.json"
const DRONE: String = "res://data/robots/drone.json"
const WEAPONS: String = "res://data/weapons/"
## Down the corridor, in sight of the start.
const CORRIDOR_ROBOT: Vector3 = Vector3(0.0, 0.0, -30.0)
## In the shaft, behind rock from the start.
const SHAFT_ROBOT: Vector3 = Vector3(0.0, -30.0, -42.0)


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


## An armed ship at the origin facing -z inside the level's walls, and an
## armed drone at each of `positions`.
func _sim(level: LevelDef, positions: Array[Vector3]) -> Sim:
	var sim: Sim = Sim.new(3, 1)
	sim.set_walls(level.union)
	sim.equip(LocalSession.load_tuning(SHIP).loadout)
	var def: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS + def.weapon + ".json"))
	for position: Vector3 in positions:
		sim.spawn_robot(def, position, Basis.IDENTITY, weapon)
	return sim


func test_a_robot_hits_along_the_corridor_but_not_through_rock() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [CORRIDOR_ROBOT, SHAFT_ROBOT])
	if not BotCover.hits(sim, level.union, sim.robots[0], Vector3.ZERO):
		return "the drone down the corridor does not hit the start"
	if BotCover.hits(sim, level.union, sim.robots[1], Vector3.ZERO):
		return "the drone in the shaft hits the start through rock"
	return ""


func test_an_intact_reactor_shields_the_ship() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [CORRIDOR_ROBOT])
	var reactor: ReactorState = ReactorState.parse_json(
		"{\"position\": [0.0, 0.0, -15.0], \"radius\": 2.5, \"hull\": 400.0, \"meltdown_seconds\": 90.0}")
	if reactor.error != "" or not sim.set_reactor(reactor):
		return "set-up: the reactor was refused: %s" % reactor.error
	if BotCover.hits(sim, level.union, sim.robots[0], Vector3.ZERO):
		return "the drone hits the start through the reactor"
	if not BotCover.hits(sim, level.union, sim.robots[0], Vector3(5.5, 3.5, 0.0)):
		return "the drone does not hit a point beside the reactor's shadow"
	return ""


func test_threats_count_every_robot_that_can_hit_and_name_the_nearest() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [CORRIDOR_ROBOT, Vector3(2.0, 1.0, -20.0), SHAFT_ROBOT])
	var cover: BotCover = BotCover.new(sim, level, LevelRoute.new(level))
	var ship: ShipState = sim.ships[0]
	if cover.threat_count(ship) != 2:
		return "threat count %d, expected the two drones in the corridor" % cover.threat_count(ship)
	if cover.threat(ship) != sim.robots[1]:
		return "the nearest threat is not the nearer corridor drone"
	return ""


## Seen from down the corridor at the start, the bot finds a point no drone
## can hit, joined to it by the route, and keeps it while it serves.
func test_cover_is_out_of_every_line_of_fire() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [CORRIDOR_ROBOT])
	var route: LevelRoute = LevelRoute.new(level)
	var cover: BotCover = BotCover.new(sim, level, route)
	var ship: ShipState = sim.ships[0]
	if not cover.exposed(ship.position):
		return "set-up: the start is not exposed"
	var point: Vector3 = cover.point_for(ship)
	if point == Vector3.INF:
		return "no cover found"
	if cover.exposed(point):
		return "cover %s is exposed" % point
	if route.chain(ship.position, point, ship.radius).is_empty():
		return "the route does not join the ship to cover %s" % point
	if not level.union.holds(point, ship.radius + BotCover.WALL_CLEARANCE):
		return "cover %s is too near a wall" % point
	if cover.point_for(ship) != point:
		return "the cover point changed while it still served"
	return ""


## With no robot able to hit anywhere, the nearest candidate is cover.
func test_without_robots_the_nearest_candidate_is_cover() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level, [])
	var cover: BotCover = BotCover.new(sim, level, LevelRoute.new(level))
	var ship: ShipState = sim.ships[0]
	var point: Vector3 = cover.point_for(ship)
	var nearest: float = INF
	for candidate: Vector3 in cover.candidates(ship):
		nearest = minf(nearest, candidate.distance_to(ship.position))
	if point == Vector3.INF or not is_equal_approx(point.distance_to(ship.position), nearest):
		return "cover %s is not the nearest candidate (%f m)" % [point, nearest]
	return ""
