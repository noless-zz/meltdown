extends RefCounted

## The face buttons after the owner's 2026-11-19 change (#613, PLT-5, CMF-1):
## up on B, down on Y, boost on A; left-handed mode swaps each with its twin
## (up on Y, down on B, boost on X). X, the comfort preset button until decision
## record 0011 (#1260), is free, and so is A when left-handed. Read from
## each layout file, so a remap in data cannot drift from decision record 0004.

const Z: Vector2 = Vector2.ZERO
const LAYOUT_FILES: Array[String] = [
	ThumbstickMapping.DEFAULT_LAYOUT_FILE, ThumbstickMapping.PAIRED_LAYOUT_FILE,
]


func _mapping(path: String, left_handed: bool) -> ThumbstickMapping:
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
	mapping.left_handed = left_handed
	return mapping


func _press(mapping: ThumbstickMapping, control: String) -> ShipInput:
	return mapping.map_controls(Z, Z, 0.0, 0.0, 0.0, 0.0, {control: true})


func _mode(path: String, left_handed: bool) -> String:
	return "%s%s" % [path.get_file(), " left-handed" if left_handed else ""]


func test_layout_files_load() -> String:
	for path: String in LAYOUT_FILES:
		var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
		if mapping.error != "":
			return "%s rejected: %s" % [path, mapping.error]
	return ""


func test_up_is_on_b_and_y_when_left_handed_in_every_layout() -> String:
	for path: String in LAYOUT_FILES:
		for left_handed: bool in [false, true]:
			var up_button: String = "left_button_upper" if left_handed else "right_button_upper"
			var lift: int = _press(_mapping(path, left_handed), up_button).thrust_q.y
			if lift != ShipInput.SCALE:
				return "%s: %s should lift up, got %d" % [_mode(path, left_handed), up_button, lift]
	return ""


func test_down_is_on_y_and_b_when_left_handed_in_the_default_layout() -> String:
	var path: String = ThumbstickMapping.DEFAULT_LAYOUT_FILE
	for left_handed: bool in [false, true]:
		var mapping: ThumbstickMapping = _mapping(path, left_handed)
		var down_button: String = "right_button_upper" if left_handed else "left_button_upper"
		var lift: int = _press(mapping, down_button).thrust_q.y
		if lift != -ShipInput.SCALE:
			return "%s: %s should move down, got %d" % [_mode(path, left_handed), down_button, lift]
		# Down and up sit on the same row of each hand, so they mirror.
		var down_controls: Array[String] = mapping.physical_controls("lift")
		if down_controls.size() != 2 or not (down_controls.has("left_button_upper")
				and down_controls.has("right_button_upper")):
			return "%s: lift should be on Y and B only, got %s" % [_mode(path, left_handed), down_controls]
	return ""


## X, or A when left-handed: the button no layout binds (decision record 0011).
func _free_button(left_handed: bool) -> String:
	return "right_button_lower" if left_handed else "left_button_lower"


func test_no_layout_flies_the_free_button() -> String:
	for path: String in LAYOUT_FILES:
		for left_handed: bool in [false, true]:
			var mapping: ThumbstickMapping = _mapping(path, left_handed)
			var free_button: String = _free_button(left_handed)
			for action: Variant in mapping.layout:
				if mapping.physical_controls(str(action)).has(free_button):
					return "%s: the free button %s does %s" % [_mode(path, left_handed), free_button, action]
			var input: ShipInput = _press(mapping, free_button)
			if input.thrust_q != Vector3i.ZERO or input.turn_q != Vector3i.ZERO or input.afterburner:
				return "%s: pressing the free button moved the ship" % _mode(path, left_handed)
	return ""


func test_boost_stays_on_a_and_x_when_left_handed() -> String:
	for path: String in LAYOUT_FILES:
		for left_handed: bool in [false, true]:
			var boost_button: String = "left_button_lower" if left_handed else "right_button_lower"
			if not _press(_mapping(path, left_handed), boost_button).afterburner:
				return "%s: %s should boost" % [_mode(path, left_handed), boost_button]
	return ""


func test_paired_roll_left_stays_off_x() -> String:
	var path: String = ThumbstickMapping.PAIRED_LAYOUT_FILE
	for left_handed: bool in [false, true]:
		var roll_button: String = "right_button_upper" if left_handed else "left_button_upper"
		var roll: int = _press(_mapping(path, left_handed), roll_button).turn_q.z
		if roll <= 0:
			return "%s: %s should roll left, got %d" % [_mode(path, left_handed), roll_button, roll]
	return ""


func test_labels_name_three_buttons_and_leave_the_free_one_bare() -> String:
	for left_handed: bool in [false, true]:
		var labels: Dictionary = ControlLabels.for_layout(ThumbstickMapping.default_layout(), left_handed)
		var want: Dictionary = {
			"right_button_upper": "down" if left_handed else "up",
			"left_button_upper": "up" if left_handed else "down",
			"right_button_lower": "" if left_handed else "boost",
			"left_button_lower": "boost" if left_handed else "",
		}
		for control: String in want:
			if str(labels.get(control, "")) != want[control]:
				return "%s: %s reads '%s', want '%s'" % [
					"left-handed" if left_handed else "right-handed", control,
					labels.get(control, ""), want[control]]
		if labels.has(_free_button(left_handed)):
			return "the free button %s is still labelled" % _free_button(left_handed)
	return ""


func test_keyboard_f_still_moves_down() -> String:
	var keyboard: KeyboardSampler = KeyboardSampler.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	var down: ShipInput = ControllerSampler.map_values(mapping, keyboard.sample([KEY_F]))
	var up: ShipInput = ControllerSampler.map_values(mapping, keyboard.sample([KEY_R]))
	if down.thrust_q.y != -ShipInput.SCALE or up.thrust_q.y != ShipInput.SCALE:
		return "F / R should move down / up, got %d / %d" % [down.thrust_q.y, up.thrust_q.y]
	return ""
