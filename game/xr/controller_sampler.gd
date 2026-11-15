class_name ControllerSampler
extends RefCounted

## Reads the two headset controllers into the plain values that
## `ThumbstickMapping.map_controls` takes (PLT-5, FLT-1).
##
## The OpenXR actions come from `openxr_action_map.tres`: `primary` (stick),
## `trigger`, `grip`, `ax_button`, `by_button` and `primary_click`. Reading goes
## through two injected callables, so tests can feed values without a device:
## - `tracking.call(hand: String) -> bool`, hand `"left"` or `"right"`
## - `read.call(hand: String, action: String) -> Variant`: a Vector2 for
##   `primary`, a float for `trigger` and `grip`, a bool for the buttons.
##
## A hand that is not tracked reads as idle, so a controller put down or out
## of sight never keeps the ship thrusting. No comfort filtering here (ARC-3).
##
## The values form a Dictionary, also produced by `KeyboardSampler`:
## `left_stick`, `right_stick` (Vector2), `left_trigger`, `right_trigger`,
## `left_grip`, `right_grip` (float 0..1) and `buttons` (button name from
## `ThumbstickMapping.BUTTONS` -> bool).

const HANDS: Array[String] = ["left", "right"]
## OpenXR button action -> the position name `ThumbstickMapping` uses. A/X is
## the lower face button and B/Y the upper one on both Touch controllers.
const BUTTON_ACTIONS: Dictionary[String, String] = {
	"ax_button": "button_lower",
	"by_button": "button_upper",
	"primary_click": "stick_click",
}

var tracking: Callable
var read: Callable


func _init(p_tracking: Callable, p_read: Callable) -> void:
	tracking = p_tracking
	read = p_read


## A sampler that reads the given rig controllers.
static func for_controllers(left: XRController3D, right: XRController3D) -> ControllerSampler:
	var pick: Callable = func(hand: String) -> XRController3D:
		return left if hand == "left" else right
	var is_tracking: Callable = func(hand: String) -> bool:
		var controller: XRController3D = pick.call(hand)
		return controller != null and controller.get_is_active()
	var read_action: Callable = func(hand: String, action: String) -> Variant:
		var controller: XRController3D = pick.call(hand)
		if controller == null:
			return null
		if action == "primary":
			return controller.get_vector2(action)
		if action == "trigger" or action == "grip":
			return controller.get_float(action)
		return controller.is_button_pressed(action)
	return ControllerSampler.new(is_tracking, read_action)


## Values with every stick centred, every trigger and grip released and no
## button pressed.
static func idle_values() -> Dictionary:
	return {
		"left_stick": Vector2.ZERO, "right_stick": Vector2.ZERO,
		"left_trigger": 0.0, "right_trigger": 0.0,
		"left_grip": 0.0, "right_grip": 0.0,
		"buttons": {},
	}


## Turns sampled values into one tick's input through `mapping`.
static func map_values(mapping: ThumbstickMapping, values: Dictionary) -> ShipInput:
	return mapping.map_controls(
		values.get("left_stick", Vector2.ZERO), values.get("right_stick", Vector2.ZERO),
		float(values.get("left_trigger", 0.0)), float(values.get("right_trigger", 0.0)),
		float(values.get("left_grip", 0.0)), float(values.get("right_grip", 0.0)),
		values.get("buttons", {}))


## The controllers' values for this frame.
func sample() -> Dictionary:
	var values: Dictionary = idle_values()
	var buttons: Dictionary = {}
	for hand: String in HANDS:
		if not bool(tracking.call(hand)):
			continue
		values[hand + "_stick"] = _vector(hand, "primary")
		values[hand + "_trigger"] = _float(hand, "trigger")
		values[hand + "_grip"] = _float(hand, "grip")
		for action: String in BUTTON_ACTIONS:
			if _pressed(hand, action):
				buttons[hand + "_" + BUTTON_ACTIONS[action]] = true
	values["buttons"] = buttons
	return values


# A runtime that does not bind an action returns nothing useful for it; the
# helpers treat any unexpected type as released.
func _vector(hand: String, action: String) -> Vector2:
	var value: Variant = read.call(hand, action)
	return value if value is Vector2 else Vector2.ZERO


func _float(hand: String, action: String) -> float:
	var value: Variant = read.call(hand, action)
	if value is float or value is int:
		return clampf(float(value), 0.0, 1.0)
	return 0.0


func _pressed(hand: String, action: String) -> bool:
	var value: Variant = read.call(hand, action)
	return value is bool and value
