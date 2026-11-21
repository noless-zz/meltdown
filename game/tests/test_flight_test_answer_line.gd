extends RefCounted

## The flight test answer line names each answer's button (#764, CMF-4,
## ARC-4): built from answers.json and panel.json, following a remapped
## answers file, and falling back to the plain line on a bad template.

const SHIPPED_LINE: String = "A Fine     B Uneasy     Y Stop"


func _shipped_spec() -> Dictionary:
	var text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FlightTestPanelText.DEFAULT_FILE))
	return text["answer_line"]


func _write(path: String, data: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()


func _asking_panel(panel: FlightTestPanel) -> String:
	var plan: FlightTestPlan = FlightTestPlan.load_file()
	var session: FlightTestSession = FlightTestSession.new(plan)
	session.advance(plan.segments[0].duration_s + 1.0)
	if not session.awaiting_answer():
		return "<no answer due>"
	panel.show_session(session)
	return str(panel.shown()["answers"])


func test_the_shipped_files_give_a_fine_b_uneasy_y_stop() -> String:
	var panel: FlightTestPanel = FlightTestPanel.new()
	var shown: String = _asking_panel(panel)
	var error: String = panel.answer_line_error
	panel.free()
	if error != "":
		return "shipped answer line rejected: %s" % error
	if shown != SHIPPED_LINE:
		return "shipped answer line is \"%s\", expected \"%s\"" % [shown, SHIPPED_LINE]
	var built: Dictionary = FlightTestAnswerLine.build(_shipped_spec(), FlightTestAnswers.load_file().buttons)
	if built.get("line", "") != SHIPPED_LINE:
		return "built from the shipped files: %s" % [built]
	return ""


func test_the_built_in_words_give_the_same_line() -> String:
	var built: Dictionary = FlightTestAnswerLine.build(FlightTestPanelText.FALLBACK["answer_line"],
			FlightTestAnswers.DEFAULTS)
	if built.get("line", "") != SHIPPED_LINE:
		return "built-in answer line gave %s" % [built]
	return ""


func test_a_remapped_answers_file_changes_the_line() -> String:
	var path: String = "user://flight_test_answers_swapped.json"
	_write(path, {"fine": "right_button_upper", "uneasy": "right_button_lower", "stop": "left_button_upper"})
	var panel: FlightTestPanel = FlightTestPanel.new(FlightTestPanelText.DEFAULT_FILE, path)
	var shown: String = _asking_panel(panel)
	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if shown != "B Fine     A Uneasy     Y Stop":
		return "with fine on B and uneasy on A the line is \"%s\"" % shown
	var moved: Dictionary[String, String] = {"fine": "left_button_lower", "uneasy": "right_button_lower",
		"stop": "right_stick_click"}
	var other: FlightTestPanel = FlightTestPanel.new()
	other.set_buttons(moved)
	var line: String = other.answer_line()
	other.free()
	if line != "X Fine     A Uneasy     Right stick Stop":
		return "set_buttons gave \"%s\"" % line
	return ""


func test_a_template_without_a_placeholder_is_rejected_naming_the_field() -> String:
	for placeholder: String in ["{button}", "{answer}"]:
		var spec: Dictionary = _shipped_spec()
		spec["template"] = "{button} {answer}".replace(placeholder, "").strip_edges()
		var built: Dictionary = FlightTestAnswerLine.build(spec, FlightTestAnswers.DEFAULTS)
		var error: String = str(built.get("error", ""))
		if not error.contains("answer_line.template") or not error.contains(placeholder):
			return "a template without %s gave %s" % [placeholder, built]
	return ""


func test_a_bad_template_shows_the_old_line() -> String:
	var path: String = "user://flight_test_panel_bad_template.json"
	var text: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FlightTestPanelText.DEFAULT_FILE))
	text["answer_line"]["template"] = "{answer}"
	_write(path, text)
	var panel: FlightTestPanel = FlightTestPanel.new(path)
	var shown: String = _asking_panel(panel)
	var result: String = ""
	if panel.text_error != "":
		result = "a bad template rejected the whole panel text: %s" % panel.text_error
	elif not panel.answer_line_error.contains("answer_line.template"):
		result = "the bad template was not reported naming the field: \"%s\"" % panel.answer_line_error
	elif shown != text["answers"]:
		result = "a bad template shows \"%s\", expected the old line \"%s\"" % [shown, text["answers"]]
	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result


func test_other_bad_fields_are_named() -> String:
	var cases: Array[Array] = []
	var no_word: Dictionary = _shipped_spec()
	(no_word["words"] as Dictionary).erase("uneasy")
	cases.append([no_word, "answer_line.words.uneasy"])
	var no_name: Dictionary = _shipped_spec()
	(no_name["buttons"] as Dictionary).erase("left_button_upper")
	cases.append([no_name, "answer_line.buttons.left_button_upper"])
	var empty_separator: Dictionary = _shipped_spec()
	empty_separator["separator"] = ""
	cases.append([empty_separator, "answer_line.separator"])
	var extra: Dictionary = _shipped_spec()
	extra["colour"] = "red"
	cases.append([extra, "colour"])
	cases.append([null, "answer_line"])
	for item: Array in cases:
		var built: Dictionary = FlightTestAnswerLine.build(item[0], FlightTestAnswers.DEFAULTS)
		if not str(built.get("error", "")).contains(item[1]):
			return "bad answer line naming %s gave %s" % [item[1], built]
	return ""
