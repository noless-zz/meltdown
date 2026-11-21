class_name GrippedSampler
extends RefCounted

## Flies the gripped virtual stick and throttle (#739, PLT-5, FLT-1, FLT-2)
## from the values `ControllerSampler` reads, so it touches no device itself
## and writes no simulation state (MP-2). Its `ShipInput` goes through the same
## comfort filter as the thumbsticks' (ARC-3); that happens in the caller.
##
## Pulling a grip past `GrippedStickMapping.GRIP_HOLD_THRESHOLD` records the
## hand's pose as its grab point; each frame the hand's pose relative to that
## point goes to `GrippedStickMapping`, and letting go forgets the point, so
## the control reads as centred. A hand whose pose is missing (not tracked)
## lets go too, so a controller put down never keeps the ship moving.
##
## Relative poses are in the rig's axes, which `GrippedStickMapping` expects:
## the offset is `current.origin - grab.origin` and the turn is the rotation
## that takes the grab orientation to the current one, both in the rig frame,
## so the way the controller happens to point at the grab does not matter.
##
## Buttons, right-handed (left-handed mode swaps each with its twin):
## - afterburner on the throttle hand's upper face button, Y. X stays the
##   comfort preset button (decision record 0004, #613), and the upper button
##   is free in this scheme because lift comes from moving the throttle.
## - fire on the stick hand's trigger, as in the thumbsticks scheme.
## The menu-button reset, the preset and the label toggle are read by the
## caller from the same values, as for the thumbsticks.

## The afterburner, right-handed. The one place this scheme names it.
const AFTERBURNER_BUTTON: String = "left_button_upper"
const AFTERBURNER_BUTTON_LEFT_HANDED: String = "right_button_upper"

var mapping: GrippedStickMapping = GrippedStickMapping.new()
## Hand name -> the pose where that hand grabbed its control.
var _grabs: Dictionary = {}


## The pose of `current` relative to `grab`, in the rig's axes.
static func relative_pose(grab: Transform3D, current: Transform3D) -> Transform3D:
	var turn: Basis = current.basis.orthonormalized() * grab.basis.orthonormalized().inverse()
	return Transform3D(turn, current.origin - grab.origin)


## Whether `hand` ("left" or "right") holds its control.
func holds(hand: String) -> bool:
	return _grabs.has(hand)


## Lets go of both controls, as if both grips were released.
func release_all() -> void:
	_grabs.clear()


## The physical afterburner button for the current hand setting.
func afterburner_button() -> String:
	return AFTERBURNER_BUTTON_LEFT_HANDED if mapping.left_handed else AFTERBURNER_BUTTON


## Records or forgets each hand's grab point from this frame's values.
func update_grabs(values: Dictionary) -> void:
	var poses: Dictionary = values.get(ControllerSampler.POSES, {})
	for hand: String in ControllerSampler.HANDS:
		var grip: float = float(values.get(hand + "_grip", 0.0))
		if grip >= GrippedStickMapping.GRIP_HOLD_THRESHOLD and poses.has(hand):
			if not _grabs.has(hand):
				_grabs[hand] = poses[hand]
		else:
			_grabs.erase(hand)


## One tick's input from this frame's values. Hand settings follow
## `thumbsticks`, the game's one mapping, so left-handed mode and inverted
## pitch apply to both schemes alike.
func map_values(values: Dictionary, thumbsticks: ThumbstickMapping) -> ShipInput:
	mapping.left_handed = thumbsticks.left_handed
	mapping.invert_pitch = thumbsticks.invert_pitch
	update_grabs(values)
	var poses: Dictionary = values.get(ControllerSampler.POSES, {})
	var buttons: Dictionary = values.get("buttons", {})
	# The mapping reads its own afterburner button; feed it this scheme's one.
	var mapped_button: String = (GrippedStickMapping.AFTERBURNER_BUTTON_LEFT_HANDED
		if mapping.left_handed else GrippedStickMapping.AFTERBURNER_BUTTON)
	var input: ShipInput = mapping.map_controls(
		_relative("left", poses), _relative("right", poses),
		1.0 if holds("left") else 0.0, 1.0 if holds("right") else 0.0,
		{mapped_button: bool(buttons.get(afterburner_button(), false))})
	var stick_hand: String = "left" if mapping.left_handed else "right"
	input.fire_primary = float(values.get(stick_hand + "_trigger", 0.0)) \
		>= ThumbstickMapping.BUTTON_THRESHOLD
	return input


func _relative(hand: String, poses: Dictionary) -> Transform3D:
	if not _grabs.has(hand) or not poses.has(hand):
		return Transform3D.IDENTITY
	return relative_pose(_grabs[hand], poses[hand])
