class_name AcceptanceResetCheck
extends RefCounted

## The `at_start` acceptance check (#776, FLT-1, CMF-8, umbrella #153): re-flies
## a replay tick by tick and passes when ship 0 ends where the level started it,
## facing the way it started, at rest and alive. It also measures how far from
## the start the ship was on the tick before the first `reset_to_start`, so a
## report shows the reset brought it back from somewhere. The final state alone
## cannot tell the spin or the pose before the reset, so like
## `AcceptanceWallCheck` this flies the replay again; the hash check pins the
## flight itself. Kept apart from `AcceptanceStateChecks` for that file's size.

## Metres: 1 mm, as the issue asks.
const MAX_DISTANCE_M: float = 0.001
## Degrees, as the issue asks.
const MAX_ANGLE_DEG: float = 0.1
## Metres per second below which the ship counts as at rest.
const MAX_SPEED: float = 0.001
## Degrees per second, measured over the last tick, below which the ship
## counts as not turning.
const MAX_SPIN_DEG: float = 0.01


## [result, message] for `replay`, adding its measurements.
static func run(replay: Replay, measurements: Dictionary) -> Array:
	# `Replay.run` with no frames is the sim set up from the header, before its
	# first tick; the frames are put back at once and stepped here.
	var frames: Array[Array] = replay.frames
	replay.frames = []
	var sim: Sim = replay.run()
	replay.frames = frames
	if sim == null:
		return [AcceptanceReport.RESULT_FAIL, "the replay could not start: %s" % replay.run_error]
	if sim.ships.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "the replay has no ship"]
	var ship: ShipState = sim.ships[0]
	var resets: int = 0
	var before_distance: float = -1.0
	var before_angle: float = -1.0
	var last_orientation: Basis = ship.orientation
	for frame: Array in frames:
		var inputs: Array[ShipInput] = []
		inputs.assign(frame)
		if inputs[0].reset_to_start:
			if resets == 0:
				before_distance = distance_from_start(sim)
				before_angle = angle_from_start(sim)
			resets += 1
		last_orientation = ship.orientation
		sim.step(inputs)
	var distance: float = distance_from_start(sim)
	var angle: float = angle_from_start(sim)
	var speed: float = ship.velocity.length()
	var spin: float = angle_between(last_orientation, ship.orientation) * ShipState.TICK_RATE
	measurements["reset_ticks"] = resets
	measurements["distance_before_reset"] = snappedf(before_distance, 0.001)
	measurements["angle_before_reset"] = snappedf(before_angle, 0.01)
	measurements["distance_after"] = snappedf(distance, 0.0001)
	measurements["angle_after"] = snappedf(angle, 0.0001)
	measurements["speed_after"] = snappedf(speed, 0.0001)
	measurements["spin_after"] = snappedf(spin, 0.0001)
	if ship.is_destroyed():
		return [AcceptanceReport.RESULT_FAIL, "the ship is destroyed"]
	if distance > MAX_DISTANCE_M:
		return [AcceptanceReport.RESULT_FAIL, "the ship ended %.3f m from the start" % distance]
	if angle > MAX_ANGLE_DEG:
		return [AcceptanceReport.RESULT_FAIL, "the ship ended turned %.2f degrees from the start" % angle]
	if speed > MAX_SPEED:
		return [AcceptanceReport.RESULT_FAIL, "the ship ended moving at %.4f m/s" % speed]
	if spin > MAX_SPIN_DEG:
		return [AcceptanceReport.RESULT_FAIL, "the ship ended turning at %.4f degrees per second" % spin]
	if resets == 0:
		return [AcceptanceReport.RESULT_FAIL, "the replay never asked for a reset"]
	return [AcceptanceReport.RESULT_PASS, "back at the start from %.2f m and %.1f degrees away; at rest" % [
		before_distance, before_angle]]


static func distance_from_start(sim: Sim) -> float:
	return sim.ships[0].position.distance_to(sim.start_positions[0])


## Degrees between ship 0's orientation and its start orientation.
static func angle_from_start(sim: Sim) -> float:
	return angle_between(sim.ships[0].orientation, sim.start_orientations[0])


## Degrees of the smallest rotation taking `a` to `b`.
static func angle_between(a: Basis, b: Basis) -> float:
	var qa: Quaternion = a.orthonormalized().get_rotation_quaternion()
	var qb: Quaternion = b.orthonormalized().get_rotation_quaternion()
	return rad_to_deg(qa.angle_to(qb))
