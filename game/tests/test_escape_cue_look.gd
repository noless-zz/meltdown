extends RefCounted

## The escape cue look file (#617, ARC-4): the shipped file parses to the
## built-in fallback, and every kind of bad value is rejected with its key named.


func _shipped_data() -> Dictionary:
	var file: FileAccess = FileAccess.open(EscapeCueLook.DEFAULT_FILE, FileAccess.READ)
	return JSON.parse_string(file.get_as_text())


## The shipped data with `key` set to `value`, as JSON text.
func _with(key: String, value: Variant) -> String:
	var data: Dictionary = _shipped_data()
	data[key] = value
	return JSON.stringify(data)


func _rejects(text: String, key: String) -> String:
	var look: Dictionary = EscapeCueLook.parse(text)
	if not look.has("error"):
		return "a bad \"%s\" was accepted" % key
	if not (look["error"] as String).contains(key):
		return "the error for \"%s\" does not name it: %s" % [key, look["error"]]
	return ""


func test_the_shipped_file_matches_the_fallback() -> String:
	var file: FileAccess = FileAccess.open(EscapeCueLook.DEFAULT_FILE, FileAccess.READ)
	if file == null:
		return "the shipped look file is missing"
	var look: Dictionary = EscapeCueLook.parse(file.get_as_text())
	if look.has("error"):
		return "the shipped look file was rejected: %s" % look["error"]
	for key: String in EscapeCueLook.FALLBACK:
		if look[key] != EscapeCueLook.FALLBACK[key]:
			return "\"%s\" is %s in the file and %s in the fallback" % [key, look[key], EscapeCueLook.FALLBACK[key]]
	if EscapeCueLook.shared()["first_show_seconds"] != 5.0 or EscapeCueLook.shared()["warning_seconds"] != 30.0:
		return "the shipped timings are not 5 s and 30 s"
	return ""


func test_unknown_and_missing_keys_are_rejected() -> String:
	var unknown: String = _rejects(_with("blink", 1), "blink")
	if unknown != "":
		return unknown
	var data: Dictionary = _shipped_data()
	data.erase("line_text")
	return _rejects(JSON.stringify(data), "line_text")


func test_bad_json_and_a_non_object_are_rejected() -> String:
	if not EscapeCueLook.parse("{").has("error") or not EscapeCueLook.parse("[1]").has("error"):
		return "bad JSON or an array was accepted"
	return ""


func test_bad_colours_are_rejected() -> String:
	for bad: Variant in [[1.0, 0.0], [1.5, 0.0, 0.0], ["red", 0, 0], "green"]:
		var result: String = _rejects(_with("arrow_color", bad), "arrow_color")
		if result != "":
			return "%s (%s)" % [result, bad]
	return ""


func test_positions_behind_inside_or_far_from_the_eye_are_rejected() -> String:
	for bad: Variant in [[0.0, 0.0, 0.5], [0.0, 0.0, -0.1], [0.0, 0.0, -3.0], [0.9, 0.0, -0.7],
			[0.0, -0.8, -0.7], [0.0, 0.0], [0.0, true, -0.7]]:
		var result: String = _rejects(_with("countdown_position_m", bad), "countdown_position_m")
		if result != "":
			return "%s (%s)" % [result, bad]
	return ""


func test_numbers_out_of_range_or_not_numbers_are_rejected() -> String:
	var cases: Array[Array] = [["first_show_seconds", 0.5], ["first_show_seconds", 31],
		["warning_seconds", 2], ["countdown_font_size", 1000], ["pixel_size", 0.0],
		["arrow_length_m", 1.0], ["exit_ring_radius_m", 0.1], ["exit_text_height_m", true],
		["line_font_size", "48"]]
	for case: Array in cases:
		var result: String = _rejects(_with(case[0], case[1]), case[0])
		if result != "":
			return "%s (%s)" % [result, case[1]]
	return ""


func test_empty_or_non_text_lines_are_rejected() -> String:
	for bad: Variant in ["", "   ", 3]:
		var result: String = _rejects(_with("line_text", bad), "line_text")
		if result != "":
			return "%s (%s)" % [result, bad]
	return _rejects(_with("exit_text", ""), "exit_text")


func test_a_missing_file_falls_back() -> String:
	var look: Dictionary = EscapeCueLook.load_file("res://view/no_such_escape_cue_look.json")
	if look != EscapeCueLook.FALLBACK:
		return "a missing file did not give the fallback"
	return ""
