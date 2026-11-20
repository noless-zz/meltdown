extends RefCounted

## The flight test panel and its words (#699, CMF-4, ARC-4): every manoeuvre
## has an instruction, a bad file is reported and not crashed on, and the panel
## shows the segment, the time, the answers and the result.

const EPSILON: float = 0.001


func _shipped_text() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FlightTestPanelText.DEFAULT_FILE))


func test_the_shipped_text_has_an_instruction_for_every_manoeuvre() -> String:
	var parsed: Dictionary = FlightTestPanelText.load_file()
	if parsed.has("error"):
		return "shipped panel text rejected: %s" % parsed["error"]
	for manoeuvre: String in FlightTestPlan.MANOEUVRES:
		if str(parsed["instructions"].get(manoeuvre, "")).strip_edges() == "":
			return "no instruction for %s" % manoeuvre
	return ""


# The built-in words are what the panel shows when the file is broken, so a
# manoeuvre added to the plan without them would leave a blank instruction (#720).
func test_the_built_in_words_match_the_plans_manoeuvres() -> String:
	var instructions: Dictionary = FlightTestPanelText.FALLBACK["instructions"]
	for manoeuvre: String in FlightTestPlan.MANOEUVRES:
		if str(instructions.get(manoeuvre, "")).strip_edges() == "":
			return "built-in words have no instruction for %s" % manoeuvre
	for key: Variant in instructions:
		if not FlightTestPlan.MANOEUVRES.has(str(key)):
			return "built-in words name %s, which the plan does not know" % str(key)
	var parsed: Dictionary = FlightTestPanelText.parse(JSON.stringify(FlightTestPanelText.FALLBACK))
	if parsed.has("error"):
		return "built-in words rejected by the parser: %s" % parsed["error"]
	return ""


func test_bad_text_is_reported_naming_the_field() -> String:
	var cases: Array[Array] = []
	var bad_key: Dictionary = _shipped_text()
	bad_key["instructions"]["barrel_roll"] = "Spin"
	cases.append([bad_key, "barrel_roll"])
	var missing: Dictionary = _shipped_text()
	(missing["instructions"] as Dictionary).erase("manual_roll")
	cases.append([missing, "manual_roll"])
	var empty: Dictionary = _shipped_text()
	empty["instructions"]["snap_yaw"] = " "
	cases.append([empty, "instructions.snap_yaw"])
	var no_seconds: Dictionary = _shipped_text()
	no_seconds["time_left"] = "time left"
	cases.append([no_seconds, "time_left"])
	var raise: Dictionary = _shipped_text()
	raise["raise_m"] = 2.0
	cases.append([raise, "raise_m"])
	var extra: Dictionary = _shipped_text()
	extra["colour"] = "red"
	cases.append([extra, "colour"])
	for item: Array in cases:
		var parsed: Dictionary = FlightTestPanelText.parse(JSON.stringify(item[0]))
		if not parsed.has("error") or not str(parsed["error"]).contains(item[1]):
			return "bad text naming %s gave %s" % [item[1], parsed]
	if not FlightTestPanelText.parse("[1, 2").has("error"):
		return "broken JSON was accepted"
	return ""


func test_a_bad_file_keeps_the_built_in_words_and_reports() -> String:
	var path: String = "user://flight_test_panel_bad.json"
	var bad: Dictionary = _shipped_text()
	bad["instructions"]["barrel_roll"] = "Spin"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad))
	file.close()
	var panel: FlightTestPanel = FlightTestPanel.new(path)
	var result: String = ""
	if not panel.text_error.contains("barrel_roll"):
		result = "the bad manoeuvre key was not reported: \"%s\"" % panel.text_error
	elif panel.instruction("manual_roll") != FlightTestPanelText.FALLBACK["instructions"]["manual_roll"]:
		result = "the built-in words were not used"
	var missing: FlightTestPanel = FlightTestPanel.new("user://no_such_panel.json")
	if result == "" and missing.text_error == "":
		result = "a missing file was not reported"
	panel.free()
	missing.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result


func test_the_panel_shows_each_stage_of_the_test() -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file()
	var session: FlightTestSession = FlightTestSession.new(plan)
	var panel: FlightTestPanel = FlightTestPanel.new()
	var text: Dictionary = FlightTestPanelText.load_file()
	var result: String = ""
	session.advance(plan.segments[0].duration_s - 4.2)
	panel.show_session(session)
	var flying: Dictionary = panel.shown()
	if flying["main"] != text["instructions"][plan.segments[0].manoeuvre]:
		result = "while flying the panel shows \"%s\"" % flying["main"]
	elif flying["detail"] != "5 s" or flying["answers"] != "":
		result = "with 4.2 s left the panel shows %s" % [flying]
	session.advance(10.0)
	panel.show_session(session)
	var asking: Dictionary = panel.shown()
	if result == "" and (asking["detail"] != text["question"] or asking["answers"] != text["answers"]):
		result = "an answer due shows %s" % [asking]
	session.answer(PresetRecommender.STOP)
	panel.show_session(session)
	var done: Dictionary = panel.shown()
	if result == "" and (not str(done["main"]).contains(panel.preset_name(1)) or done["detail"] != text["change_hint"] \
			or done["answers"] != ""):
		result = "the end shows %s" % [done]
	if result == "" and not panel.preset_name(1).contains(ComfortPresetFiles.load_number(1).display_name):
		result = "preset 1's name is \"%s\"" % panel.preset_name(1)
	panel.free()
	return result


func test_the_panel_sits_at_the_status_panels_distance_and_size() -> String:
	var panel: FlightTestPanel = FlightTestPanel.new()
	var status: Transform3D = StatusPanel.rig_transform(Transform3D.IDENTITY)
	var here: Transform3D = panel.rig_transform(Transform3D.IDENTITY)
	var result: String = ""
	if absf(here.origin.distance_to(status.origin) - panel.raise_m()) > EPSILON:
		result = "the panel is %s m from the status panel, expected %s" % [here.origin.distance_to(status.origin), panel.raise_m()]
	elif not here.basis.is_equal_approx(status.basis):
		result = "the panel is not in the status panel's plane"
	for child: Node in panel.get_children():
		var label: Label3D = child as Label3D
		if result == "" and label != null and (not is_equal_approx(label.pixel_size, StatusPanel.PIXEL_SIZE) or label.font_size < StatusPanel.SMALL_FONT):
			result = "label %s is smaller than the status panel's text" % label.name
	panel.free()
	return result
