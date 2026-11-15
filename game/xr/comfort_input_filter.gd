class_name ComfortInputFilter
extends RefCounted

## Applies one player's comfort preset to that player's turn input before it
## is sent to the simulation (CMF-1, CMF-3, ARC-3).
##
## Snap turning is a one-tick turn of the ship rather than a jump of the view:
## the view then only ever moves with the ship's simulated motion (CMF-8), and
## the core sees an ordinary input it treats like every other player's
## (CMF-6). Thrust and the afterburner always pass through unchanged, so a
## preset never alters speed.
##
## A snap axis fires once when its rate passes half the mapping's full rate,
## then stays at zero until the rate falls below a quarter of it. The gap
## between the two thresholds keeps a stick held near the trigger point from
## firing a burst of snaps.
##
## Smooth yaw and pitch are capped to the preset's rates. A pitch limit is
## kept by predicting this tick's turn on a throwaway `ShipState` that only
## copies the ship's orientation: the prediction runs the same rotation code
## as the simulation, and the real ship is never touched.

## Fraction of full rate that fires a snap.
const SNAP_FIRE_FRACTION: float = 0.5
## Fraction of full rate the stick must fall below before the next snap.
const SNAP_REARM_FRACTION: float = 0.25
## Radians of rounding allowed at the pitch limit, so that a 30 degree snap
## from 30 degrees still reaches a 60 degree limit.
const LIMIT_EPSILON: float = 0.0001

var preset: ComfortPreset
## Per snap axis: true while the stick has been released since the last snap.
var _pitch_armed: bool = true
var _yaw_armed: bool = true


func _init(p_preset: ComfortPreset) -> void:
	preset = p_preset


## Turn rate in milliradians per second that turns exactly `snap_angle_deg`
## in one simulation tick, as stored in `ShipInput.turn_q`.
func snap_rate_q() -> int:
	return roundi(deg_to_rad(preset.snap_angle_deg) / ShipState.TICK_DT * ShipInput.SCALE)


## Angle of the nose above (positive) or below the horizontal plane, in
## radians. The nose is the basis's -z axis.
static func nose_elevation(orientation: Basis) -> float:
	return asin(clampf(-orientation.z.normalized().y, -1.0, 1.0))


## A rate cap in degrees per second as milliradians per second, or -1 for none.
static func cap_q(cap_deg_per_s: float) -> int:
	if cap_deg_per_s == ComfortPreset.NO_LIMIT:
		return -1
	return roundi(deg_to_rad(cap_deg_per_s) * ShipInput.SCALE)


## Returns the input to simulate for this tick. Call once per tick, in order:
## the filter remembers whether each snap axis has been released.
## `orientation` is the ship's current orientation, read only; it matters only
## when the preset has a pitch limit, and callers of such a preset must pass it.
func filter(input: ShipInput, orientation: Basis = Basis.IDENTITY) -> ShipInput:
	var turn: Vector3i = input.turn_q
	var pitch_snapped: bool = preset.pitch_mode == ComfortPreset.PitchMode.SNAP
	if pitch_snapped:
		var pitch: Array = _snap(turn.x, ThumbstickMapping.MAX_PITCH_RATE, _pitch_armed)
		turn.x = int(pitch[0])
		_pitch_armed = bool(pitch[1])
	else:
		turn.x = _cap(turn.x, preset.pitch_rate_cap_deg_per_s)
	if preset.yaw_mode == ComfortPreset.YawMode.SNAP:
		var yaw: Array = _snap(turn.y, ThumbstickMapping.MAX_YAW_RATE, _yaw_armed)
		turn.y = int(yaw[0])
		_yaw_armed = bool(yaw[1])
	else:
		turn.y = _cap(turn.y, preset.yaw_rate_cap_deg_per_s)
	if preset.roll_mode == ComfortPreset.RollMode.OFF_AUTO_LEVEL:
		turn.z = 0
	if preset.pitch_limit_deg != ComfortPreset.NO_LIMIT and turn.x != 0:
		turn.x = _limit_pitch(turn, orientation, pitch_snapped)
	return ShipInput.new(input.thrust_q, turn, input.afterburner)


func _cap(rate_q: int, cap_deg_per_s: float) -> int:
	var cap: int = cap_q(cap_deg_per_s)
	if cap < 0:
		return rate_q
	return clampi(rate_q, -cap, cap)


## Returns the pitch rate to keep so that pitch never carries the nose past
## the limit. Pitch that brings the nose back towards the horizon always
## passes, so a ship already past the limit (for instance after a bounce) can
## recover. A snap is all or nothing: half a snap would be a smaller,
## surprising turn. A smooth rate is scaled down to end the tick at the limit.
## A snap dropped here still counts as fired, so it cannot go off later while
## the stick is held.
func _limit_pitch(turn: Vector3i, orientation: Basis, snapped: bool) -> int:
	var limit: float = deg_to_rad(preset.pitch_limit_deg)
	var without: Basis = _turned(orientation, Vector3i(0, turn.y, turn.z))
	if _pitch_allowed(turn, orientation, without, limit):
		return turn.x
	if snapped:
		return 0
	var base: float = nose_elevation(without)
	var full: float = nose_elevation(_turned(orientation, turn))
	if is_equal_approx(full, base):
		return 0
	var target: float = limit * signf(full)
	var fraction: float = clampf((target - base) / (full - base), 0.0, 1.0)
	var scaled: Vector3i = Vector3i(int(turn.x * fraction), turn.y, turn.z)
	if _pitch_allowed(scaled, orientation, without, limit):
		return scaled.x
	return 0


## True when `turn` leaves the nose within the limit, or at least no further
## from the horizon than the same turn without pitch would. A pitch that
## carries the nose over the vertical (its heading flips) is never allowed:
## its elevation can look smaller while the ship has in fact looped.
func _pitch_allowed(turn: Vector3i, orientation: Basis, without: Basis, limit: float) -> bool:
	var turned: Basis = _turned(orientation, turn)
	var after: float = absf(nose_elevation(turned))
	if after <= limit + LIMIT_EPSILON:
		return true
	var heading_before: Vector3 = Vector3(-without.z.x, 0.0, -without.z.z)
	var heading_after: Vector3 = Vector3(-turned.z.x, 0.0, -turned.z.z)
	if heading_before.dot(heading_after) < 0.0:
		return false
	return after < absf(nose_elevation(without)) - LIMIT_EPSILON


## Orientation after one tick of `turn`, worked out on a throwaway ship.
static func _turned(orientation: Basis, turn_q: Vector3i) -> Basis:
	var probe: ShipState = ShipState.new()
	probe.orientation = orientation
	probe.step(Vector3.ZERO, ShipInput.new(Vector3i.ZERO, turn_q).turn())
	return probe.orientation


## Returns [filtered rate in milliradians per second, armed after this tick].
func _snap(rate_q: int, full_rate: float, armed: bool) -> Array:
	var magnitude: float = absf(float(rate_q)) / ShipInput.SCALE
	if armed and magnitude > full_rate * SNAP_FIRE_FRACTION:
		return [snap_rate_q() * signi(rate_q), false]
	if not armed and magnitude < full_rate * SNAP_REARM_FRACTION:
		return [0, true]
	return [0, armed]
