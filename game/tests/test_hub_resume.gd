extends RefCounted

## The hub offers to resume a suspended run (RUN-8, CRW-2, ARC-4, #1106): with no
## waiting run the launch page has no resume row and `resume` refuses with the
## reason; with one, the page's first row shows the saved level and seed and
## `resume` gives the action, and the launch row's discard note shows only then.

const SHIP_PATH: String = "res://data/ships/default_ship.json"
const ROLES_PATH: String = "res://data/crew/roles.json"
const LEVEL: int = 3
const SEED: int = 9876543210


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


## A hub on its launch page, with `save` waiting (null for none).
static func _hub(save: RunSave) -> HubText:
	var model: HubModel = HubModel.create(
		HubConfig.load_shipped(),
		Profile.new(),
		CrewRoles.parse_json(FileAccess.get_file_as_string(ROLES_PATH)),
		ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR)),
		UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR)),
		Fitting.new(),
		JSON.parse_string(FileAccess.get_file_as_string(SHIP_PATH)))
	model.set_waiting(save)
	var hub: HubText = HubText.new(model)
	for i: int in model.pages().size():
		if hub.page_id() == HubConfig.FIT:
			break
		hub.turn_page(1)
	hub.row = 0
	return hub


static func _save() -> RunSave:
	var save: RunSave = RunSave.new()
	save.run_seed = SEED
	save.next_level = LEVEL
	save.ship = "default_ship"
	return save


func _words() -> HubWords:
	return HubConfig.load_shipped().words


func test_the_file_has_the_resume_words() -> String:
	var words: HubWords = _words()
	if HubWords.PLACEHOLDERS.get("resume_row", []) != ["level", "seed"]:
		return "resume_row should take {level} and {seed}"
	if words.row("resume_row") == "" or words.row("launch_discard_note") == "":
		return "hub.json lacks resume_row or launch_discard_note"
	return ""


func test_no_waiting_run_has_no_resume_row_and_resume_refuses() -> String:
	var hub: HubText = _hub(null)
	var resume_text: String = _words().row("resume_row", {"level": LEVEL, "seed": SEED})
	var note: String = _words().row("launch_discard_note")
	var lines: Array[String] = hub.lines()
	if lines.has(resume_text) or lines.has(note):
		return "a resume row or discard note shows with no waiting run: %s" % str(lines)
	if hub.model.run_waits() or not hub.model.waiting().is_empty():
		return "the model says a run waits"
	var result: Variant = hub.model.resume()
	if typeof(result) != TYPE_STRING or str(result) != HubModel.NO_RUN_WAITING:
		return "resume gave %s, expected the reason \"%s\"" % [str(result), HubModel.NO_RUN_WAITING]
	if lines[lines.size() - 1] != _words().row("launch_row"):
		return "the launch row is no longer last: %s" % str(lines)
	return ""


func test_a_waiting_run_shows_level_and_seed_first_and_resumes() -> String:
	var hub: HubText = _hub(_save())
	var lines: Array[String] = hub.lines()
	var expected: String = _words().row("resume_row", {"level": LEVEL, "seed": SEED})
	if lines.size() < 2 or lines[1] != expected:
		return "first row was %s, expected \"%s\"" % [str(lines.slice(1, 2)), expected]
	if not expected.contains(str(LEVEL)) or not expected.contains(str(SEED)):
		return "the row \"%s\" lacks the level or the seed" % expected
	if hub.selected() != {"action": HubText.ACTION_RESUME}:
		return "the first selected row acts %s" % str(hub.selected())
	var result: Variant = hub.model.resume()
	if typeof(result) != TYPE_DICTIONARY or result != {"resume": true}:
		return "resume gave %s" % str(result)
	var reason: String = hub.press()
	if reason != "" or hub.resumed != {"resume": true}:
		return "pressing resume gave reason \"%s\", resumed %s" % [reason, str(hub.resumed)]
	return ""


func test_the_discard_note_sits_under_the_launch_row_only_when_a_run_waits() -> String:
	var hub: HubText = _hub(_save())
	var lines: Array[String] = hub.lines()
	var launch: int = lines.find(_words().row("launch_row"))
	if launch < 0 or launch + 1 >= lines.size() or lines[launch + 1] != _words().row("launch_discard_note"):
		return "no discard note under the launch row: %s" % str(lines)
	# The note is not selectable: the last selectable line is still the launch row.
	hub.move(1000)
	if hub.selected_line() != launch or hub.selected() != {"action": HubText.ACTION_LAUNCH}:
		return "the last selectable line is %d, launch is %d" % [hub.selected_line(), launch]
	return ""


func test_launch_is_unchanged_while_a_run_waits() -> String:
	var plain: HubText = _hub(null)
	var waiting: HubText = _hub(_save())
	if plain.model.launch() != waiting.model.launch() or plain.model.launch_check() != waiting.model.launch_check():
		return "launch differs while a run waits"
	return ""
