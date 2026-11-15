extends RefCounted

## Controller and keyboard samplers (PLT-4, PLT-5, FLT-1): raw values in,
## the plain values `ThumbstickMapping` takes out, and the whole chain from a
## key or stick to the ship moving in the main scene.


## A sampler whose hands report `values[hand][action]` and are tracked when
## listed in `tracked`.
func _fake_controllers(tracked: Array[String], values: Dictionary) -> ControllerSampler:
	var is_tracking: Callable = func(hand: String) -> bool:
		return tracked.has(hand)
	var read: Callable = func(hand: String, action: String) -> Variant:
		return (values.get(hand, {}) as Dictionary).get(action, null)
	return ControllerSampler.new(is_tracking, read)


func _both_hands_busy() -> Dictionary:
	return {
		"left": {"primary": Vector2(0.2, 0.9), "trigger": 0.3, "grip": 0.7,
				"ax_button": true, "by_button": false, "primary_click": true},
		"right": {"primary": Vector2(-0.5, 0.4), "trigger": 1.0, "grip": 0.0,
				"ax_button": false, "by_button": true, "primary_click": false},
	}


func test_controller_values_reach_plain_values() -> String:
	var sampler: ControllerSampler = _fake_controllers(["left", "right"], _both_hands_busy())
	var values: Dictionary = sampler.sample()
	if values["left_stick"] != Vector2(0.2, 0.9) or values["right_stick"] != Vector2(-0.5, 0.4):
		return "sticks read as %s and %s" % [values["left_stick"], values["right_stick"]]
	if not is_equal_approx(values["left_trigger"], 0.3) or not is_equal_approx(values["right_trigger"], 1.0):
		return "triggers read as %s and %s" % [values["left_trigger"], values["right_trigger"]]
	if not is_equal_approx(values["left_grip"], 0.7) or not is_equal_approx(values["right_grip"], 0.0):
		return "grips read as %s and %s" % [values["left_grip"], values["right_grip"]]
	var expected: Dictionary = {
		"left_button_lower": true, "left_stick_click": true, "right_button_upper": true,
	}
	if values["buttons"] != expected:
		return "buttons read as %s" % str(values["buttons"])
	return ""


func test_untracked_controllers_give_idle_input() -> String:
	var sampler: ControllerSampler = _fake_controllers([], _both_hands_busy())
	var values: Dictionary = sampler.sample()
	if values != ControllerSampler.idle_values():
		return "untracked hands read as %s" % str(values)
	var input: ShipInput = ControllerSampler.map_values(ThumbstickMapping.new(), values)
	if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO or input.afterburner:
		return "untracked hands flew %s %s %s" % [input.thrust_q, input.turn_q, input.afterburner]
	return ""


func test_one_untracked_hand_reads_idle() -> String:
	var sampler: ControllerSampler = _fake_controllers(["right"], _both_hands_busy())
	var values: Dictionary = sampler.sample()
	if values["left_stick"] != Vector2.ZERO or values["left_grip"] != 0.0:
		return "the untracked left hand still reads %s" % str(values)
	if values["right_stick"] != Vector2(-0.5, 0.4):
		return "the tracked right hand lost its stick: %s" % str(values["right_stick"])
	if values["buttons"].has("left_stick_click"):
		return "the untracked left hand still holds its stick click"
	return ""


func test_unexpected_reads_count_as_released() -> String:
	var weird: Dictionary = {"left": {"primary": 3.0, "trigger": "x", "grip": 2.5, "ax_button": 1}}
	var values: Dictionary = _fake_controllers(["left"], weird).sample()
	if values["left_stick"] != Vector2.ZERO or values["left_trigger"] != 0.0:
		return "odd types were not treated as idle: %s" % str(values)
	if not is_equal_approx(values["left_grip"], 1.0):
		return "grip above 1 was not clamped: %s" % values["left_grip"]
	if not values["buttons"].is_empty():
		return "a non-bool button counted as pressed"
	return ""


func test_controller_chain_flies_forward_and_boosts() -> String:
	var hands: Dictionary = {"left": {"primary": Vector2(0.0, 1.0), "primary_click": true}}
	var values: Dictionary = _fake_controllers(["left", "right"], hands).sample()
	var input: ShipInput = ControllerSampler.map_values(ThumbstickMapping.new(), values)
	if input.thrust_q != Vector3i(0, 0, -1000):
		return "full left stick forward gave thrust %s" % str(input.thrust_q)
	if not input.afterburner:
		return "left stick click did not hold the afterburner"
	return ""


func test_keyboard_keys_reach_plain_values() -> String:
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	var values: Dictionary = keyboard.sample([KEY_W, KEY_LEFT, KEY_R, KEY_E, KEY_SHIFT])
	if values["left_stick"] != Vector2(0.0, 1.0):
		return "W gave left stick %s" % str(values["left_stick"])
	if values["right_stick"] != Vector2(-1.0, 0.0):
		return "Left arrow gave right stick %s" % str(values["right_stick"])
	if values["right_trigger"] != 1.0 or values["left_trigger"] != 0.0:
		return "R gave triggers %s / %s" % [values["left_trigger"], values["right_trigger"]]
	if values["right_grip"] != 1.0 or values["left_grip"] != 0.0:
		return "E gave grips %s / %s" % [values["left_grip"], values["right_grip"]]
	if values["buttons"] != {"left_stick_click": true}:
		return "Shift gave buttons %s" % str(values["buttons"])
	return ""


func test_keyboard_opposite_keys_cancel_and_diagonals_stay_unit() -> String:
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	var cancel: Dictionary = keyboard.sample([KEY_W, KEY_S, KEY_UP, KEY_DOWN])
	if cancel["left_stick"] != Vector2.ZERO or cancel["right_stick"] != Vector2.ZERO:
		return "opposite keys did not cancel: %s" % str(cancel)
	var diagonal: Vector2 = keyboard.sample([KEY_W, KEY_D])["left_stick"]
	if not is_equal_approx(diagonal.length(), 1.0) or diagonal.x <= 0.0 or diagonal.y <= 0.0:
		return "W and D gave %s" % str(diagonal)
	return ""


func test_no_keys_and_unbound_keys_give_idle() -> String:
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	if keyboard.sample([]) != ControllerSampler.idle_values():
		return "no keys did not read idle"
	if keyboard.sample([KEY_Z, KEY_SPACE]) != ControllerSampler.idle_values():
		return "unbound keys did not read idle"
	if keyboard.used_keys().size() != KeyboardSampler.default_bindings().size():
		return "used_keys does not list every bound key"
	return ""


func test_keyboard_roll_and_pitch_directions() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	var up: ShipInput = ControllerSampler.map_values(mapping, keyboard.sample([KEY_UP]))
	var roll_right: ShipInput = ControllerSampler.map_values(mapping, keyboard.sample([KEY_E]))
	var lift_down: ShipInput = ControllerSampler.map_values(mapping, keyboard.sample([KEY_F]))
	if up.turn_q.x <= 0:
		return "Up arrow did not raise the nose: %s" % str(up.turn_q)
	# Positive z rotation lowers the left wing, so a right roll is negative.
	if roll_right.turn_q.z >= 0:
		return "E did not roll right: %s" % str(roll_right.turn_q)
	if lift_down.thrust_q.y >= 0:
		return "F did not move down: %s" % str(lift_down.thrust_q)
	return ""


func test_keyboard_forward_flies_the_main_scene_ship() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return "main.tscn did not load"
	var main: Node = scene.instantiate()
	var keyboard: KeyboardSampler = main.get("keyboard")
	main.call("apply_controls", keyboard.sample([KEY_W]))
	var flown: ShipInput = (main.get("input_source") as LatestInputSource).latest_input()
	for i: int in 90:
		main.call("advance_frame", 1.0 / 90.0)
	var rig_position: Vector3 = (main.get_node("XRRig") as Node3D).position
	main.free()
	if flown.thrust_q != Vector3i(0, 0, -1000):
		return "W set input thrust %s" % str(flown.thrust_q)
	if rig_position.z > -1.0:
		return "W did not move the rig forward along -z: %s" % str(rig_position)
	if absf(rig_position.x) > 1.0e-4 or absf(rig_position.y) > 1.0e-4:
		return "W moved the rig sideways: %s" % str(rig_position)
	return ""


func test_main_scene_flat_frame_samples_the_keyboard() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate()
	# Outside the tree no XR session runs, so the keyboard is the source; with
	# no key held in headless runs it reads idle.
	var values: Dictionary = main.call("sample_controls")
	main.free()
	if values != ControllerSampler.idle_values():
		return "a flat frame with no keys read %s" % str(values)
	return ""
