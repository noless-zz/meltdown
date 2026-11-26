extends RefCounted

## Checklist files (#1325, DEV-6, ARC-4): the shipped one reads, and every bad
## field is refused with the field named.

const MINIMAL: String = '{"id": "t1", "title": "T", "parts": [{"title": "P", "steps": [%s]}]}'
const STEP: String = '{"id": "s1", "do": "Do it.", "look_for": "It works."%s}'


static func with_step(extra: String) -> Checklist:
	return Checklist.parse(MINIMAL % (STEP % extra))


func test_every_shipped_checklist_reads() -> String:
	var found: Array[String] = Checklist.files()
	if found.is_empty():
		return "no checklist ships in %s" % Checklist.DIR
	for path: String in found:
		var checklist: Checklist = Checklist.load_file(path)
		if not checklist.is_valid():
			return "%s: %s" % [path, checklist.error]
		if "%s.json" % checklist.id != path.get_file():
			return "%s has id %s; name the file after it" % [path, checklist.id]
	return ""


func test_the_g6_checklist_carries_the_gate_and_its_owed_checks() -> String:
	var checklist: Checklist = Checklist.load_file(Checklist.DIR.path_join("g6.json"))
	if checklist.issue != 1304:
		return "issue %d, want the G6 gate #1304" % checklist.issue
	for step_id: String in ["base_room", "suspend_resume", "return_to_base", "device_suites", "sensitive_tester"]:
		if checklist.step(step_id) == null:
			return "no step %s" % step_id
	if checklist.step("sensitive_tester").action != ChecklistStep.ACTION_COMFORT:
		return "the sensitive tester's step does not set preset 1"
	return ""


func test_a_minimal_file_reads_with_parts_and_remarks_defaulted() -> String:
	var checklist: Checklist = Checklist.parse(
		'{"id": "t1", "title": "T", "remarks": ["meh"], "parts": [{"title": "A", "steps": [%s]}, {"title": "B", "steps": [%s]}]}'
		% [STEP % "", '{"id": "s2", "do": "x", "look_for": "y", "remarks": ["own"]}'])
	if not checklist.is_valid():
		return checklist.error
	if checklist.parts != ["A", "B"] or checklist.steps[1].part != 1:
		return "parts %s, second step in part %d" % [checklist.parts, checklist.steps[1].part]
	if checklist.steps[0].remarks != ["meh"] or checklist.steps[1].remarks != ["own"]:
		return "remarks %s and %s" % [checklist.steps[0].remarks, checklist.steps[1].remarks]
	return ""


func test_actions_read_into_kind_and_value() -> String:
	var cases: Dictionary = {
		', "action": {"comfort": 3}': [ChecklistStep.ACTION_COMFORT, "3", "set comfort preset 3"],
		', "action": {"seed": 31}': [ChecklistStep.ACTION_SEED, "31", "fly seed #31"],
		', "action": {"level": "res://data/levels/g2_level.json"}': [ChecklistStep.ACTION_LEVEL, "res://data/levels/g2_level.json", "fly g2_level"],
		', "action": {"tunnel": true}': [ChecklistStep.ACTION_TUNNEL, "", "fly the test tunnel"],
	}
	for extra: String in cases:
		var checklist: Checklist = with_step(extra)
		if not checklist.is_valid():
			return "%s: %s" % [extra, checklist.error]
		var step: ChecklistStep = checklist.steps[0]
		if [step.action, step.action_value, step.action_text()] != cases[extra]:
			return "%s read as %s" % [extra, [step.action, step.action_value, step.action_text()]]
	return ""


func test_bad_files_are_refused_naming_the_field() -> String:
	var cases: Dictionary = {
		"[]": "JSON object",
		'{"id": "t1", "title": "T", "parts": [], "extra": 1}': "unknown key \"extra\"",
		'{"id": "T 1", "title": "T", "parts": []}': "\"id\"",
		'{"id": "t1", "title": " ", "parts": []}': "\"title\"",
		'{"id": "t1", "title": "T", "issue": 0, "parts": []}': "\"issue\"",
		'{"id": "t1", "title": "T", "parts": []}': "\"parts\"",
		'{"id": "t1", "title": "T", "remarks": [""], "parts": []}': "\"remarks\"",
		'{"id": "t1", "title": "T", "parts": [{"title": "P", "steps": []}]}': "\"steps\"",
	}
	for text: String in cases:
		var checklist: Checklist = Checklist.parse(text)
		if checklist.is_valid() or not checklist.error.contains(cases[text]):
			return "%s gave error \"%s\", want one naming %s" % [text, checklist.error, cases[text]]
	return ""


func test_bad_steps_and_actions_are_refused() -> String:
	var cases: Dictionary = {
		', "colour": "red"': "unknown key \"colour\"",
		', "look_for": ""': "\"look_for\"",
		', "action": {"comfort": 5}': "\"comfort\"",
		', "action": {"comfort": 1.5}': "\"comfort\"",
		', "action": {"seed": -1}': "\"seed\"",
		', "action": {"level": "res://data/levels/no_such_level.json"}': "\"level\"",
		', "action": {"tunnel": false}': "\"tunnel\"",
		', "action": {"comfort": 1, "seed": 2}': "one of",
		', "action": {"warp": 1}': "unknown action",
		', "remarks": "meh"': "\"remarks\"",
	}
	for extra: String in cases:
		var checklist: Checklist = with_step(extra)
		if checklist.is_valid() or not checklist.error.contains(cases[extra]):
			return "%s gave error \"%s\"" % [extra, checklist.error]
		if not checklist.error.begins_with("part 1: step 1"):
			return "the error does not say where: %s" % checklist.error
	return ""


func test_a_step_id_given_twice_is_refused() -> String:
	var checklist: Checklist = Checklist.parse(MINIMAL % ("%s, %s" % [STEP % "", STEP % ""]))
	return "" if not checklist.is_valid() and checklist.error.contains("given twice") else "error \"%s\"" % checklist.error


func test_a_missing_file_is_refused() -> String:
	var checklist: Checklist = Checklist.load_file("res://data/checklists/none.json")
	return "" if not checklist.is_valid() and checklist.error == "file not found" else checklist.error
