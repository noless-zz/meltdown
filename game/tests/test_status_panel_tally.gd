extends RefCounted

## The status panel's tally (#1356, CRF-1, CRF-2, SLV-3, PLT-2, MP-2): the
## owner could not tell a component was collected or a miner rescued, nor how
## many he carried. The tally counts both from plain copies, confirms each rise
## on the hold row, and draws a carried and a banked line within a glance down.

const NAMES: Dictionary[String, String] = {"cell_salts": "Cell Salts", "core_glass": "Core Glass"}


static func _tally() -> StatusPanelTally:
	return StatusPanelTally.new(StatusPanelLook.FALLBACK, NAMES)


func test_the_first_frame_only_remembers() -> String:
	var tally: StatusPanelTally = _tally()
	var said: String = tally.update({"cell_salts": 3}, 1, {}, false)
	if said != "" or tally.collected_confirmations != 0 or tally.miner_confirmations != 0:
		return "the first frame said \"%s\" (%d, %d)" % [said, tally.collected_confirmations,
			tally.miner_confirmations]
	if tally.row_text() != "Carried 3 Cell Salts | Miners 1":
		return "the row reads \"%s\"" % tally.row_text()
	return ""


func test_a_pickup_is_confirmed_with_its_count_and_name() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({}, 0, {}, false)
	var said: String = tally.update({"cell_salts": 2}, 0, {}, false)
	if said != "+2 Cell Salts":
		return "a pickup said \"%s\"" % said
	if tally.collected_confirmations != 1 or tally.flash_left != 1.0:
		return "confirmations %d, flash %.2f" % [tally.collected_confirmations, tally.flash_left]
	said = tally.update({"cell_salts": 2}, 0, {}, false)
	if said != "":
		return "an unchanged count said \"%s\"" % said
	said = tally.update({"cell_salts": 5, "core_glass": 1}, 0, {}, false)
	if said != "+3 Cell Salts" or tally.collected_confirmations != 3:
		return "two kinds rising said \"%s\", %d confirmations" % [said, tally.collected_confirmations]
	if tally.row_text() != "Carried 5 Cell Salts, 1 Core Glass | Miners 0":
		return "the row reads \"%s\"" % tally.row_text()
	return ""


func test_a_rescue_says_miner_aboard_and_outranks_a_pickup() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({}, 0, {}, false)
	var said: String = tally.update({"cell_salts": 1}, 1, {}, false)
	if said != "Miner aboard":
		return "a rescue with a pickup said \"%s\"" % said
	if tally.miner_confirmations != 1 or tally.collected_confirmations != 1 or tally.miners != 1:
		return "confirmations %d and %d, %d aboard" % [tally.miner_confirmations,
			tally.collected_confirmations, tally.miners]
	return ""


func test_a_new_level_resets_the_count_without_a_message() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({}, 0, {}, true)
	tally.update({"cell_salts": 4}, 1, {}, true)
	var said: String = tally.update({}, 0, {"cell_salts": 4}, true)
	if said != "":
		return "the next level's start said \"%s\"" % said
	if tally.row_text() != "Carried none | Miners 0":
		return "the row reads \"%s\"" % tally.row_text()
	if tally.banked_text() != "Banked 4 Cell Salts":
		return "the banked line reads \"%s\"" % tally.banked_text()
	return ""


func test_the_banked_line_shows_only_in_a_run() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({}, 0, {}, false)
	if tally.banked_text() != "":
		return "outside a run the banked line reads \"%s\"" % tally.banked_text()
	tally.update({}, 0, {}, true)
	if tally.banked_text() != "Banked none":
		return "a run with nothing banked reads \"%s\"" % tally.banked_text()
	return ""


func test_an_unknown_kind_shows_its_id() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({"odd_kind": 2, "zero": 0}, 0, {}, false)
	if tally.row_text() != "Carried 2 odd_kind | Miners 0":
		return "the row reads \"%s\"" % tally.row_text()
	return ""


func test_the_flash_runs_out() -> String:
	var tally: StatusPanelTally = _tally()
	tally.update({}, 0, {}, false)
	tally.update({}, 1, {}, false)
	tally.advance(0.6)
	if tally.flash_left <= 0.0:
		return "the flash ended after 0.6 s"
	tally.advance(0.6)
	if tally.flash_left != 0.0:
		return "the flash has %.2f s left after 1.2 s" % tally.flash_left
	return ""


func test_the_shipped_names_come_from_the_component_files() -> String:
	var names: Dictionary[String, String] = StatusPanelTally.shipped_names()
	if names.get("cell_salts", "") != "Cell Salts" or names.size() < 4:
		return "shipped names: %s" % [names]
	if not StatusPanelTally.shipped_names("res://no/such/dir").is_empty():
		return "a missing folder gave names"
	return ""


func test_the_shipped_look_words_the_tally() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	for key: String in ["tally_text", "tally_banked_text", "tally_none_text", "tally_collected_text",
			"tally_miner_text", "tally_flash_color", "tally_flash_seconds"]:
		if not look.has(key) or look[key] != StatusPanelLook.FALLBACK[key]:
			return "the shipped look's %s is %s, the fallback's %s" % [key, look.get(key),
				StatusPanelLook.FALLBACK[key]]
	if not (look["rows"] as Array).has("tally"):
		return "the shipped panel does not draw the tally: %s" % [look["rows"]]
	var rejected: Dictionary = StatusPanelLook.parse('{"escaped_color": [0, 1, 0], "position_m": [0, -0.2, -0.5], '
		+ '"tilt_deg": 19, "max_row_angle_deg": 30, "message_seconds": 2, "tally_miner_text": " "}')
	if not rejected.has("error") or not String(rejected["error"]).contains("tally_miner_text"):
		return "a blank miner text was taken: %s" % [rejected]
	return ""


func test_the_panel_feeds_the_hold_row_and_tints_the_line() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var said: String = panel.tally_row.show_counts({}, 0, {}, true)
	said = panel.tally_row.show_counts({}, 1, {}, true)
	var texts: Dictionary = panel.texts()
	var flashing: bool = panel.tally_row.flashing()
	panel.tally_row.advance(2.0)
	var after: bool = panel.tally_row.flashing()
	var drawn: bool = StatusPanelRowList.drawn(panel, "tally")
	panel.free()
	if said != "Miner aboard":
		return "the row returned \"%s\"" % said
	if texts.get(StatusPanelTallyRow.NAME) != "Carried none | Miners 1" \
			or texts.get(StatusPanelTallyRow.BANKED_NAME) != "Banked none":
		return "the panel shows %s" % [texts]
	if not flashing or after:
		return "flash at the rescue %s, after 2 s %s" % [flashing, after]
	if not drawn:
		return "the shipped panel does not draw the tally rows"
	return ""


## The tally's two lines sit above the countdown, the banked line on top, the
## outcome row clear of them, and both within the glance limits on every preset
## (preset 1 included), below the eye line, with two weapon slots.
func test_the_tally_lines_sit_on_top_within_a_glance() -> String:
	var limit: float = float(StatusPanelLook.load_file()["max_row_angle_deg"])
	for number: int in [1, 2, 3, 4]:
		var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.for_preset(ComfortPresetFiles.load_number(number)))
		var panel: StatusPanel = StatusPanel.new()
		panel.show_weapons(["Pulse Cannon", "Needle Gun"] as Array[String])
		RigViews.place(HeadRecentre.new(), frame, panel)
		var eye: Transform3D = frame.transform.affine_inverse()
		var heights: Array[float] = []
		var downs: Array[float] = []
		for row: String in [StatusPanel.OUTCOME_NAME, StatusPanelTallyRow.BANKED_NAME, StatusPanelTallyRow.NAME,
				StatusPanel.MELTDOWN_NAME]:
			var y: float = (panel.get_node(row) as Node3D).position.y
			heights.append(y)
			downs.append(-CockpitGeometry.yaw_pitch(eye * panel.transform * Vector3(0.0, y, 0.0)).y)
		panel.free()
		frame.free()
		for index: int in range(1, heights.size()):
			if heights[index - 1] - heights[index] < 0.025:
				return "preset %d: rows too close or out of order: %s" % [number, heights]
		if downs[1] <= 0.0 or downs[2] > limit:
			return "preset %d: the tally lines are %.1f and %.1f degrees down" % [number, downs[1], downs[2]]
	return ""
