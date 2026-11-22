extends RefCounted

## The gripped stick and throttle flown from sampled values (#739, PLT-5,
## FLT-1, FLT-2, MP-2): grabbing, releasing, thrust, pitch, the buttons and
## left-handed mode, all from plain values without a headset.

## Grab poses with arbitrary turns, so a test cannot pass only because the
## controller happened to point along the rig's axes at the grab.
var LEFT_GRAB: Transform3D = Transform3D(
	Basis.from_euler(Vector3(-0.6, 0.3, 0.2)), Vector3(-0.2, 1.0, -0.3))
var RIGHT_GRAB: Transform3D = Transform3D(
	Basis.from_euler(Vector3(-0.5, -0.4, -0.1)), Vector3(0.2, 1.0, -0.3))


static func _values(left_pose: Transform3D, right_pose: Transform3D,
		left_grip: float, right_grip: float, buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_grip"] = left_grip
	values["right_grip"] = right_grip
	values["buttons"] = buttons
	values[ControllerSampler.POSES] = {"left": left_pose, "right": right_pose}
	return values


## `pose` turned by `turn` in the rig's frame, about its own position.
static func _turned(pose: Transform3D, turn: Basis) -> Transform3D:
	return Transform3D(turn * pose.basis, pose.origin)


static func _still(input: ShipInput) -> bool:
	return input.thrust_q == Vector3i.ZERO and input.turn_q == Vector3i.ZERO \
		and not input.afterburner and not input.fire_primary


func test_no_input_until_a_grip_is_pulled() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	var moved_left: Transform3D = LEFT_GRAB.translated(Vector3(0.0, 0.0, -0.1))
	var tilted_right: Transform3D = _turned(RIGHT_GRAB, Basis(Vector3.RIGHT, -0.5))
	for values: Dictionary in [_values(LEFT_GRAB, RIGHT_GRAB, 0.0, 0.0),
			_values(moved_left, tilted_right, 0.4, 0.4, {"left_button_upper": true})]:
		var input: ShipInput = sampler.map_values(values, thumbs)
		if not _still(input):
			return "input %s %s before a grip was pulled" % [input.thrust_q, input.turn_q]
	if sampler.holds("left") or sampler.holds("right"):
		return "a hand holds its control without a grip"
	return ""


func test_a_grabbed_throttle_pushed_ahead_gives_forward_thrust() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	var grabbed: ShipInput = sampler.map_values(_values(LEFT_GRAB, RIGHT_GRAB, 1.0, 0.0), thumbs)
	if not _still(grabbed):
		return "grabbing alone moved the ship: %s" % grabbed.thrust_q
	var ahead: Transform3D = LEFT_GRAB.translated(Vector3(0.0, 0.0, -0.10))
	var input: ShipInput = sampler.map_values(_values(ahead, RIGHT_GRAB, 1.0, 0.0), thumbs)
	if input.thrust().z > -0.99 or not is_zero_approx(input.thrust().x) \
			or not is_zero_approx(input.thrust().y) or input.turn_q != Vector3i.ZERO:
		return "throttle 10 cm ahead gave thrust %s turn %s" % [input.thrust(), input.turn_q]
	return ""


func test_releasing_the_grip_centres_the_control() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	var ahead: Transform3D = LEFT_GRAB.translated(Vector3(0.0, 0.0, -0.10))
	sampler.map_values(_values(LEFT_GRAB, RIGHT_GRAB, 1.0, 0.0), thumbs)
	sampler.map_values(_values(ahead, RIGHT_GRAB, 1.0, 0.0), thumbs)
	var released: ShipInput = sampler.map_values(_values(ahead, RIGHT_GRAB, 0.0, 0.0), thumbs)
	if not _still(released) or sampler.holds("left"):
		return "after release: thrust %s, holds %s" % [released.thrust_q, sampler.holds("left")]
	# Grabbing again where the hand now is starts from the centre.
	var regrabbed: ShipInput = sampler.map_values(_values(ahead, RIGHT_GRAB, 1.0, 0.0), thumbs)
	if not _still(regrabbed):
		return "a new grab did not start centred: %s" % regrabbed.thrust_q
	# A hand that stops being tracked lets go as well.
	var lost: Dictionary = _values(ahead, RIGHT_GRAB, 1.0, 0.0)
	lost[ControllerSampler.POSES] = {"right": RIGHT_GRAB}
	sampler.map_values(lost, thumbs)
	if sampler.holds("left"):
		return "an untracked hand still holds the throttle"
	return ""


func test_a_stick_tilted_ahead_pitches_the_nose_down() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	sampler.map_values(_values(LEFT_GRAB, RIGHT_GRAB, 0.0, 1.0), thumbs)
	# Top ahead is a negative turn about the rig's x axis.
	var tilted: Transform3D = _turned(RIGHT_GRAB, Basis(Vector3.RIGHT, -deg_to_rad(20.0)))
	var input: ShipInput = sampler.map_values(_values(LEFT_GRAB, tilted, 0.0, 1.0), thumbs)
	if input.turn().x >= -0.1 or absf(input.turn().y) > 0.01 or absf(input.turn().z) > 0.01:
		return "stick tilted ahead gave turn %s" % input.turn()
	if input.thrust_q != Vector3i.ZERO:
		return "the stick moved the ship: %s" % input.thrust_q
	return ""


func test_y_boosts_and_x_does_not() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	var y: ShipInput = sampler.map_values(
		_values(LEFT_GRAB, RIGHT_GRAB, 1.0, 0.0, {"left_button_upper": true}), thumbs)
	var x: ShipInput = sampler.map_values(
		_values(LEFT_GRAB, RIGHT_GRAB, 1.0, 0.0, {"left_button_lower": true}), thumbs)
	if not y.afterburner or x.afterburner:
		return "Y boosts %s, X boosts %s" % [y.afterburner, x.afterburner]
	if sampler.afterburner_button() == "left_button_lower":
		return "the afterburner sits on X, the free button (decision record 0011)"
	return ""


func test_the_stick_hands_trigger_fires() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	var values: Dictionary = _values(LEFT_GRAB, RIGHT_GRAB, 0.0, 0.0)
	values["right_trigger"] = 1.0
	var right: ShipInput = sampler.map_values(values, thumbs)
	values["right_trigger"] = 0.0
	values["left_trigger"] = 1.0
	var left: ShipInput = sampler.map_values(values, thumbs)
	if not right.fire_primary or left.fire_primary:
		return "right trigger fires %s, left trigger fires %s" % [
			right.fire_primary, left.fire_primary]
	return ""


func test_left_handed_mode_swaps_the_hands() -> String:
	var sampler: GrippedSampler = GrippedSampler.new()
	var thumbs: ThumbstickMapping = ThumbstickMapping.new()
	thumbs.left_handed = true
	sampler.map_values(_values(LEFT_GRAB, RIGHT_GRAB, 1.0, 1.0), thumbs)
	var tilted_left: Transform3D = _turned(LEFT_GRAB, Basis(Vector3.RIGHT, -deg_to_rad(20.0)))
	var right_ahead: Transform3D = RIGHT_GRAB.translated(Vector3(0.0, 0.0, -0.10))
	var values: Dictionary = _values(tilted_left, right_ahead, 1.0, 1.0,
		{"right_button_upper": true})
	values["left_trigger"] = 1.0
	var input: ShipInput = sampler.map_values(values, thumbs)
	if input.turn().x >= -0.1 or input.thrust().z > -0.99:
		return "left-handed: turn %s thrust %s" % [input.turn(), input.thrust()]
	if not input.afterburner or not input.fire_primary:
		return "left-handed: B boosts %s, left trigger fires %s" % [
			input.afterburner, input.fire_primary]
	values["buttons"] = {"left_button_upper": true}
	if sampler.map_values(values, thumbs).afterburner:
		return "left-handed: Y still boosts"
	return ""


func test_relative_pose_is_in_the_rigs_axes() -> String:
	var turn: Basis = Basis(Vector3.UP, 0.3)
	var rel: Transform3D = GrippedSampler.relative_pose(
		RIGHT_GRAB, Transform3D(turn * RIGHT_GRAB.basis, RIGHT_GRAB.origin + Vector3(0.0, 0.05, 0.0)))
	if not rel.basis.is_equal_approx(turn) or not rel.origin.is_equal_approx(Vector3(0.0, 0.05, 0.0)):
		return "relative pose %s" % rel
	return ""
