extends RefCounted

## The status panel in flight draws only what a pilot needs in a fight (#1207):
## hull, shield, energy, the meltdown countdown, the outcome, weapon and hold.
## The development rows keep their values for the dev menu's Info section but
## never draw, and which rows draw is a list in the look file (ARC-4).

const LOOK_FILE: String = "res://xr/status_panel_look.json"


## The shipped look file's text with `rows` set to `rows`.
static func _look_text(rows: Variant) -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	data["rows"] = rows
	return JSON.stringify(data)


func test_the_panel_in_flight_draws_exactly_the_listed_rows() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var wrong: Array[String] = []
	for row: String in StatusPanelRowList.names():
		if StatusPanelRowList.drawn(panel, row) != StatusPanelRowList.FIGHT.has(row):
			wrong.append(row)
	var rows: Array[String] = panel.rows
	panel.free()
	if not wrong.is_empty():
		return "rows drawn against the fight list: %s" % ", ".join(wrong)
	if rows != StatusPanelRowList.FIGHT:
		return "the panel lists %s" % [rows]
	return ""


func test_the_shipped_look_file_lists_the_fight_rows() -> String:
	var look: Dictionary = StatusPanelLook.parse(FileAccess.get_file_as_string(LOOK_FILE))
	if look.has("error"):
		return "the shipped look file is rejected: %s" % look["error"]
	if look["rows"] != StatusPanelRowList.FIGHT:
		return "the shipped file lists %s" % [look["rows"]]
	return ""


func test_every_panel_node_belongs_to_one_row() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var listed: Array[String] = []
	for row: String in StatusPanelRowList.NODES:
		for node_name: String in StatusPanelRowList.NODES[row]:
			listed.append(node_name)
	var missing: Array[String] = []
	for child: Node in panel.get_children():
		if child is VisualInstance3D and not listed.has(String(child.name)):
			missing.append(String(child.name))
	panel.free()
	if not missing.is_empty():
		return "panel nodes in no row, so the list cannot hide them: %s" % ", ".join(missing)
	return ""


func test_hidden_rows_stay_undrawn_when_they_show_themselves() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Cruise", 12.0, StatusPanel.BOOST_ON, "abc1234")
	var large_up: bool = panel.large_preset_visible()
	var large_drawn: bool = StatusPanelRowList.drawn(panel, "preset_large")
	panel.advance(StatusPanel.PRESET_LARGE_SECONDS + 0.1)
	var small_up: bool = (panel.get_node(StatusPanel.PRESET_NAME) as Label3D).visible
	var small_drawn: bool = StatusPanelRowList.drawn(panel, "preset")
	var speed_drawn: bool = StatusPanelRowList.drawn(panel, "speed")
	panel.free()
	if not large_up or not small_up:
		return "the preset rows should still show themselves (large %s, small %s)" % [large_up, small_up]
	if large_drawn or small_drawn or speed_drawn:
		return "a development row draws in flight (large %s, small %s, speed %s)" % [
			large_drawn, small_drawn, speed_drawn]
	return ""


func test_the_countdown_still_appears_when_the_meltdown_starts() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var before: bool = panel.meltdown_visible()
	panel.show_gauges(ShipGauges.of(1.0, 1.0, 1.0, 90.0))
	var after: bool = panel.meltdown_visible()
	var drawn: bool = StatusPanelRowList.drawn(panel, "meltdown")
	var text: String = panel.texts()[StatusPanel.MELTDOWN_NAME]
	panel.free()
	if before:
		return "the countdown shows before a meltdown"
	if not after or not drawn:
		return "the countdown does not appear at the meltdown (shown %s, drawn %s)" % [after, drawn]
	if text.strip_edges() == "":
		return "the countdown row is blank"
	return ""


func test_a_row_comes_back_from_the_file_without_code() -> String:
	var rows: Array = StatusPanelRowList.FIGHT.duplicate()
	rows.append("speed")
	var look: Dictionary = StatusPanelLook.parse(_look_text(rows))
	if look.has("error"):
		return "a list with speed is rejected: %s" % look["error"]
	var panel: StatusPanel = StatusPanel.new()
	panel.show_rows(look["rows"])
	var speed: bool = StatusPanelRowList.drawn(panel, "speed")
	var preset: bool = StatusPanelRowList.drawn(panel, "preset")
	panel.free()
	if not speed or preset:
		return "speed drawn %s and preset drawn %s; only speed was added" % [speed, preset]
	return ""


func test_a_look_file_without_rows_gets_the_fight_rows() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	data.erase("rows")
	var look: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
	if look.has("error"):
		return "a file without rows is rejected: %s" % look["error"]
	if look["rows"] != StatusPanelRowList.FIGHT:
		return "a file without rows gives %s" % [look["rows"]]
	return ""


func test_bad_row_lists_are_rejected_naming_the_field() -> String:
	var cases: Dictionary = {
		"unknown name": [["hull", "radar"], "radar"],
		"not text": [["hull", 3], "3"],
		"twice": [["hull", "hull"], "twice"],
		"not a list": ["hull", "list"],
	}
	for case: String in cases:
		var look: Dictionary = StatusPanelLook.parse(_look_text(cases[case][0]))
		var problem: String = str(look.get("error", ""))
		if problem == "":
			return "%s: the list %s was accepted" % [case, cases[case][0]]
		if not problem.contains("\"rows\"") or not problem.contains(str(cases[case][1])):
			return "%s: the message '%s' does not name the field and the fault" % [case, problem]
	return ""


func test_the_panel_corner_choice_is_unchanged() -> String:
	var corners: Dictionary = StatusPanelLook.shared()["corners"]
	var expected: Dictionary = {
		# Moved out of the middle of the view by #1452, then into both eyes' views by #1507.
		"top_left": Vector3(-0.245, 0.245, -0.550),
		"top_right": Vector3(0.297, 0.262, -0.515),
		"bottom_left": Vector3(-0.258, -0.223, -0.553),
		"bottom_right": Vector3(0.323, -0.174, -0.537),
	}
	for corner: String in expected:
		if not (corners[corner] as Vector3).is_equal_approx(expected[corner]):
			return "corner %s moved to %s" % [corner, corners[corner]]
	var placed: Transform3D = StatusPanelLook.placement(StatusPanelLook.shared(), "top_right")
	if not placed.origin.is_equal_approx(expected["top_right"]):
		return "the top right corner places the panel at %s" % placed.origin
	return ""
