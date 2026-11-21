extends RefCounted

## The status panel's preset row for the custom comfort mode (CMF-1, #807):
## "Custom (base N)" while it is active, "Custom file rejected: <field>" for
## the look's 10 s when a rejected file kept it away at start or at the preset
## button, and the numbered presets as before. View only (ARC-3).

const SCRATCH_DIR: String = "user://test_status_panel_custom"
const X: String = "left_button_lower"
const CUSTOM: int = ComfortPresetFiles.CUSTOM_NUMBER
const FRAME: float = 1.0 / 90.0


static func _comfort(custom_text: String, file_name: String) -> ComfortWiring:
	DirAccess.make_dir_recursive_absolute(SCRATCH_DIR)
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	wiring.custom_path = SCRATCH_DIR + "/" + file_name
	if FileAccess.file_exists(wiring.custom_path):
		DirAccess.remove_absolute(wiring.custom_path)
	if custom_text != "":
		var file: FileAccess = FileAccess.open(wiring.custom_path, FileAccess.WRITE)
		file.store_string(custom_text)
		file.close()
	return wiring


## The small preset label after one frame of `delta` seconds, fed as
## `RigViews.place_guarded` and `RigViews.show_ship` feed it in the game.
static func _frame(panel: StatusPanel, comfort: ComfortWiring, delta: float = FRAME) -> String:
	RigViews.show_swivel(panel, comfort)
	RigViews.show_custom(panel, comfort)
	RigViews.show_ship(panel, ShipState.new(), comfort.number, comfort.preset.display_name, "", delta)
	return str(panel.texts()[StatusPanel.PRESET_NAME])


## The label after `seconds` more of 90 Hz frames.
static func _after(panel: StatusPanel, comfort: ComfortWiring, seconds: float) -> String:
	var shown: String = ""
	for i: int in roundi(seconds / FRAME):
		shown = _frame(panel, comfort)
	return shown


static func _press(comfort: ComfortWiring) -> void:
	comfort.read_preset_button({X: true})
	comfort.read_preset_button({})


func test_the_shipped_look_holds_the_custom_words() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	if look.has("error"):
		return "the shipped look was rejected: %s" % look["error"]
	var expected: Dictionary = {"preset_custom_text": "Custom (base {base})",
		"preset_custom_rejected_text": "Custom file rejected: {field}",
		"preset_custom_rejected_seconds": 10.0}
	for key: String in expected:
		if look[key] != expected[key]:
			return "shipped %s is %s, expected %s" % [key, str(look[key]), str(expected[key])]
	return ""


func test_the_custom_mode_is_named_with_its_base() -> String:
	var comfort: ComfortWiring = _comfort("{\"base\": 3, \"display_name\": \"Mine\"}", "good.json")
	comfort.set_preset(CUSTOM)
	var panel: StatusPanel = StatusPanel.new()
	var shown: String = _frame(panel, comfort)
	var large: String = str(panel.texts()[StatusPanel.PRESET_LARGE_NAME])
	comfort.set_preset(1)
	var after: String = _frame(panel, comfort)
	panel.free()
	if shown != "Custom (base 3)" or large != "Custom (base 3)":
		return "custom mode shows \"%s\" / \"%s\", expected \"Custom (base 3)\"" % [shown, large]
	if after != "Preset 1 %s" % comfort.preset.display_name:
		return "back on preset 1 the row shows \"%s\"" % after
	return ""


func test_a_file_rejected_at_start_names_the_field_for_ten_seconds() -> String:
	var comfort: ComfortWiring = _comfort("{\"base\": 7}", "bad_base.json")
	comfort.set_preset(1)
	var panel: StatusPanel = StatusPanel.new()
	var first: String = _frame(panel, comfort)
	var at_nine: String = _after(panel, comfort, 9.0)
	var at_eleven: String = _after(panel, comfort, 2.0)
	panel.free()
	if first != "Custom file rejected: base":
		return "at start the row shows \"%s\"" % first
	if at_nine != first:
		return "after 9 s the row shows \"%s\"" % at_nine
	if at_eleven != "Preset 1 %s" % comfort.preset.display_name:
		return "after 11 s the row shows \"%s\"" % at_eleven
	return ""


func test_the_preset_button_reaching_a_rejected_file_shows_it_again() -> String:
	var comfort: ComfortWiring = _comfort("{\"base\": 2, \"snap_angle_deg\": \"wide\"}", "bad_field.json")
	comfort.set_preset(3)
	var panel: StatusPanel = StatusPanel.new()
	_frame(panel, comfort)
	var cleared: String = _after(panel, comfort, 11.0)
	_press(comfort)  # 3 > 4: the custom file is not reached.
	var at_four: String = _frame(panel, comfort)
	_press(comfort)  # 4 > Custom, rejected: 1.
	var shown: String = _frame(panel, comfort)
	var number: int = comfort.number
	var later: String = _after(panel, comfort, 10.5)
	panel.free()
	if not cleared.begins_with("Preset 3 ") or not at_four.begins_with("Preset 4 "):
		return "before the custom place the row shows \"%s\", then \"%s\"" % [cleared, at_four]
	if shown != "Custom file rejected: snap_angle_deg" or number != 1:
		return "the button past preset 4 shows \"%s\" on preset %d" % [shown, number]
	if not later.begins_with("Preset 1 "):
		return "10.5 s later the row shows \"%s\"" % later
	return ""


func test_the_launch_switch_asking_for_a_rejected_file_shows_it_once() -> String:
	var comfort: ComfortWiring = _comfort("{\"base\": 2, \"unknown\": 1}", "unknown.json")
	comfort.set_preset(CUSTOM)  # As `--comfort=custom` does before the first frame.
	var panel: StatusPanel = StatusPanel.new()
	var shown: String = _frame(panel, comfort)
	var reports: int = comfort.custom_notice.reports
	panel.free()
	if shown != "Custom file rejected: unknown" or comfort.number == CUSTOM:
		return "the launch switch shows \"%s\" on preset %d" % [shown, comfort.number]
	if reports != 1:
		return "the start was reported %d times, expected once" % reports
	return ""


func test_numbered_presets_are_unchanged_without_a_custom_file() -> String:
	var comfort: ComfortWiring = _comfort("", "missing.json")
	var panel: StatusPanel = StatusPanel.new()
	var shown: Array[String] = []
	var expected: Array[String] = []
	for number: int in [1, 2, 3, 4, 1]:
		comfort.set_preset(number)
		shown.append(_frame(panel, comfort))
		expected.append("Preset %d %s" % [number, comfort.preset.display_name])
	_press(comfort)
	_press(comfort)
	_press(comfort)
	_press(comfort)  # 4 > 1, no file: nothing to report.
	var reports: int = comfort.custom_notice.reports
	panel.free()
	if shown != expected:
		return "numbered presets show %s, expected %s" % [str(shown), str(expected)]
	if reports != 0 or comfort.number != 1:
		return "a missing file reported %d rejections, preset %d" % [reports, comfort.number]
	return ""


func test_the_words_and_time_come_from_the_look() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE))
	data["preset_custom_text"] = "Own {base}"
	data["preset_custom_rejected_text"] = "Bad {field}"
	data["preset_custom_rejected_seconds"] = 3
	var look: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
	if look.has("error"):
		return "a reworded look was rejected: %s" % look["error"]
	var holder: Node3D = Node3D.new()
	var row: StatusPanelPresetRow = StatusPanelPresetRow.new(holder, look)
	row.add_large(holder)
	row.show_custom_base(4)
	row.show(CUSTOM, "Custom", "")
	var named: String = (holder.get_node(StatusPanel.PRESET_NAME) as Label3D).text
	row.show_rejections(1, "base")
	row.show(CUSTOM, "Custom", "")
	var rejected: String = (holder.get_node(StatusPanel.PRESET_NAME) as Label3D).text
	row.advance(3.01)
	row.show(CUSTOM, "Custom", "")
	var after: String = (holder.get_node(StatusPanel.PRESET_NAME) as Label3D).text
	holder.free()
	if [named, rejected, after] != ["Own 4", "Bad base", "Own 4"]:
		return "reworded look shows %s" % str([named, rejected, after])
	data["preset_custom_rejected_seconds"] = 61
	if not StatusPanelLook.parse(JSON.stringify(data)).has("error"):
		return "a 61 s rejection time was accepted"
	return ""


func test_the_rejected_field_is_short() -> String:
	var cases: Dictionary = {
		"{\"base\": 7}": "base",
		"{\"base\": 1, \"yaw_mode\": \"SPIN\"}": "yaw_mode",
		"{\"base\": 1, \"break_reminder_minutes\": -1}": "break_reminder_minutes",
		"not json": "not JSON",
		"[1]": "not a JSON object",
		"{\"base\": 1}": "",
	}
	for text: String in cases:
		var got: String = ComfortCustom.parse(text).rejected_field()
		if got != cases[text]:
			return "%s gives field \"%s\", expected \"%s\"" % [text, got, cases[text]]
	return ""
