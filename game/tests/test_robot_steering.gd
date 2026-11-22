extends RefCounted

## `RobotSteering` driven directly, without `Sim`: a chasing robot turns no
## faster than its limit and stays inside its walls (CMB-3, ARC-1, #1155).

const ROBOTS_DIR: String = "res://data/robots"
## Slack on angle checks, radians: orthonormalising the basis each tick moves
## the facing by far less than this.
const ANGLE_EPSILON: float = 1e-4


func _def(id: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s.json" % [ROBOTS_DIR, id]))


func test_chaser_turns_within_limit_and_stays_inside_bounds() -> String:
	for id: String in ["hauler", "needler"]:
		var def: RobotDef = _def(id)
		if def.movement != "chase":
			return "%s is no longer a chaser; pick another robot" % id
		# Faces +z, away from a target that sits behind it and beyond a wall,
		# so it must turn the long way round and is pushed into the box face.
		var robot: RobotState = RobotState.new(def, Vector3.ZERO, Basis(Vector3.UP, PI))
		var target: ShipState = ShipState.new()
		target.position = Vector3(3.0, 1.0, -30.0)
		var bounds: BoxBounds = BoxBounds.new(Vector3(-6.0, -4.0, -10.0), Vector3(6.0, 4.0, 10.0))
		var limit: float = RobotSteering.max_turn_per_tick(robot)
		if limit <= 0.0:
			return "%s has no turn rate" % id
		var reached_wall: bool = false
		for tick: int in 600:
			var before: Vector3 = robot.forward()
			RobotSteering.step(robot, target)
			RobotSteering.keep_inside(robot, bounds)
			var turned: float = StableAngle.between(before, robot.forward())
			if turned > limit + ANGLE_EPSILON:
				return "%s turned %s rad at tick %d, limit %s" % [id, turned, tick, limit]
			for axis: int in 3:
				var low: float = bounds.min_corner[axis] + def.radius
				var high: float = bounds.max_corner[axis] - def.radius
				if robot.position[axis] < low - 1e-5 or robot.position[axis] > high + 1e-5:
					return "%s left its bounds on axis %d at tick %d: %s" % [id, axis, tick, robot.position]
			if robot.position.z <= bounds.min_corner.z + def.radius + 1e-5:
				reached_wall = true
		if not reached_wall:
			return "%s never reached the wall towards its target" % id
		var facing_error: float = StableAngle.between(robot.forward(),
			(target.position - robot.position).normalized())
		if facing_error > 0.05:
			return "%s still faces %s rad off its target after 600 ticks" % [id, facing_error]
	return ""


func test_robot_state_delegates_give_the_same_result() -> String:
	var def: RobotDef = _def("needler")
	var target: ShipState = ShipState.new()
	target.position = Vector3(5.0, -2.0, -20.0)
	var via_state: RobotState = RobotState.new(def, Vector3(1.0, 0.0, 0.0), Basis(Vector3.UP, 0.7))
	var direct: RobotState = RobotState.new(def, Vector3(1.0, 0.0, 0.0), Basis(Vector3.UP, 0.7))
	var bounds: BoxBounds = BoxBounds.new(Vector3(-8.0, -8.0, -30.0), Vector3(8.0, 8.0, 8.0))
	for tick: int in 240:
		via_state.step(target)
		via_state.keep_inside(bounds)
		RobotSteering.step(direct, target)
		RobotSteering.keep_inside(direct, bounds)
		if via_state.state_hash() != direct.state_hash():
			return "RobotState.step and RobotSteering.step differ at tick %d" % tick
	if via_state.chase_standoff(target) != RobotSteering.chase_standoff(direct, target):
		return "chase_standoff differs"
	return ""
