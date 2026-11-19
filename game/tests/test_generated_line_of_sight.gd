extends RefCounted

## Robots behind walls in generated mines (#615, CMB-2, CMB-3, GEN-5, ARC-1):
## the owner was hit through corridor walls on seeds 31 and 1. On those seeds,
## every robot is paired with spots in weapon range it has no clear line to,
## and from none of them does it hurt the ship; over seeds 0..99 no robot shot
## ever leaves open space; and every wall the view draws is solid in the core.

## Seeds the owner flew when he was hit through walls.
const OWNER_SEEDS: Array[int] = [31, 1]
const SWEEP_SEEDS: int = 100
## Five seconds a pair: a drone turns to face the ship and fires many times.
const PAIR_TICKS: int = 300
## The most pairs flown per seed, nearest first, to keep the test short.
const PAIRS_PER_SEED: int = 12
## Ticks the ship holds each spot in the sweep.
const SPOT_TICKS: int = 20
## How far off a drawn face the view-wall test looks, metres.
const PROBE_M: float = 0.01
## How far in from a quad's sides its probe points sit, metres.
const INSET_M: float = 0.02


func _session(level_seed: int) -> LocalSession:
	var level: LevelDef = SeedLevel.load_level(level_seed)
	if level == null:
		return null
	return LocalSession.for_level(level, 0, null, LocalSession.load_tuning(AcceptanceStepLevel.SHIP_FILE))


## Centres of every box, the spots the ship is put at.
func _spots(walls: BoxUnion) -> Array[Vector3]:
	var spots: Array[Vector3] = []
	for box: BoxBounds in walls.boxes:
		spots.append((box.min_corner + box.max_corner) * 0.5)
	return spots


## A copy of `def` that holds its place, so a robot cannot fly round to a
## clear line during the pair test.
func _hovering(def: RobotDef) -> RobotDef:
	var copy: RobotDef = RobotDef.new()
	for property: Dictionary in def.get_property_list():
		if property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(property["name"], def.get(property["name"]))
	copy.movement = "hover"
	return copy


## Robot index and spot for each armed robot and each spot in its weapon range
## it has no clear line to, nearest first, at most `PAIRS_PER_SEED`.
func _hidden_pairs(sim: Sim) -> Array[Array]:
	var pairs: Array[Array] = []
	for r: int in sim.robots.size():
		var robot: RobotState = sim.robots[r]
		if robot.weapon == null:
			continue
		for spot: Vector3 in _spots(sim.walls):
			var distance: float = robot.position.distance_to(spot)
			if distance > robot.weapon_range() or distance < 1.0:
				continue
			if not LineOfSight.clear(sim.walls, robot.position, spot):
				pairs.append([distance, r, spot])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return pairs.slice(0, PAIRS_PER_SEED)


func test_owner_seeds_robots_never_hit_the_ship_through_a_wall() -> String:
	for level_seed: int in OWNER_SEEDS:
		var session: LocalSession = _session(level_seed)
		if session == null:
			return "seed %d: the level was rejected" % level_seed
		var pairs: Array[Array] = _hidden_pairs(session.sim)
		if pairs.is_empty():
			return "seed %d: no robot with a spot in range behind a wall; the test checks nothing" % level_seed
		for pair: Array in pairs:
			var problem: String = _fly_pair(session.sim, pair[1], pair[2])
			if problem != "":
				return "seed %d, robot %d, ship at %s: %s" % [level_seed, pair[1], pair[2], problem]
	return ""


## A sim on the same walls with only robot `r`, awake and holding its place,
## facing the ship, which holds still at `spot`. "" if it is never hit.
func _fly_pair(source: Sim, r: int, spot: Vector3) -> String:
	var robot: RobotState = source.robots[r]
	var sim: Sim = Sim.new(source.run_seed, 1)
	sim.set_walls(source.walls)
	sim.set_start_pose(0, spot, Basis.IDENTITY)
	sim.ships[0].shield_recharge = 0.0
	var facing: Basis = Basis.looking_at(spot - robot.position, Vector3.UP if absf(
		(spot - robot.position).normalized().y) < 0.99 else Vector3.RIGHT)
	sim.spawn_robot(_hovering(robot.def), robot.position, facing, robot.weapon)
	sim.robots[0].awake = true
	var start: float = sim.ships[0].shield + sim.ships[0].hull
	var inputs: Array[ShipInput] = [ShipInput.new()]
	for i: int in PAIR_TICKS:
		sim.step(inputs)
		for event: SimEvent in sim.last_events:
			if event.kind == SimEvent.Kind.SHIP_HIT:
				return "hit on tick %d" % sim.tick
		for projectile: Projectile in sim.projectiles:
			if projectile.is_robot_owned():
				return "fired on tick %d with no line" % sim.tick
	if sim.ships[0].shield + sim.ships[0].hull != start:
		return "lost %f" % (start - sim.ships[0].shield - sim.ships[0].hull)
	return ""


## The ship visits every box centre in turn, unhurt so robots keep firing; every
## robot shot's path each tick must lie in open space.
func test_robot_shots_never_leave_open_space_over_100_seeds() -> String:
	var shots_seen: int = 0
	for level_seed: int in SWEEP_SEEDS:
		var session: LocalSession = _session(level_seed)
		if session == null:
			continue
		var sim: Sim = session.sim
		for robot: RobotState in sim.robots:
			robot.awake = true
		var last: Dictionary[Projectile, Vector3] = {}
		var inputs: Array[ShipInput] = [ShipInput.new()]
		for spot: Vector3 in _spots(sim.walls):
			sim.ships[0].position = spot
			sim.ships[0].velocity = Vector3.ZERO
			for i: int in SPOT_TICKS:
				sim.ships[0].hull = 1.0e9
				sim.step(inputs)
				var now: Dictionary[Projectile, Vector3] = {}
				for projectile: Projectile in sim.projectiles:
					if not projectile.is_robot_owned():
						continue
					shots_seen += 1
					var from: Vector3 = last.get(projectile, projectile.position)
					if not LineOfSight.clear(sim.walls, from, projectile.position):
						return "seed %d, tick %d: a robot shot went from %s to %s through a wall" % [
							level_seed, sim.tick, from, projectile.position]
					now[projectile] = projectile.position
				last = now
	if shots_seen == 0:
		return "no robot fired in 100 seeds; the sweep checks nothing"
	return ""


## Every wall quad `LevelFaces` draws for a generated level lies on the
## boundary of the core's open space: just inside it is open, and no clear line
## (`LineOfSight`) goes through it to just behind it. A wall drawn where the core is open would hide a robot that can
## see the ship. Test only: a failure here belongs to a lane-c fix in `view/`.
func test_every_drawn_wall_is_solid_in_the_core() -> String:
	for level_seed: int in OWNER_SEEDS + [0, 2, 3, 4, 5, 6, 7, 8]:
		var level: LevelDef = SeedLevel.load_level(level_seed)
		if level == null:
			continue
		var walls: BoxUnion = level.union
		for quad: Dictionary in LevelFaces.quads(walls):
			var normal: Vector3 = quad["normal"]
			for point: Vector3 in _probe_points(quad):
				if not walls.holds(point + normal * PROBE_M, 0.0):
					return "seed %d: in front of the wall at %s is not open" % [level_seed, point]
				# Behind may be another box face to face with this one; that is a
				# wall for shots, sight and ships alike, so only a clear line
				# through the drawn face is wrong.
				if LineOfSight.clear(walls, point + normal * PROBE_M, point - normal * PROBE_M):
					return "seed %d: the view draws a wall at %s where the core is open" % [
						level_seed, point]
	return ""


## The quad's centre and four points just in from its corners.
func _probe_points(quad: Dictionary) -> Array[Vector3]:
	var low: Vector3 = quad["min"]
	var high: Vector3 = quad["max"]
	var axis: int = quad["axis"]
	var points: Array[Vector3] = [(low + high) * 0.5]
	var u: int = (axis + 1) % 3
	var v: int = (axis + 2) % 3
	for pu: float in [low[u] + INSET_M, high[u] - INSET_M]:
		for pv: float in [low[v] + INSET_M, high[v] - INSET_M]:
			var point: Vector3 = low
			point[u] = pu
			point[v] = pv
			points.append(point)
	return points
