extends RefCounted

## Layout reading split out of the mapping (#1158, PLT-5, ARC-4): the shipped
## default file read through `ThumbstickLayout` equals the built-in default,
## a broken file keeps the default with the same error text, and the
## mapping's forwards give the same result as the new class.


func _same_layout(got: Dictionary, want: Dictionary) -> String:
	if got.size() != want.size():
		return "got %d actions, want %d: %s" % [got.size(), want.size(), got]
	for action: Variant in want:
		if not got.has(action) or got[action] != want[action]:
			return "\"%s\": got %s, want %s" % [action, got.get(action), want[action]]
	return ""


func test_shipped_default_file_equals_default_layout() -> String:
	var read: ThumbstickLayout = ThumbstickLayout.from_file(ThumbstickLayout.DEFAULT_LAYOUT_FILE)
	if read.error != "":
		return "default file rejected: %s" % read.error
	if read.warning != "":
		return "default file warned: %s" % read.warning
	return _same_layout(read.bindings, ThumbstickLayout.default_layout())


func test_mapping_forwards_default_layout() -> String:
	return _same_layout(ThumbstickMapping.default_layout(), ThumbstickLayout.default_layout())


func test_missing_file_keeps_default_with_error() -> String:
	var path: String = ThumbstickLayout.LAYOUTS_DIR + "/no_such_layout.json"
	var read: ThumbstickLayout = ThumbstickLayout.from_file(path)
	if read.error != "no layout file at %s" % path:
		return "error: %s" % read.error
	var mapping: ThumbstickMapping = ThumbstickMapping.from_file(path)
	if mapping.error != read.error:
		return "mapping error %s, layout error %s" % [mapping.error, read.error]
	return _same_layout(mapping.layout, ThumbstickLayout.default_layout())


func test_broken_json_keeps_default_with_same_error_text() -> String:
	var text: String = "{\"strafe\": {\"left_stick_x\": 2.0}}"
	var read: ThumbstickLayout = ThumbstickLayout.from_json(text)
	var want: String = "weight of \"left_stick_x\" in \"strafe\" is 2.0, must be in -1..1"
	if read.error != want:
		return "error %s, want %s" % [read.error, want]
	if ThumbstickMapping.from_json(text).error != want:
		return "mapping error %s" % ThumbstickMapping.from_json(text).error
	if read.stick_dead_zone != StickDeadZone.DEFAULT:
		return "dead zone %s on a rejected file" % read.stick_dead_zone
	return _same_layout(read.bindings, ThumbstickLayout.default_layout())


func test_mapping_takes_dead_zone_from_layout() -> String:
	var text: String = "{\"strafe\": {\"left_stick_x\": 1.0}, \"%s\": 0.2}" % StickDeadZone.FIELD
	var read: ThumbstickLayout = ThumbstickLayout.from_json(text)
	var mapping: ThumbstickMapping = ThumbstickMapping.from_json(text)
	if mapping.stick_dead_zone != read.stick_dead_zone or mapping.warning != read.warning:
		return "mapping dead zone %s warning %s, layout %s %s" % [
			mapping.stick_dead_zone, mapping.warning, read.stick_dead_zone, read.warning]
	return _same_layout(mapping.layout, read.bindings)


func test_swap_hands_swaps_left_and_right_only() -> String:
	var got: Dictionary = ThumbstickLayout.swap_hands({"left_grip": 0.5, "right_stick_x": -1.0, "other": 1.0})
	var want: Dictionary = {"right_grip": 0.5, "left_stick_x": -1.0, "other": 1.0}
	if got != want:
		return "got %s, want %s" % [got, want]
	return ""
