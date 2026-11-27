extends RefCounted

## The render scale table (#1417, GFX-7, ARC-4): the shipped file is read
## and scaling is off (#1503: on the Quest a lowered scale magnified the
## picture, so it stays off until a device step proves it); a missing or out-of-range value, a wrong type, an
## unknown key, a floor above the ceiling or a low water at or above the high
## water are refused with the field named; a refused or missing file falls
## back to scaling off.

const SHIPPED: String = "res://xr/render_scale.json"
const SCRATCH: String = "user://t1417_render_scale.json"


func _data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIPPED))


func test_the_shipped_file_is_read_with_scaling_off() -> String:
	var table: RenderScaleTable = RenderScaleTable.load_file(SHIPPED)
	if table.error != "" or table.enabled:
		return "the shipped table: error \"%s\", enabled %s" % [table.error, table.enabled]
	if table.ceiling != 1.0 or table.floor_scale >= 1.0 or table.floor_scale < 0.5:
		return "the shipped bounds are %s..%s" % [table.floor_scale, table.ceiling]
	return ""


func test_a_missing_value_is_refused_with_its_name() -> String:
	for key: String in _data():
		var data: Dictionary = _data()
		data.erase(key)
		var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify(data))
		if not table.error.contains("missing key \"%s\"" % key):
			return "without %s: \"%s\"" % [key, table.error]
	return ""


func test_an_out_of_range_or_mistyped_value_is_refused_with_its_name() -> String:
	var bad: Array = [["floor", 0.4], ["floor", 1.1], ["ceiling", 1.2], ["step", 0.0], ["step", 0.6],
		["high_water", 2.5], ["low_water", 0.05], ["frames_down", 0], ["frames_up", 601],
		["interval_frames", -1], ["frames_down", 2.5], ["step", "0.1"], ["floor", true],
		["enabled", 1], ["enabled", "yes"]]
	for pair: Array in bad:
		var data: Dictionary = _data()
		data[pair[0]] = pair[1]
		var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify(data))
		if table.error == "" or not table.error.contains("\"%s\"" % pair[0]):
			return "%s = %s gave \"%s\"" % [pair[0], pair[1], table.error]
	return ""


func test_inconsistent_pairs_and_unknown_keys_are_refused() -> String:
	var data: Dictionary = _data()
	data["floor"] = 0.9
	data["ceiling"] = 0.8
	var table: RenderScaleTable = RenderScaleTable.parse(JSON.stringify(data))
	if not table.error.contains("\"floor\""):
		return "a floor above the ceiling gave \"%s\"" % table.error
	data = _data()
	data["low_water"] = data["high_water"]
	table = RenderScaleTable.parse(JSON.stringify(data))
	if not table.error.contains("\"low_water\""):
		return "low water at high water gave \"%s\"" % table.error
	data = _data()
	data["gpu_only"] = true
	table = RenderScaleTable.parse(JSON.stringify(data))
	if not table.error.contains("\"gpu_only\""):
		return "an unknown key gave \"%s\"" % table.error
	if RenderScaleTable.parse("[1, 2]").error == "" or RenderScaleTable.parse("{").error == "":
		return "text that is not an object was read"
	return ""


func test_a_refused_or_missing_file_turns_scaling_off() -> String:
	var data: Dictionary = _data()
	data["floor"] = 0.1
	var file: FileAccess = FileAccess.open(SCRATCH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var refused: RenderScaleTable = RenderScaleTable.load_file(SCRATCH)
	DirAccess.remove_absolute(SCRATCH)
	var missing: RenderScaleTable = RenderScaleTable.load_file(SCRATCH)
	if refused.enabled or not refused.error.contains("\"floor\""):
		return "a refused file: enabled %s, error \"%s\"" % [refused.enabled, refused.error]
	if missing.enabled or missing.error != "file not found":
		return "a missing file: enabled %s, error \"%s\"" % [missing.enabled, missing.error]
	return ""
