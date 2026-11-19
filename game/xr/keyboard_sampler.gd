class_name KeyboardSampler
extends RefCounted

## Turns the pressed keys of the flat desktop build (PLT-4) into the same
## plain values `ControllerSampler` produces, so the keyboard flies through
## the tested `ThumbstickMapping` like the controllers do (FLT-1).
##
## Default keys, as physical positions so other keyboard layouts keep the
## shape:
## - W / S: forward / back (left stick y)
## - A / D: strafe left / right (left stick x)
## - R / F: up / down (B / Y, decision record 0004)
## - Up / Down arrow: nose up / down (right stick y; `invert_pitch` flips it)
## - Left / Right arrow: yaw left / right (right stick x)
## - Q / E: roll left / right (left / right grip)
## - Shift: afterburner (A)
## - Space: primary fire (right trigger)
## - G (`SLOT_PART_KEY`): slot the held part (right stick click, #312)
##
## The key state is passed in, so nothing here reads a device.

## Slots the part in the hold, through the control the layout binds to
## `slot_part`; G sits beside the movement keys under the left hand.
const SLOT_PART_KEY: Key = KEY_G

## Physical key -> [control, value]. Stick controls add up, so opposite keys
## cancel; triggers, grips and buttons are set while their key is held.
var bindings: Dictionary[int, Array] = default_bindings()


static func default_bindings() -> Dictionary[int, Array]:
	return {
		KEY_W: ["left_stick_y", 1.0],
		KEY_S: ["left_stick_y", -1.0],
		KEY_D: ["left_stick_x", 1.0],
		KEY_A: ["left_stick_x", -1.0],
		KEY_R: ["right_button_upper", 1.0],
		KEY_F: ["left_button_upper", 1.0],
		KEY_SPACE: ["right_trigger", 1.0],
		KEY_UP: ["right_stick_y", 1.0],
		KEY_DOWN: ["right_stick_y", -1.0],
		KEY_RIGHT: ["right_stick_x", 1.0],
		KEY_LEFT: ["right_stick_x", -1.0],
		KEY_Q: ["left_grip", 1.0],
		KEY_E: ["right_grip", 1.0],
		KEY_SHIFT: ["right_button_lower", 1.0],
		SLOT_PART_KEY: ["right_stick_click", 1.0],
	}


## The keys the caller should check each frame.
func used_keys() -> Array[int]:
	var keys: Array[int] = []
	keys.assign(bindings.keys())
	return keys


## The values for a frame in which exactly `pressed_keys` are held.
func sample(pressed_keys: Array[int]) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	var left_stick: Vector2 = Vector2.ZERO
	var right_stick: Vector2 = Vector2.ZERO
	var buttons: Dictionary = {}
	for key: int in pressed_keys:
		if not bindings.has(key):
			continue
		var control: String = bindings[key][0]
		var amount: float = float(bindings[key][1])
		match control:
			"left_stick_x":
				left_stick.x += amount
			"left_stick_y":
				left_stick.y += amount
			"right_stick_x":
				right_stick.x += amount
			"right_stick_y":
				right_stick.y += amount
			_:
				if ThumbstickMapping.BUTTONS.has(control):
					buttons[control] = amount > 0.0
				elif values.has(control):
					values[control] = clampf(amount, 0.0, 1.0)
	# Two keys at once (W and D) would read longer than a full stick; keep the
	# direction and limit the length as a real stick does.
	values["left_stick"] = left_stick.limit_length(1.0)
	values["right_stick"] = right_stick.limit_length(1.0)
	values["buttons"] = buttons
	return values
