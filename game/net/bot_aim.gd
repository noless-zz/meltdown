class_name BotAim
extends RefCounted

## The bot pilot's aiming (CMB-3, PLT-4): where to point the nose and when a
## shot is worth firing. Split out of `BotPilot` when it reached its size
## limit (#492); `BotPilot` keeps thin wrappers so its callers are unchanged.
##
## Pure functions of the ship and its target as they stand: no state, no
## randomness and no clock, so the same flight gives the same inputs (ARC-1,
## ARC-2). Only reads the sim (MP-2).

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
## Choosing a target, this many metres nearer weigh as much as a radian less
## to turn the nose.
const METRES_PER_RADIAN: float = 30.0


## Where `target` will be when a shot fired now reaches it, if it keeps its
## velocity: the shot's flight time is taken over the present distance.
static func lead_point(ship: ShipState, target: RobotState) -> Vector3:
	var weapon: WeaponDef = ship.primary_slots[ship.selected_primary]
	if weapon == null or weapon.projectile_speed <= 0.0:
		return target.position
	var flight: float = ship.position.distance_to(target.position) / weapon.projectile_speed
	return target.position + target.velocity * flight


## Turn rates that bring the nose to `local`, a direction in ship space,
## within the caps.
static func turn_towards(local: Vector3) -> Vector3:
	return _capped(_errors(local) * TURN_GAIN)


## Turn rates that keep the nose on `target`'s lead point while it moves
## (#492). `turn_towards` alone lags a robot that crosses the nose: a strafer
## circling at 18 m/s 20 m away moves about 0.9 rad/s, and the turn gain then
## leaves the nose some 9 degrees behind, outside the fire cone, so the bot
## never fired at it. The rate at which the lead point moves across the nose,
## from both velocities over one tick, is added to the correction.
static func track(ship: ShipState, target: RobotState) -> Vector3:
	var basis_inverse: Basis = ship.orientation.transposed()
	var lead: Vector3 = lead_point(ship, target)
	var now: Vector3 = _errors(basis_inverse * (lead - ship.position))
	var dt: float = ShipState.TICK_DT
	var ahead: Vector3 = (lead + target.velocity * dt) - (ship.position + ship.velocity * dt)
	var drift: Vector3 = _errors(basis_inverse * ahead) - now
	# A target straight behind flips between plus and minus a half turn.
	drift = Vector3(wrapf(drift.x, -PI, PI), wrapf(drift.y, -PI, PI), 0.0)
	return _capped(now * TURN_GAIN + drift / dt)


## How dear `target` is to shoot at from `ship`: the angle the nose must turn
## to its lead point, radians, plus its distance over `METRES_PER_RADIAN`.
## Answering the nearest robot first (#334) left the nose chasing a strafer
## it could not catch while robots ahead of it fired freely (#492).
static func cost(ship: ShipState, target: RobotState) -> float:
	var offset: Vector3 = lead_point(ship, target) - ship.position
	var nose: Vector3 = -ship.orientation.z.normalized()
	var angle: float = StableAngle.between(nose, offset) if offset != Vector3.ZERO else 0.0
	return angle + offset.length() / METRES_PER_RADIAN


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
	return StableAngle.between(nose, offset) <= deg_to_rad(FIRE_CONE_HALF_ANGLE_DEG)


## Pitch and yaw errors, radians, to bring the nose to `local`, a direction in
## ship space. Positive pitch raises the nose and positive yaw turns it left
## (see `ShipState.step`). Straight behind, atan2 gives a full half turn, so
## the bot turns at its full rate rather than stalling.
static func _errors(local: Vector3) -> Vector3:
	return Vector3(atan2(local.y, -local.z), atan2(-local.x, -local.z), 0.0)


static func _capped(rates: Vector3) -> Vector3:
	return Vector3(clampf(rates.x, -MAX_PITCH_RATE, MAX_PITCH_RATE),
		clampf(rates.y, -MAX_YAW_RATE, MAX_YAW_RATE), 0.0)
