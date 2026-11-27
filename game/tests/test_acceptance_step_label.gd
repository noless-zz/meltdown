extends RefCounted

## The cockpit's acceptance step label (#1438, DEV-6, CMF-8, ARC-3): its text,
## its look file, where it sits, and how the wiring reads the runner.

const STEP_START: String = "Meltdown: acceptance: step %s"


func _suite(suite_name: String, ids: Array[String]) -> AcceptanceSuite:
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = suite_name
	for id: String in ids:
		var step: AcceptanceStep = AcceptanceStep.new()
		step.id = id
		suite.steps.append(step)
	return suite


func _write(text: String) -> String:
	var path: String = "user://test_acceptance_step_label.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_text_names_suite_number_count_and_step() -> String:
	var cases: Array[Array] = [
		[["m1", 3, 9, "frame_budget"], "m1  3/9  frame_budget"],
		[["m6", 12, 31, "wall_depth"], "m6  12/31  wall_depth"],
		[["m1", 3, 0, "frame_budget"], "m1  3  frame_budget"],
		[["m1", 0, 9, ""], "m1"],
	]
	for case: Array in cases:
		var args: Array = case[0]
		var got: String = AcceptanceStepLabel.text_for(args[0], args[1], args[2], args[3])
		if got != case[1]:
			return "%s gave '%s', not '%s'" % [args, got, case[1]]
	return ""


func test_the_shipped_look_is_read() -> String:
	var got: Array = AcceptanceStepLabel.read_look()
	if got[1] != "":
		return got[1]
	var at: Vector3 = got[0]["position_m"]
	if at.z >= 0.0 or at.y >= 0.0:
		return "the label sits at %s; it belongs low and ahead" % at
	return ""


func test_a_bad_look_names_its_field_and_keeps_the_fallback() -> String:
	var good: String = FileAccess.get_file_as_string(AcceptanceStepLabel.DEFAULT_FILE)
	var cases: Dictionary = {
		good.replace("\"font_size\": 48", "\"font_size\": 2"): "font_size",
		good.replace("[0.0, -0.3, -0.5]", "[0.0, -0.3, 0.5]"): "position_m",
		good.replace("[1.0, 0.85, 0.3]", "[1.0, 2.0, 0.3]"): "color",
		good.replace("\"outline_size\"", "\"outline\""): "outline_size",
		"[]": "not a JSON object",
	}
	for text: String in cases:
		var got: Array = AcceptanceStepLabel.read_look(_write(text))
		if not (got[1] as String).contains(cases[text]):
			return "a file with a bad %s gave error '%s'" % [cases[text], got[1]]
		if got[0]["position_m"] != AcceptanceStepLabel.FALLBACK["position_m"]:
			return "a rejected file did not leave the fallback look"
	return ""


func test_the_label_faces_the_eye_and_moves_only_with_the_cockpit() -> String:
	var label: AcceptanceStepLabel = AcceptanceStepLabel.new()
	var problem: String = ""
	var cockpit: Transform3D = Transform3D(Basis(Vector3.UP, 0.4), Vector3(0.1, 1.2, -0.3))
	label.place(cockpit)
	var seen: Transform3D = cockpit.affine_inverse() * label.transform
	var to_eye: Vector3 = -seen.origin.normalized()
	if not seen.origin.is_equal_approx(label.look["position_m"]):
		problem = "the label sits at %s in the cockpit, not %s" % [seen.origin, label.look["position_m"]]
	elif seen.basis.z.normalized().dot(to_eye) < 0.99:
		problem = "the label's face points along %s, not at the eye" % seen.basis.z
	label.free()
	return problem


func test_shown_text_hides_an_empty_label() -> String:
	var label: AcceptanceStepLabel = AcceptanceStepLabel.new()
	label.show_text("m1  1/9  basic_flight")
	var shown: bool = label.visible and label.label.text == "m1  1/9  basic_flight"
	label.show_text("")
	var hidden: bool = not label.visible
	label.free()
	return "" if shown and hidden else "shown %s, hidden %s" % [shown, hidden]


func test_the_wiring_reads_the_current_step_from_the_runner_lines() -> String:
	var suites: Array[AcceptanceSuite] = [_suite("m0", ["boot"]), _suite("m1", ["basic_flight", "flight_axes", "frame_budget"])]
	var lines: PackedStringArray = PackedStringArray([STEP_START % "boot", (STEP_START % "boot") + " pass"])
	var cases: Array[Array] = [
		[0, PackedStringArray(), ""],
		[1, PackedStringArray([STEP_START % "boot"]), "m0  1/1  boot"],
		[2, lines, "m1"],
		[2, lines + PackedStringArray([STEP_START % "flight_axes"]), "m1  2/3  flight_axes"],
		[2, lines + PackedStringArray([(STEP_START % "frame_budget") + " fail suite=m1 index=3 count=3 (time limit)"]),
			"m1  3/3  frame_budget"],
		[3, lines, ""],
	]
	for case: Array in cases:
		var got: String = AcceptanceStepLabelWiring.text_for_run(suites, case[0], case[1])
		if got != case[2]:
			return "%d suites begun, lines %s: '%s', not '%s'" % [case[0], case[1], got, case[2]]
	return ""


func test_no_runner_no_label() -> String:
	var main: Node = Node.new()
	var wiring: AcceptanceStepLabelWiring = AcceptanceStepLabelWiring.attach(main, null)
	var problem: String = "" if wiring == null and main.get_child_count() == 0 else "a label without an acceptance run"
	main.free()
	return problem
