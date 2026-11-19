extends RefCounted

## Control layouts as data files (issue #82, PLT-5, ARC-4, FLT-1): the
## default file matches the built-in layout, the paired layout puts both
## directions of lift and roll on one hand each, and bad files are rejected
## with the built-in default kept. Both files follow decision record 0004
## (#149): triggers fire, A boosts, face buttons lift.

const ROLL: float = ThumbstickMapping.MAX_ROLL_RATE


func _paired() -> ThumbstickMapping:
	return ThumbstickMapping.from_file(ThumbstickMapping.PAIRED_LAYOUT_FILE)


## Compares two layouts key by key, so a difference names the binding.
func _layout_diff(got: Dictionary, want: Dictionary) -> String:
	if got.size() != want.size():
		return "got %d actions, want %d: %s" % [got.size(), want.size(), got]
	for action: Variant in want:
		if not got.has(action):
			return "missing action \"%s\"" % action
		var g: Dictionary = got[action]
		var w: Dictionary = want[action]
		if g.size() != w.size():
			return "\"%s\": got %s, want %s" % [action, g, w]
		for control: Variant in w:
			if not g.has(control) or typeof(g[control]) != TYPE_FLOAT \
					or g[control] != w[control]:
				return "\"%s\": got %s, want %s" % [action, g, w]
	return ""


func _same_input(got: ShipInput, want: ShipInput, label: String) -> String:
	if got.thrust_q != want.thrust_q or got.turn_q != want.turn_q \
			or got.afterburner != want.afterburner or got.fire_primary != want.fire_primary:
		return "%s: got thrust %s turn %s boost %s fire %s, want thrust %s turn %s boost %s fire %s" % [
			label, got.thrust_q, got.turn_q, got.afterburner, got.fire_primary,
			want.thrust_q, want.turn_q, want.afterburner, want.fire_primary]
	return ""


func test_default_file_equals_built_in_layout() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE)
	if mapping.error != "":
		return "default file rejected: " + mapping.error
	return _layout_diff(mapping.layout, ThumbstickMapping.default_layout())


func test_default_layout_is_unchanged() -> String:
	var want: Dictionary = {
		"strafe": {"left_stick_x": 1.0},
		"forward": {"left_stick_y": 1.0},
		"yaw": {"right_stick_x": 1.0},
		"pitch": {"right_stick_y": 1.0},
		"roll": {"left_grip": -1.0, "right_grip": 1.0},
		"lift": {"left_button_upper": -1.0, "right_button_upper": 1.0},
		"afterburner": {"right_button_lower": 1.0},
		"fire_primary": {"right_trigger": 1.0},
		"slot_part": {"right_stick_click": 1.0},
		"show_map": {"left_stick_click": 1.0},
	}
	return _layout_diff(ThumbstickMapping.default_layout(), want)


func test_paired_file_follows_decision_record() -> String:
	var want: Dictionary = {
		"strafe": {"left_stick_x": 1.0},
		"forward": {"left_stick_y": 1.0},
		"yaw": {"right_stick_x": 1.0},
		"pitch": {"right_stick_y": 1.0},
		"roll": {"left_button_upper": -1.0, "left_grip": 1.0},
		"lift": {"right_button_upper": 1.0, "right_grip": -1.0},
		"afterburner": {"right_button_lower": 1.0},
		"fire_primary": {"right_trigger": 1.0},
		"slot_part": {"right_stick_click": 1.0},
		"show_map": {"left_stick_click": 1.0},
	}
	return _layout_diff(_paired().layout, want)


func test_no_layout_file_binds_a_trigger_to_lift() -> String:
	for path: String in [ThumbstickMapping.DEFAULT_LAYOUT_FILE, ThumbstickMapping.PAIRED_LAYOUT_FILE]:
		var m: ThumbstickMapping = ThumbstickMapping.from_file(path)
		var z: Vector2 = Vector2.ZERO
		for pull: Array in [[1.0, 0.0], [0.0, 1.0]]:
			var input: ShipInput = m.map_controls(z, z, pull[0], pull[1], 0.0, 0.0)
			if input.thrust_q != Vector3i.ZERO:
				return "%s: triggers %s moved the ship %s" % [path, pull, input.thrust_q]
		if not m.map_controls(z, z, 0.0, 1.0, 0.0, 0.0).fire_primary:
			return "%s: right trigger does not fire" % path
	return ""


func test_paired_file_loads() -> String:
	var mapping: ThumbstickMapping = _paired()
	if mapping.error != "":
		return "paired file rejected: " + mapping.error
	return ""


func test_paired_bindings_give_right_axis_and_sign() -> String:
	var m: ThumbstickMapping = _paired()
	var z: Vector2 = Vector2.ZERO
	var cases: Array[Array] = [
		["B up", m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"right_button_upper": true}),
			ShipInput.from_floats(Vector3(0, 1, 0), Vector3.ZERO)],
		["right grip down", m.map_controls(z, z, 0.0, 0.0, 0.0, 1.0),
			ShipInput.from_floats(Vector3(0, -1, 0), Vector3.ZERO)],
		["Y roll left", m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"left_button_upper": true}),
			ShipInput.from_floats(Vector3.ZERO, Vector3(0, 0, ROLL))],
		["left grip roll right", m.map_controls(z, z, 0.0, 0.0, 1.0, 0.0),
			ShipInput.from_floats(Vector3.ZERO, Vector3(0, 0, -ROLL))],
	]
	for c: Array in cases:
		var problem: String = _same_input(c[1], c[2], c[0])
		if problem != "":
			return problem
	return ""


func test_paired_sticks_and_afterburner_match_default() -> String:
	var paired: ThumbstickMapping = _paired()
	var built_in: ThumbstickMapping = ThumbstickMapping.new()
	for action: String in ["strafe", "forward", "yaw", "pitch", "afterburner", "fire_primary"]:
		if paired.layout.get(action) != built_in.layout.get(action):
			return "\"%s\": paired %s, default %s" % [
				action, paired.layout.get(action), built_in.layout.get(action)]
	return ""


func test_right_controller_alone_gives_both_directions_of_lift() -> String:
	var m: ThumbstickMapping = _paired()
	var z: Vector2 = Vector2.ZERO
	# Only right-hand values: the left trigger, grip and buttons stay at rest.
	var up: ShipInput = m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"right_button_upper": true})
	var down: ShipInput = m.map_controls(z, z, 0.0, 0.0, 0.0, 1.0)
	if up.thrust().y <= 0.0:
		return "B alone should lift up, got %s" % up.thrust()
	if down.thrust().y >= 0.0:
		return "right grip alone should lift down, got %s" % down.thrust()
	return ""


func test_left_handed_paired_swaps_hands() -> String:
	var m: ThumbstickMapping = _paired()
	m.left_handed = true
	var z: Vector2 = Vector2.ZERO
	var fire: ShipInput = ShipInput.new()
	fire.fire_primary = true
	var cases: Array[Array] = [
		["Y up", m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"left_button_upper": true}),
			ShipInput.from_floats(Vector3(0, 1, 0), Vector3.ZERO)],
		["left grip down", m.map_controls(z, z, 0.0, 0.0, 1.0, 0.0),
			ShipInput.from_floats(Vector3(0, -1, 0), Vector3.ZERO)],
		["B roll left", m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"right_button_upper": true}),
			ShipInput.from_floats(Vector3.ZERO, Vector3(0, 0, ROLL))],
		["right grip roll right", m.map_controls(z, z, 0.0, 0.0, 0.0, 1.0),
			ShipInput.from_floats(Vector3.ZERO, Vector3(0, 0, -ROLL))],
		["left trigger fires", m.map_controls(z, z, 1.0, 0.0, 0.0, 0.0), fire],
		["X boosts forward", m.map_controls(z, z, 0.0, 0.0, 0.0, 0.0, {"left_button_lower": true}),
			ShipInput.from_floats(Vector3(0, 0, -1), Vector3.ZERO, true)],
	]
	for c: Array in cases:
		var problem: String = _same_input(c[1], c[2], c[0])
		if problem != "":
			return problem
	return ""


func test_rejected_files_keep_default_and_name_the_problem() -> String:
	var cases: Array[Array] = [
		["not json", "{", "invalid JSON"],
		["not an object", "[1, 2]", "top level"],
		["unknown axis", "{\"hover\": {\"left_grip\": 1.0}}", "\"hover\""],
		["unknown control", "{\"lift\": {\"left_pedal\": 1.0}}", "\"left_pedal\""],
		["weight above 1", "{\"lift\": {\"right_trigger\": 1.5}}", "\"right_trigger\""],
		["weight below -1", "{\"roll\": {\"left_grip\": -2}}", "\"left_grip\""],
		["weight not a number", "{\"lift\": {\"right_trigger\": true}}", "\"right_trigger\""],
		["bindings not an object", "{\"lift\": 1.0}", "\"lift\""],
	]
	for c: Array in cases:
		var mapping: ThumbstickMapping = ThumbstickMapping.from_json(c[1])
		if mapping.error == "":
			return "%s: accepted" % c[0]
		if not mapping.error.contains(c[2]):
			return "%s: error \"%s\" does not name %s" % [c[0], mapping.error, c[2]]
		var problem: String = _layout_diff(mapping.layout, ThumbstickMapping.default_layout())
		if problem != "":
			return "%s: default not kept: %s" % [c[0], problem]
	return ""


func test_missing_file_keeps_default() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file("res://xr/layouts/no_such_layout.json")
	if mapping.error == "":
		return "missing file gave no error"
	return _layout_diff(mapping.layout, ThumbstickMapping.default_layout())


func test_weights_at_bounds_are_accepted() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_json(
		"{\"lift\": {\"right_trigger\": 1, \"right_grip\": -1.0}}")
	if mapping.error != "":
		return "bounds rejected: " + mapping.error
	return ""
