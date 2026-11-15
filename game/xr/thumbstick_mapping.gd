class_name ThumbstickMapping
extends RefCounted

## The thumbsticks-only control scheme (PLT-5) as a pure mapping from
## controller values to one tick's `ShipInput` (FLT-1).
##
## It reads no input device: the caller passes the values it read, so the
## mapping can be tested without a headset and the same code serves every
## controller source. Comfort filtering is not done here (ARC-3).
##
## Default right-handed layout:
## - left stick: x strafe, y forward and back
## - right stick: x yaw, y pitch
## - left grip rolls left, right grip rolls right
## - left trigger moves down, right trigger moves up
## - face buttons are accepted but unbound
##
## Ship axes use the pilot's view, each -1..1 before scaling:
## `strafe` (+ right), `lift` (+ up), `forward` (+ ahead), `pitch` (+ nose up),
## `yaw` (+ nose right), `roll` (+ right wing down). Stick y is + when pushed
## away from the player, as OpenXR reports it, so pushing the right stick
## away pitches the nose up unless `invert_pitch` is on.
##
## Left-handed mode swaps the roles of the two hands: every left control acts
## as the right one and the other way round, so the right stick flies and the
## left stick turns. Stick x keeps its direction, so pushing right still means
## right.

## Radial dead zone of each stick as a fraction of full deflection. Drift
## inside it gives exactly zero, so a resting stick never moves the ship.
const STICK_DEAD_ZONE: float = 0.15
const MAX_PITCH_RATE: float = PI / 2.0
const MAX_YAW_RATE: float = PI / 2.0
const MAX_ROLL_RATE: float = PI * 0.75

const AXES: Array[String] = ["strafe", "lift", "forward", "pitch", "yaw", "roll"]
## Physical controls a layout may bind. Buttons are named by position rather
## than by letter, so left-handed mode can swap them like everything else.
const CONTROLS: Array[String] = [
	"left_stick_x", "left_stick_y", "right_stick_x", "right_stick_y",
	"left_trigger", "right_trigger", "left_grip", "right_grip",
	"left_button_lower", "left_button_upper", "right_button_lower", "right_button_upper",
]

## Ship axis -> {physical control: weight}. The settings menu can replace this
## to remap controls without code changes.
var layout: Dictionary = {}
var left_handed: bool = false
var invert_pitch: bool = false


func _init(p_layout: Dictionary = default_layout()) -> void:
	layout = p_layout


## A fresh copy of the default right-handed layout, safe to edit.
static func default_layout() -> Dictionary:
	return {
		"strafe": {"left_stick_x": 1.0},
		"forward": {"left_stick_y": 1.0},
		"yaw": {"right_stick_x": 1.0},
		"pitch": {"right_stick_y": 1.0},
		"roll": {"left_grip": -1.0, "right_grip": 1.0},
		"lift": {"left_trigger": -1.0, "right_trigger": 1.0},
	}


## Scales a stick so that the dead zone gives exactly zero and the output
## rises from zero at its edge to 1 at full deflection, in the same direction.
static func apply_dead_zone(stick: Vector2) -> Vector2:
	var length: float = stick.length()
	# Vector2 holds 32-bit floats, so a stick reading exactly on the edge can
	# come out a hair longer than the 64-bit constant.
	if length <= STICK_DEAD_ZONE or is_equal_approx(length, STICK_DEAD_ZONE):
		return Vector2.ZERO
	var scaled: float = (minf(length, 1.0) - STICK_DEAD_ZONE) / (1.0 - STICK_DEAD_ZONE)
	return stick / length * scaled


## Maps one frame of controller values to the input for one tick. Triggers
## and grips are 0..1; `buttons` maps button names from `CONTROLS` to
## pressed, and a missing button counts as released.
func map_controls(left_stick: Vector2, right_stick: Vector2,
		left_trigger: float, right_trigger: float,
		left_grip: float, right_grip: float,
		buttons: Dictionary = {}) -> ShipInput:
	var left: Vector2 = apply_dead_zone(left_stick)
	var right: Vector2 = apply_dead_zone(right_stick)
	var controls: Dictionary = {
		"left_stick_x": left.x, "left_stick_y": left.y,
		"right_stick_x": right.x, "right_stick_y": right.y,
		"left_trigger": clampf(left_trigger, 0.0, 1.0),
		"right_trigger": clampf(right_trigger, 0.0, 1.0),
		"left_grip": clampf(left_grip, 0.0, 1.0),
		"right_grip": clampf(right_grip, 0.0, 1.0),
	}
	for button: String in ["left_button_lower", "left_button_upper",
			"right_button_lower", "right_button_upper"]:
		controls[button] = 1.0 if buttons.get(button, false) else 0.0
	if left_handed:
		controls = _swap_hands(controls)
	var axis: Dictionary = {}
	for name: String in AXES:
		axis[name] = _axis_value(controls, name)
	var pitch: float = -axis["pitch"] if invert_pitch else axis["pitch"]
	# Ship space: z forward is negative; positive rotations about x, y and z
	# raise the nose, turn it left and lower the left wing.
	var thrust: Vector3 = Vector3(axis["strafe"], axis["lift"], -axis["forward"])
	var turn: Vector3 = Vector3(
		pitch * MAX_PITCH_RATE,
		-axis["yaw"] * MAX_YAW_RATE,
		-axis["roll"] * MAX_ROLL_RATE)
	return ShipInput.from_floats(thrust, turn)


func _axis_value(controls: Dictionary, axis_name: String) -> float:
	var bindings: Dictionary = layout.get(axis_name, {})
	var total: float = 0.0
	for control: Variant in bindings:
		total += float(controls.get(control, 0.0)) * float(bindings[control])
	return clampf(total, -1.0, 1.0)


static func _swap_hands(controls: Dictionary) -> Dictionary:
	var swapped: Dictionary = {}
	for control: String in controls:
		var other: String = control
		if control.begins_with("left_"):
			other = "right_" + control.trim_prefix("left_")
		elif control.begins_with("right_"):
			other = "left_" + control.trim_prefix("right_")
		swapped[other] = controls[control]
	return swapped
