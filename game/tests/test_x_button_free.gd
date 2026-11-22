extends RefCounted

## X is free (decision record 0011, #1260, PLT-5, CMF-1, CMF-4): no shipped
## layout binds it, and pressing it in flight changes neither the comfort
## preset nor the `ShipInput` produced, in every scheme and hand setting. In
## left-handed mode the free button is its mirror, A, which is where X's
## layout entry lands. The preset still changes through the menu's Comfort
## entry; `test_dev_menu_comfort.gd` covers that path.

const THUMBSTICK_FILES: Array[String] = [
	ThumbstickMapping.DEFAULT_LAYOUT_FILE, ThumbstickMapping.PAIRED_LAYOUT_FILE,
]
const GRIP: float = 1.0


## X, or A when left-handed.
static func _free_button(left_handed: bool) -> String:
	return "right_button_lower" if left_handed else "left_button_lower"


## Every field the simulation reads from one tick's input, for comparison.
static func _fields(input: ShipInput) -> String:
	return str([input.thrust_q, input.turn_q, input.afterburner, input.reset_to_start,
		input.fire_primary, input.slot_held, input.aim_q])


## Values with the sticks, grips and triggers part way, so a binding anywhere
## would show; poses too, so the gripped scheme flies.
static func _values(buttons: Dictionary) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = Vector2(0.3, 0.6)
	values["right_stick"] = Vector2(-0.4, 0.2)
	values["left_grip"] = GRIP
	values["right_grip"] = GRIP
	values["right_trigger"] = 0.8
	values["buttons"] = buttons
	var pose: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, -0.3))
	values[ControllerSampler.POSES] = {"left": pose, "right": pose}
	return values


static func _mode(name: String, left_handed: bool) -> String:
	return "%s%s" % [name, " left-handed" if left_handed else ""]


func test_no_shipped_thumbstick_layout_binds_x() -> String:
	for path: String in THUMBSTICK_FILES:
		var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
		if mapping.error != "":
			return "%s rejected: %s" % [path, mapping.error]
		for action: Variant in mapping.layout:
			var bindings: Dictionary = mapping.layout[action]
			if bindings.has("left_button_lower") and not is_zero_approx(float(bindings["left_button_lower"])):
				return "%s binds X to %s" % [path.get_file(), action]
	return ""


func test_no_layout_file_names_x() -> String:
	for file: String in DirAccess.get_files_at(ThumbstickMapping.LAYOUTS_DIR):
		if not file.ends_with(".json"):
			continue
		var text: String = FileAccess.get_file_as_string(ThumbstickMapping.LAYOUTS_DIR + "/" + file)
		if text.contains("left_button_lower"):
			return "%s still names left_button_lower" % file
	return ""


func test_pressing_x_changes_no_ship_input_in_any_thumbstick_layout() -> String:
	for path: String in THUMBSTICK_FILES:
		for left_handed: bool in [false, true]:
			var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
			mapping.left_handed = left_handed
			var free_button: String = _free_button(left_handed)
			var without: ShipInput = ControllerSampler.map_values(mapping, _values({}))
			var with_x: ShipInput = ControllerSampler.map_values(mapping, _values({free_button: true}))
			if _fields(with_x) != _fields(without):
				return "%s: %s changed the input from %s to %s" % [
					_mode(path.get_file(), left_handed), free_button, _fields(without), _fields(with_x)]
	return ""


func test_pressing_x_changes_no_ship_input_in_the_gripped_scheme() -> String:
	for left_handed: bool in [false, true]:
		var thumbs: ThumbstickMapping = ThumbstickMapping.new()
		thumbs.left_handed = left_handed
		var free_button: String = _free_button(left_handed)
		var plain: GrippedSampler = GrippedSampler.new()
		var pressed: GrippedSampler = GrippedSampler.new()
		var without: ShipInput = plain.map_values(_values({}), thumbs)
		var with_x: ShipInput = pressed.map_values(_values({free_button: true}), thumbs)
		if plain.afterburner_button() == free_button:
			return "%s: the afterburner sits on the free button" % _mode("gripped", left_handed)
		if _fields(with_x) != _fields(without):
			return "%s: %s changed the input from %s to %s" % [
				_mode("gripped", left_handed), free_button, _fields(without), _fields(with_x)]
	return ""


## Through the main scene, as a frame runs: the preset stays and the input
## handed to the session is the one a frame without X hands it.
func test_pressing_x_in_flight_changes_neither_preset_nor_input() -> String:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	for left_handed: bool in [false, true]:
		var results: Array[String] = []
		var numbers: Array[int] = []
		for press: bool in [false, true]:
			var main: Node = scene.instantiate()
			(main.get("mapping") as ThumbstickMapping).left_handed = left_handed
			var buttons: Dictionary = {_free_button(left_handed): true} if press else {}
			for i: int in 3:
				main.call("apply_controls", _values(buttons))
			results.append(_fields((main.get("input_source") as LatestInputSource).latest_input()))
			numbers.append(int((main.get("comfort") as ComfortWiring).number))
			main.free()
		if numbers[1] != numbers[0]:
			return "%s: X moved the preset from %d to %d" % [_mode("main", left_handed), numbers[0], numbers[1]]
		if results[1] != results[0]:
			return "%s: X changed the input from %s to %s" % [_mode("main", left_handed), results[0], results[1]]
	return ""
