extends RefCounted

## Robot movement towards the nearest ship: hover turns to face, chase closes
## to a stand-off, strafe circles in a band (CMB-3, ARC-1, ARC-2, ARC-4, #224).

const ROBOTS_DIR: String = "res://data/robots"
## Slack on angle checks, radians: orthonormalising the basis each tick moves
## the facing by far less than this.
const ANGLE_EPSILON: float = 1e-4


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


## One ship at the origin facing -z, holding still, and one robot of type `id`
## at `position`, facing +z (away from the ship when it is in front of it).
func _sim_with(id: String, position: Vector3) -> Sim:
	var sim: Sim = Sim.new(5, 1)
	sim.spawn_robot(_def(id), position, Basis(Vector3.UP, PI))
	return sim


func _still() -> Array[ShipInput]:
	return [ShipInput.new()]


## Signed angle of `offset` around the world vertical, radians.
func _bearing(offset: Vector3) -> float:
	return atan2(offset.x, offset.z)


func test_chaser_closes_from_40_m_and_holds_its_standoff() -> String:
	for id: String in ["hauler", "needler"]:
		var sim: Sim = _sim_with(id, Vector3(0.0, 0.0, -40.0))
		var robot: RobotState = sim.robots[0]
		var ship: ShipState = sim.ships[0]
		var standoff: float = robot.chase_standoff(ship)
		var never_closer: float = robot.def.radius + ship.radius
		for i: int in 1800:
			sim.step(_still())
			var distance: float = robot.position.distance_to(ship.position)
			if distance <= never_closer:
				return "%s reached the ship (%s m) at tick %d" % [id, distance, sim.tick]
			if distance < standoff - 0.25:
				return "%s overshot its stand-off %s to %s m at tick %d" % [id, standoff, distance, sim.tick]
		for i: int in 120:
			sim.step(_still())
			var distance: float = robot.position.distance_to(ship.position)
			if absf(distance - standoff) > 0.25:
				return "%s at %s m, stand-off %s m, at tick %d" % [id, distance, standoff, sim.tick]
	return ""


func test_chaser_backs_off_when_inside_its_standoff() -> String:
	var sim: Sim = _sim_with("needler", Vector3(0.0, 0.0, -1.0))
	var robot: RobotState = sim.robots[0]
	var standoff: float = robot.chase_standoff(sim.ships[0])
	for i: int in 300:
		sim.step(_still())
	var distance: float = robot.position.length()
	if absf(distance - standoff) > 0.25:
		return "needler at %s m after backing off, stand-off %s m" % [distance, standoff]
	return ""


func test_strafer_ends_in_its_band_circling_one_way() -> String:
	for id: String in ["glider", "skimmer"]:
		for start: Vector3 in [Vector3(0.0, 0.0, -40.0), Vector3(3.0, 0.0, -4.0)]:
			var sim: Sim = _sim_with(id, start)
			var robot: RobotState = sim.robots[0]
			for i: int in 600:
				sim.step(_still())
			var previous: float = _bearing(robot.position)
			var sign: float = 0.0
			for i: int in 600:
				sim.step(_still())
				var distance: float = robot.position.length()
				if distance < robot.def.strafe_min_distance or distance > robot.def.strafe_max_distance:
					return "%s from %s at %s m, outside its band, at tick %d" % [id, start, distance, sim.tick]
				var bearing: float = _bearing(robot.position)
				var change: float = wrapf(bearing - previous, -PI, PI)
				previous = bearing
				if change == 0.0:
					return "%s bearing stopped changing at tick %d" % [id, sim.tick]
				if sign == 0.0:
					sign = signf(change)
				elif signf(change) != sign:
					return "%s bearing reversed at tick %d" % [id, sim.tick]
	return ""


func test_strafers_circle_by_spawn_index() -> String:
	var sim: Sim = Sim.new(5, 1)
	sim.spawn_robot(_def("glider"), Vector3(0.0, 0.0, -15.0), Basis.IDENTITY)
	sim.spawn_robot(_def("glider"), Vector3(0.0, 0.0, 15.0), Basis.IDENTITY)
	if sim.robots[0].strafe_direction != 1 or sim.robots[1].strafe_direction != -1:
		return "strafe directions %d, %d" % [sim.robots[0].strafe_direction, sim.robots[1].strafe_direction]
	var before: Array[float] = [_bearing(sim.robots[0].position), _bearing(sim.robots[1].position)]
	for i: int in 120:
		sim.step(_still())
	var first: float = wrapf(_bearing(sim.robots[0].position) - before[0], -PI, PI)
	var second: float = wrapf(_bearing(sim.robots[1].position) - before[1], -PI, PI)
	if signf(first) == signf(second):
		return "both strafers circled the same way (%s, %s)" % [first, second]
	return ""


func test_turn_rate_is_never_exceeded() -> String:
	var sim: Sim = Sim.new(5, 1)
	for id: String in ["drone", "hauler", "glider", "needler", "skimmer", "warden"]:
		sim.spawn_robot(_def(id), Vector3(float(sim.robots.size()) * 3.0, 1.0, 25.0),
			Basis(Vector3.UP, 0.3))
	# The ship turns and moves, so every robot keeps turning to follow it.
	var input: ShipInput = ShipInput.new(Vector3i(500, 300, -800), Vector3i(200, 400, 0))
	for i: int in 600:
		var facings: Array[Vector3] = []
		for robot: RobotState in sim.robots:
			facings.append(robot.forward())
		sim.step([input])
		for r: int in sim.robots.size():
			var robot: RobotState = sim.robots[r]
			var turned: float = facings[r].angle_to(robot.forward())
			if turned > robot.max_turn_per_tick() + ANGLE_EPSILON:
				return "%s turned %s rad in one tick, limit %s" % [robot.def.id, turned, robot.max_turn_per_tick()]
	return ""


func test_hover_turns_to_face_without_moving() -> String:
	var sim: Sim = _sim_with("drone", Vector3(0.0, 0.0, -30.0))
	var robot: RobotState = sim.robots[0]
	for i: int in 180:
		sim.step(_still())
	if robot.position != Vector3(0.0, 0.0, -30.0):
		return "hovering drone moved to %s" % robot.position
	var to_ship: Vector3 = (sim.ships[0].position - robot.position).normalized()
	if robot.forward().angle_to(to_ship) > ANGLE_EPSILON:
		return "drone faces %s, ship is towards %s" % [robot.forward(), to_ship]
	return ""


func test_no_live_ship_means_hover_without_turning() -> String:
	var sim: Sim = _sim_with("needler", Vector3(0.0, 0.0, -40.0))
	sim.ships[0].hull = 0.0
	var start: Basis = sim.robots[0].orientation
	for i: int in 120:
		sim.step(_still())
	if sim.robots[0].position != Vector3(0.0, 0.0, -40.0) or sim.robots[0].orientation != start:
		return "needler moved or turned with no live ship"
	return ""


func test_target_is_nearest_live_ship_lower_index_on_tie() -> String:
	var sim: Sim = Sim.new(5, 3)
	sim.ships[0].position = Vector3(10.0, 0.0, 0.0)
	sim.ships[1].position = Vector3(-10.0, 0.0, 0.0)
	sim.ships[2].position = Vector3(0.0, 0.0, 5.0)
	if sim.nearest_live_ship(Vector3.ZERO) != sim.ships[2]:
		return "nearest ship not chosen"
	sim.ships[2].hull = 0.0
	if sim.nearest_live_ship(Vector3.ZERO) != sim.ships[0]:
		return "tie did not go to the lower index"
	for ship: ShipState in sim.ships:
		ship.hull = 0.0
	if sim.nearest_live_ship(Vector3.ZERO) != null:
		return "a destroyed ship was targeted"
	return ""


func test_identical_sims_hash_the_same_every_tick() -> String:
	var sims: Array[Sim] = []
	for n: int in 2:
		var sim: Sim = Sim.new(9, 2, BoxBounds.new(Vector3(-30.0, -30.0, -60.0), Vector3(30.0, 30.0, 30.0)))
		sim.ships[1].position = Vector3(8.0, 0.0, 0.0)
		for id: String in ["drone", "hauler", "glider", "needler", "skimmer", "warden"]:
			sim.spawn_robot(_def(id), Vector3(float(sim.robots.size()) * 4.0 - 10.0, 2.0, -35.0), Basis.IDENTITY)
		sims.append(sim)
	var inputs: Array[ShipInput] = [
		ShipInput.new(Vector3i(200, 0, -900), Vector3i(0, 300, 0)),
		ShipInput.new(Vector3i(-400, 100, -500), Vector3i(100, -200, 50)),
	]
	for i: int in 600:
		sims[0].step(inputs)
		sims[1].step(inputs)
		if sims[0].state_hash() != sims[1].state_hash():
			return "hashes differ at tick %d" % sims[0].tick
	return ""
