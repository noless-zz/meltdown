class_name BotPilot
extends ShipInputSource

## Flies one ship of a `Sim` against its robots: turns to the nearest live
## robot, holds an engagement distance and fires when the robot is in range
## and in front of the nose (CMB-3, PLT-4). Used to check automatically that
## a level can be beaten (gate G2) without a person flying it.
##
## It only reads the simulation and answers with a `ShipInput`, exactly what a
## pilot's controllers would give, so the server stays the only writer of
## state (MP-2). No randomness and no clock: the same sim gives the same input
## (ARC-1, ARC-2).

## Distance to the target the bot tries to hold, metres. Far enough that a
## robot's shots take a moment to arrive, close enough that every shipped
## primary weapon reaches.
const ENGAGE_DISTANCE: float = 15.0
## The bot holds fire unless the target is within this angle of the nose,
## degrees. Shots leave straight ahead, so a wide cone would waste energy.
const FIRE_CONE_HALF_ANGLE_DEG: float = 5.0
## Turn rates the bot asks for at most, radians per second. Equal to the
## thumbstick mapping's limits (`ThumbstickMapping.MAX_PITCH_RATE` and
## `MAX_YAW_RATE`, tested), so the bot flies no faster than a pilot can. `net/`
## may not depend on `xr/`, so the values are repeated here.
const MAX_PITCH_RATE: float = PI / 2.0
const MAX_YAW_RATE: float = PI / 2.0
## Turn rate asked for per radian off the target, per second. Below the tick
## rate, so a turn never overshoots within one tick; this value settles a
## small error in about half a second.
const TURN_GAIN: float = 6.0
## Closing speed wanted per metre away from `ENGAGE_DISTANCE`, per second.
const CLOSING_GAIN: float = 1.0
## Thrust per metre per second of closing speed still missing: full thrust
## once the error reaches 4 m/s.
const THRUST_GAIN: float = 0.25

var _sim: Sim = null
var _ship_index: int = 0


func _init(sim: Sim, ship_index: int = 0) -> void:
	_sim = sim
	_ship_index = ship_index


## Reads the sim as it stands before tick `tick` and returns the input to fly.
func next_input(_tick: int) -> ShipInput:
	if _sim == null or _ship_index < 0 or _ship_index >= _sim.ships.size():
		return ShipInput.new()
	var ship: ShipState = _sim.ships[_ship_index]
	var target: RobotState = nearest_robot(ship.position)
	if target == null:
		return ShipInput.new()
	var offset: Vector3 = target.position - ship.position
	var distance: float = offset.length()
	# Ship space: x right, y up, forward is -z. The basis is orthonormal, so
	# its transpose is its inverse.
	var local: Vector3 = ship.orientation.transposed() * offset
	# Positive pitch raises the nose and positive yaw turns it left (see
	# `ShipState.step`). Straight behind, atan2 gives a full half turn, so
	# the bot turns at its full rate rather than stalling.
	var pitch_error: float = atan2(local.y, -local.z)
	var yaw_error: float = atan2(-local.x, -local.z)
	var turn: Vector3 = Vector3(
		clampf(pitch_error * TURN_GAIN, -MAX_PITCH_RATE, MAX_PITCH_RATE),
		clampf(yaw_error * TURN_GAIN, -MAX_YAW_RATE, MAX_YAW_RATE),
		0.0)
	var thrust: Vector3 = Vector3.ZERO
	if distance > 0.0:
		var to_target: Vector3 = offset / distance
		var closing: float = ship.velocity.dot(to_target)
		var wanted: float = (distance - ENGAGE_DISTANCE) * CLOSING_GAIN
		var push: float = clampf((wanted - closing) * THRUST_GAIN, -1.0, 1.0)
		thrust = local / distance * push
	var input: ShipInput = ShipInput.from_floats(thrust, turn)
	input.fire_primary = should_fire(ship, offset)
	return input


## The live robot nearest to `point`, or null when there is none. Only a
## strictly nearer robot replaces the best, so ties go to the lower index.
func nearest_robot(point: Vector3) -> RobotState:
	var best: RobotState = null
	var best_distance: float = INF
	for robot: RobotState in _sim.robots:
		if not robot.is_alive():
			continue
		var d: float = point.distance_squared_to(robot.position)
		if d < best_distance:
			best = robot
			best_distance = d
	return best


## Whether `ship` should hold fire at a target `offset` away: within its
## selected primary weapon's range and within the cone ahead of its nose. An
## empty slot has no range, so an unarmed ship never fires.
static func should_fire(ship: ShipState, offset: Vector3) -> bool:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null:
		return false
	var weapon_range: float = weapon.projectile_speed * float(weapon.lifetime_ticks()) \
		* ShipState.TICK_DT
	var distance: float = offset.length()
	if distance > weapon_range:
		return false
	if distance == 0.0:
		return true
	var nose: Vector3 = -ship.orientation.z.normalized()
	return nose.angle_to(offset) <= deg_to_rad(FIRE_CONE_HALF_ANGLE_DEG)
