class_name RobotSteering
extends RefCounted

## How a robot moves on the fixed tick: turning, chasing, strafing, hovering
## and staying inside its walls (CMB-3). Split out of `RobotState` (#1155) so
## the movement and the firing can each grow without the other's file passing
## the size limit. Static functions on the robot's own fields: no state lives
## here, so `RobotState.state_hash` and every pinned replay are unchanged
## (ARC-1, ARC-2). The numbers come from `robot.def`, a data file (ARC-4).


## Moves one tick according to `def.movement`, towards or around `target`,
## the ship `Sim` chose for it. With no target every movement is hover and the
## robot does not turn: there is nothing to face.
static func step(robot: RobotState, target: ShipState) -> void:
	if target == null:
		hover(robot)
		return
	var offset: Vector3 = target.position - robot.position
	var distance: float = offset.length()
	# A target exactly on the centre gives no direction; keep the facing.
	var to_target: Vector3 = offset / distance if distance > 0.0 else robot.forward()
	turn_towards(robot, to_target)
	match robot.def.movement:
		"chase":
			chase(robot, to_target, distance, chase_standoff(robot, target))
		"strafe":
			strafe(robot, to_target, distance)
		_:
			hover(robot)


## Largest turn in one tick, radians.
static func max_turn_per_tick(robot: RobotState) -> float:
	return deg_to_rad(robot.def.turn_rate) * ShipState.TICK_DT


## Distance from the target's centre a chaser holds.
static func chase_standoff(robot: RobotState, target: ShipState) -> float:
	return robot.def.standoff_radii * robot.def.radius + target.radius


## Turns the facing towards `direction` (unit length) by at most
## `max_turn_per_tick`. The rotation is about the axis perpendicular to both,
## so the facing moves by exactly the turned angle and no roll is added.
static func turn_towards(robot: RobotState, direction: Vector3) -> void:
	var facing: Vector3 = robot.forward()
	var angle: float = StableAngle.between(facing, direction)
	if angle <= 0.0:
		return
	var axis: Vector3 = facing.cross(direction)
	if axis.length_squared() < 1e-12:
		# Exactly behind: any perpendicular axis will do; the robot's own up
		# keeps the choice deterministic.
		axis = robot.orientation.y
	var turn: float = minf(angle, max_turn_per_tick(robot))
	robot.orientation = Basis(axis.normalized(), turn) * robot.orientation
	robot.orientation = robot.orientation.orthonormalized()


## Closes on the target along the facing, slowing so that it can stop at
## `standoff` with its own acceleration; inside the stand-off it backs away.
## The approach is scaled by how well it faces the target, so a chaser still
## turning does not fly off sideways.
static func chase(robot: RobotState, to_target: Vector3, distance: float,
		standoff: float) -> void:
	var gap: float = distance - standoff
	var desired: Vector3 = Vector3.ZERO
	if gap > 0.0:
		var alignment: float = maxf(robot.forward().dot(to_target), 0.0)
		desired = robot.forward() * stopping_speed(robot, gap) * alignment
	elif gap < 0.0:
		desired = -to_target * stopping_speed(robot, -gap)
	steer(robot, desired)


## Circles the target sideways in `strafe_direction`, about the world vertical
## (or the world x axis when straight above or below it), drifting back to the
## middle of the distance band.
static func strafe(robot: RobotState, to_target: Vector3, distance: float) -> void:
	var def: RobotDef = robot.def
	var axis: Vector3 = Vector3.UP
	if absf(to_target.dot(axis)) > 0.99:
		axis = Vector3.RIGHT
	var sideways: Vector3 = to_target.cross(axis).normalized() * float(robot.strafe_direction)
	var middle: float = (def.strafe_min_distance + def.strafe_max_distance) * 0.5
	var radial: float = clampf((distance - middle) * def.strafe_radial_gain,
		-def.max_speed, def.max_speed)
	# Outside the band, getting back in comes first.
	if distance < def.strafe_min_distance or distance > def.strafe_max_distance:
		radial = signf(radial) * def.max_speed
	steer(robot, (sideways * def.max_speed + to_target * radial).limit_length(def.max_speed))


## Fastest speed from which `def.acceleration` still stops within `gap`
## metres, capped at `def.max_speed`. One tick of margin keeps the discrete
## tick from overshooting.
static func stopping_speed(robot: RobotState, gap: float) -> float:
	var a: float = robot.def.acceleration
	var speed: float = sqrt(2.0 * a * gap + a * a * ShipState.TICK_DT * ShipState.TICK_DT) \
		- a * ShipState.TICK_DT
	return minf(maxf(speed, 0.0), robot.def.max_speed)


## Changes velocity towards `desired` by at most `def.acceleration` this tick,
## caps it at `def.max_speed` and moves.
static func steer(robot: RobotState, desired: Vector3) -> void:
	var change: Vector3 = (desired - robot.velocity).limit_length(
		robot.def.acceleration * ShipState.TICK_DT)
	robot.velocity = (robot.velocity + change).limit_length(robot.def.max_speed)
	robot.position += robot.velocity * ShipState.TICK_DT


## Holds position: any velocity is braked towards zero at `def.acceleration`,
## never past it, and capped at `def.max_speed`.
static func hover(robot: RobotState) -> void:
	var brake: float = robot.def.acceleration * ShipState.TICK_DT
	var speed: float = robot.velocity.length()
	if speed <= brake:
		robot.velocity = Vector3.ZERO
	else:
		robot.velocity = robot.velocity * ((speed - brake) / speed)
	robot.velocity = robot.velocity.limit_length(robot.def.max_speed)
	robot.position += robot.velocity * ShipState.TICK_DT


## Keeps the robot's sphere inside `bounds`. Robots do not bounce or take wall
## damage like ships: on each axis where it crossed a wall it is placed back on
## the wall and its velocity into that wall is removed. A box narrower than the
## robot holds it on the centre line, as `BoxBounds.contain_impact` does ships.
static func keep_inside(robot: RobotState, bounds: BoxBounds) -> void:
	var radius: float = robot.def.radius
	for axis: int in 3:
		var low: float = bounds.min_corner[axis] + radius
		var high: float = bounds.max_corner[axis] - radius
		if low > high:
			low = (bounds.min_corner[axis] + bounds.max_corner[axis]) * 0.5
			high = low
		if robot.position[axis] < low:
			robot.position[axis] = low
			robot.velocity[axis] = maxf(robot.velocity[axis], 0.0)
		elif robot.position[axis] > high:
			robot.position[axis] = high
			robot.velocity[axis] = minf(robot.velocity[axis], 0.0)
