class_name GrippedStickMapping
extends RefCounted

## The gripped virtual stick and throttle control scheme (PLT-5) as a pure
## mapping from hand poses to one tick's `ShipInput` (FLT-1).
##
## Like `ThumbstickMapping` it reads no input device and no node: the caller
## passes each hand's pose relative to the point where that hand grabbed its
## control, so the mapping can be tested without a headset. Comfort filtering
## is not done here (ARC-3); grabbing, the visible stick and throttle models
## and choosing the scheme belong to the caller.
##
## Each pose is a `Transform3D` in the grab point's frame, which uses the
## player's axes (x right, y up, -z ahead, as OpenXR reports them):
## `origin` is how far the hand has moved from the grab point in metres, and
## `basis` is how it has turned since the grab. The identity is the centre.
##
## Default right-handed layout:
## - right hand, the stick (rotation only): tilting the top ahead pitches the
##   nose down and back pitches it up, as on an aircraft stick; tilting right
##   rolls right; twisting clockwise seen from above yaws right
## - left hand, the throttle (position only): pushing ahead gives forward
##   thrust and pulling back reverse thrust, moving right strafes right and
##   moving up lifts
## - the lower face button on the throttle hand (X on a left Quest
##   controller) holds the afterburner (FLT-2)
## - a hand does nothing unless its grip is held; releasing the grip lets go
##   of that control, which then reads as centred
##
## Axis names and signs match `ThumbstickMapping`: `strafe` (+ right),
## `lift` (+ up), `forward` (+ ahead), `pitch` (+ nose up), `yaw` (+ nose
## right), `roll` (+ right wing down), each -1..1 before scaling. Both schemes
## turn at the same full rates, so switching scheme does not change how fast
## the ship can turn.
##
## Left-handed mode swaps the hands: the left hand holds the stick, the right
## hand the throttle, and the afterburner moves to the right hand's lower face
## button (A).

## A grip pulled at least this far holds the control. Half way, as for the
## buttons of `ThumbstickMapping`.
const GRIP_HOLD_THRESHOLD: float = 0.5

## Stick tilt, ahead/back and left/right, in radians. A wrist rests a few
## degrees off its grab angle without meaning to, so that gives exactly zero.
const STICK_TILT_DEAD_ZONE_RAD: float = deg_to_rad(4.0)
## Tilt that gives full pitch or roll. Small enough to reach without bending
## the wrist uncomfortably, large enough for fine control near the centre.
const STICK_TILT_FULL_RAD: float = deg_to_rad(30.0)
## Twist about the stick's own axis, in radians. A wrist twists less easily
## than it tilts, so the twist range is narrower.
const STICK_TWIST_DEAD_ZONE_RAD: float = deg_to_rad(5.0)
const STICK_TWIST_FULL_RAD: float = deg_to_rad(25.0)

## Throttle travel from the grab point along each axis, in metres.
const THROTTLE_DEAD_ZONE_M: float = 0.02
const THROTTLE_FULL_M: float = 0.10

const MAX_PITCH_RATE: float = ThumbstickMapping.MAX_PITCH_RATE
const MAX_YAW_RATE: float = ThumbstickMapping.MAX_YAW_RATE
const MAX_ROLL_RATE: float = ThumbstickMapping.MAX_ROLL_RATE

const AXES: Array[String] = ["strafe", "lift", "forward", "pitch", "yaw", "roll"]
## The buttons passed in the `buttons` argument of `map_controls`, named by
## position as in `ThumbstickMapping.BUTTONS`.
const BUTTONS: Array[String] = ThumbstickMapping.BUTTONS
## The afterburner button in the right-handed layout. Left-handed mode moves
## it to the same button on the right hand, which then holds the throttle.
const AFTERBURNER_BUTTON: String = "left_button_lower"
const AFTERBURNER_BUTTON_LEFT_HANDED: String = "right_button_lower"

var left_handed: bool = false
var invert_pitch: bool = false


## Scales a signed reading so that the dead zone gives exactly zero and the
## output rises from zero at its edge to 1 at `full`, keeping the sign.
static func apply_dead_zone(value: float, dead_zone: float, full: float) -> float:
	var size: float = absf(value)
	if size <= dead_zone or is_equal_approx(size, dead_zone):
		return 0.0
	return signf(value) * clampf((size - dead_zone) / (full - dead_zone), 0.0, 1.0)


## Stick angles of a hand rotation relative to its grab rotation, in radians:
## x the tilt of the top to the right, y the twist clockwise seen from above,
## z the tilt of the top ahead.
static func stick_angles(rotation: Basis) -> Vector3:
	var q: Quaternion = rotation.orthonormalized().get_rotation_quaternion()
	# q and -q are the same rotation; pick the one whose twist is within +-PI.
	if q.w < 0.0:
		q = -q
	# The top of the stick follows the hand's up axis. A twist about that axis
	# does not move it, so tilt and twist stay independent.
	var top: Vector3 = q * Vector3.UP
	var tilt_right: float = atan2(top.x, top.y)
	var tilt_ahead: float = atan2(-top.z, top.y)
	# Twist about y from the swing-twist split; positive about y turns
	# counter-clockwise seen from above, so it is negated.
	var twist_clockwise: float = -2.0 * atan2(q.y, q.w)
	return Vector3(tilt_right, twist_clockwise, tilt_ahead)


## The six axes, each -1..1, for one frame of hand poses and grips.
func axes(left_pose: Transform3D, right_pose: Transform3D,
		left_grip: float, right_grip: float) -> Dictionary:
	var stick_pose: Transform3D = left_pose if left_handed else right_pose
	var throttle_pose: Transform3D = right_pose if left_handed else left_pose
	var stick_grip: float = left_grip if left_handed else right_grip
	var throttle_grip: float = right_grip if left_handed else left_grip
	var result: Dictionary = {}
	for name: String in AXES:
		result[name] = 0.0
	if _held(stick_grip):
		var angles: Vector3 = stick_angles(stick_pose.basis)
		var ahead: float = apply_dead_zone(
			angles.z, STICK_TILT_DEAD_ZONE_RAD, STICK_TILT_FULL_RAD)
		# Stick ahead is nose down, as on an aircraft.
		result["pitch"] = ahead if invert_pitch else -ahead
		result["roll"] = apply_dead_zone(
			angles.x, STICK_TILT_DEAD_ZONE_RAD, STICK_TILT_FULL_RAD)
		result["yaw"] = apply_dead_zone(
			angles.y, STICK_TWIST_DEAD_ZONE_RAD, STICK_TWIST_FULL_RAD)
	if _held(throttle_grip):
		var offset: Vector3 = throttle_pose.origin
		result["strafe"] = apply_dead_zone(offset.x, THROTTLE_DEAD_ZONE_M, THROTTLE_FULL_M)
		result["lift"] = apply_dead_zone(offset.y, THROTTLE_DEAD_ZONE_M, THROTTLE_FULL_M)
		result["forward"] = apply_dead_zone(-offset.z, THROTTLE_DEAD_ZONE_M, THROTTLE_FULL_M)
	return result


## True when the afterburner button is pressed on the throttle hand and that
## hand's grip is held. `buttons` maps names from `BUTTONS` to pressed; a
## missing button counts as released.
func afterburner(left_grip: float, right_grip: float, buttons: Dictionary = {}) -> bool:
	var throttle_grip: float = right_grip if left_handed else left_grip
	var button: String = AFTERBURNER_BUTTON_LEFT_HANDED if left_handed else AFTERBURNER_BUTTON
	return _held(throttle_grip) and bool(buttons.get(button, false))


## Maps one frame of hand poses, grips (0..1) and buttons to the input for
## one tick.
func map_controls(left_pose: Transform3D, right_pose: Transform3D,
		left_grip: float, right_grip: float,
		buttons: Dictionary = {}) -> ShipInput:
	var axis: Dictionary = axes(left_pose, right_pose, left_grip, right_grip)
	# Ship space: z forward is negative; positive rotations about x, y and z
	# raise the nose, turn it left and lower the left wing.
	var thrust: Vector3 = Vector3(axis["strafe"], axis["lift"], -axis["forward"])
	var turn: Vector3 = Vector3(
		axis["pitch"] * MAX_PITCH_RATE,
		-axis["yaw"] * MAX_YAW_RATE,
		-axis["roll"] * MAX_ROLL_RATE)
	return ShipInput.from_floats(thrust, turn, afterburner(left_grip, right_grip, buttons))


static func _held(grip: float) -> bool:
	return grip >= GRIP_HOLD_THRESHOLD
