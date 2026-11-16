extends RefCounted

## The bot pilot's route through a level's boxes (#289, CMB-3, GEN-5, ARC-1):
## every leg clear of rock, the flight held by the union on every tick, and
## deterministic.

const LEVEL_FILE: String = "res://data/levels/g2_level.json"
## The issue's limit: one minute of flight.
const TICK_LIMIT: int = 3600
## Close enough to the goal to count as arrived, metres.
const ARRIVED_M: float = 1.0
## Step of the independent segment check, metres.
const SAMPLE_M: float = 0.05


func _level() -> LevelDef:
	return LevelDef.parse_json(FileAccess.get_file_as_string(LEVEL_FILE))


static func _centre(box: BoxBounds) -> Vector3:
	return (box.min_corner + box.max_corner) * 0.5


## Centre of the box farthest from the level's start.
static func _farthest_centre(level: LevelDef) -> Vector3:
	var best: Vector3 = level.start_position()
	for box: BoxBounds in level.union.boxes:
		var centre: Vector3 = _centre(box)
		if level.start_position().distance_to(centre) > level.start_position().distance_to(best):
			best = centre
	return best


## Checked by sampling, independently of `LevelRoute.segment_held`.
static func _sampled_held(union: BoxUnion, from: Vector3, to: Vector3, radius: float) -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / SAMPLE_M))
	for i: int in steps + 1:
		if not union.holds(from.lerp(to, float(i) / float(steps)), radius):
			return false
	return true


## A sim with one ship at the level's start, no robots and no walls, so only
## the bot keeps the ship off the rock.
func _sim(level: LevelDef) -> Sim:
	var sim: Sim = Sim.new(5, 1)
	var facing: Vector3 = level.start_facing()
	sim.set_start_pose(0, level.start_position(), Basis.looking_at(facing, Vector3.UP))
	return sim


## Flies the bot to `goal`. Returns "" or what went wrong; `ticks` gets the
## ticks flown.
func _fly(sim: Sim, bot: BotPilot, goal: Vector3, union: BoxUnion, ticks: Array[int]) -> String:
	var ship: ShipState = sim.ships[0]
	var limit: Vector3 = Vector3(BotPilot.MAX_PITCH_RATE, BotPilot.MAX_YAW_RATE, 0.0)
	while ship.position.distance_to(goal) > ARRIVED_M:
		if sim.tick >= TICK_LIMIT:
			return "not arrived after %d ticks, at %s" % [sim.tick, ship.position]
		var before: int = sim.state_hash()
		var input: ShipInput = bot.next_input(sim.tick)
		if sim.state_hash() != before:
			return "next_input changed the sim at tick %d" % sim.tick
		var turn: Vector3 = input.turn()
		for axis: int in 3:
			if absf(turn[axis]) > limit[axis] + 0.001:
				return "tick %d turn %s exceeds %s" % [sim.tick, turn, limit]
		var inputs: Array[ShipInput] = [input]
		sim.step(inputs)
		if not union.holds(ship.position, ship.radius):
			return "tick %d: ship at %s is not held by the level" % [sim.tick, ship.position]
	ticks.append(sim.tick)
	return ""


func test_g2_level_loads() -> String:
	var level: LevelDef = _level()
	if level.error != "":
		return level.error
	if level.union.boxes.size() < 3:
		return "expected a level of several boxes"
	return ""


func test_segment_held_follows_the_rock() -> String:
	var union: BoxUnion = _level().union
	if not LevelRoute.segment_held(union, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 0.0, -38.0), 1.0):
		return "a segment down the first corridor is not held"
	if LevelRoute.segment_held(union, Vector3(0.0, 0.0, 0.0), Vector3(0.0, -40.0, -60.0), 1.0):
		return "a segment through rock is held"
	if LevelRoute.segment_held(union, Vector3(0.0, 0.0, 0.0), Vector3(0.0, 3.5, -20.0), 1.0):
		return "a segment ending closer than the radius to the ceiling is held"
	return ""


func test_every_route_between_box_centres_is_clear() -> String:
	var level: LevelDef = _level()
	var route: LevelRoute = LevelRoute.new(level)
	var radius: float = ShipState.new().radius
	var ends: Array[Vector3] = [level.start_position()]
	for box: BoxBounds in level.union.boxes:
		ends.append(_centre(box))
	for from: Vector3 in ends:
		for to: Vector3 in ends:
			var points: Array[Vector3] = route.waypoints(from, to, radius)
			if points.back() != to:
				return "route %s to %s does not end at the target" % [from, to]
			var last: Vector3 = from
			for point: Vector3 in points:
				if not level.union.holds(point, radius):
					return "waypoint %s on %s to %s is not held" % [point, from, to]
				if not _sampled_held(level.union, last, point, radius):
					return "leg %s to %s on %s to %s crosses rock" % [last, point, from, to]
				last = point
	return ""


func test_route_to_the_farthest_box_goes_round_the_corners() -> String:
	var level: LevelDef = _level()
	var route: LevelRoute = LevelRoute.new(level)
	var points: Array[Vector3] = route.waypoints(level.start_position(), _farthest_centre(level),
		ShipState.new().radius)
	if points.size() < 3:
		return "expected a route through several openings, got %s" % [points]
	return ""


func test_flies_from_the_start_to_the_farthest_box_inside_the_level() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level)
	var bot: BotPilot = BotPilot.new(sim, 0, level)
	var goal: Vector3 = _farthest_centre(level)
	bot.set_goal(goal)
	var ticks: Array[int] = []
	var problem: String = _fly(sim, bot, goal, level.union, ticks)
	if problem != "":
		return problem
	print("Meltdown: bot reached the farthest G2 box in %d ticks" % ticks[0])
	return ""


func test_two_flights_give_the_same_hash() -> String:
	var level: LevelDef = _level()
	var goal: Vector3 = _farthest_centre(level)
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = _sim(level)
		var bot: BotPilot = BotPilot.new(sim, 0, level)
		bot.set_goal(goal)
		var ticks: Array[int] = []
		var problem: String = _fly(sim, bot, goal, level.union, ticks)
		if problem != "":
			return problem
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "two flights ended on hashes %d and %d" % hashes
	return ""


func test_with_a_level_but_no_robot_or_goal_it_stays_put() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level)
	var input: ShipInput = BotPilot.new(sim, 0, level).next_input(0)
	if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO or input.fire_primary:
		return "expected no input without a robot or a goal"
	return ""


func test_a_robot_round_the_corner_is_reached_by_the_route() -> String:
	var level: LevelDef = _level()
	var sim: Sim = _sim(level)
	var drone: RobotDef = RobotDef.parse_json(
		FileAccess.get_file_as_string("res://data/robots/drone.json"))
	sim.spawn_robot(drone, Vector3(0.0, -40.0, -60.0), Basis.IDENTITY)
	var input: ShipInput = BotPilot.new(sim, 0, level).next_input(0)
	# The drone is below and ahead through rock; the first opening is straight
	# ahead (-z), so the bot thrusts forward, not down, and holds fire.
	if input.thrust_q.z >= 0 or input.thrust_q.y < 0 or input.fire_primary:
		return "input %s %s, expected forward thrust towards the opening" % [
			input.thrust_q, input.fire_primary]
	return ""
