extends RefCounted

## The hub offers to resume a suspended run (RUN-8, CRW-2, ARC-4, #1106): with no
## waiting run the launch page has no resume row and `resume` refuses with the
## reason; with one, the row directly above the launch row (#1172) shows the
## saved level and seed and `resume` gives the action, and the launch row's
## discard note shows only then.

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
	if HubWords.PLACEHOLDERS.get("resume_row", []) != ["level"] or HubWords.PLACEHOLDERS.get("resume_note", []) != ["seed"]:
		return "resume_row should take {level} and resume_note {seed} (#1300)"
	if words.row("resume_row") == "" or words.row("launch_discard_note") == "":
		return "hub.json lacks resume_row or launch_discard_note"
	return ""


func test_no_waiting_run_has_no_resume_row_and_resume_refuses() -> String:
	var hub: HubText = _hub(null)
	var resume_text: String = _words().row("resume_row", {"level": LEVEL, "seed": SEED})
	var lines: Array[String] = hub.lines()
	hub.move(1000)
	if lines.has(resume_text) or hub.note() != "":
		return "a resume row or discard note shows with no waiting run: %s, note \"%s\"" % [str(lines), hub.note()]
	if hub.model.run_waits() or not hub.model.waiting().is_empty():
		return "the model says a run waits"
	var result: Variant = hub.model.resume()
	if typeof(result) != TYPE_STRING or str(result) != HubModel.NO_RUN_WAITING:
		return "resume gave %s, expected the reason \"%s\"" % [str(result), HubModel.NO_RUN_WAITING]
	if lines[lines.size() - 1] != _words().row("launch_row"):
		return "the launch row is no longer last: %s" % str(lines)
	return ""


## Moves the selection onto the line `line` of `hub.lines()`; false if it never gets there.
static func _select_line(hub: HubText, line: int) -> bool:
	hub.move(-1000)
	for i: int in hub.lines().size():
		if hub.selected_line() == line:
			return true
		hub.move(1)
	return hub.selected_line() == line


func test_a_waiting_run_shows_level_and_seed_above_the_launch_row() -> String:
	var hub: HubText = _hub(_save())
	var lines: Array[String] = hub.lines()
	var expected: String = _words().row("resume_row", {"level": LEVEL, "seed": SEED})
	var resume: int = lines.find(expected)
	var launch: int = lines.find(_words().row("launch_row"))
	if resume < 0 or launch < 0:
		return "no resume row \"%s\" or launch row in %s" % [expected, str(lines)]
	if resume != launch - 1:
		return "the resume row is line %d, the launch row line %d: %s" % [resume, launch, str(lines)]
	if not expected.contains(str(LEVEL)):
		return "the row \"%s\" lacks the level" % expected
	# The seed is the resume row's note, shown only while it is selected (#1300).
	if not _select_line(hub, resume) or not hub.note().contains(str(SEED)):
		return "the selected resume row's note \"%s\" lacks the seed" % hub.note()
	return ""


func test_the_selection_starts_on_the_first_fitting_row() -> String:
	var hub: HubText = _hub(_save())
	var plain: HubText = _hub(null)
	if hub.selected_line() != 1 or hub.selected() == {"action": HubText.ACTION_RESUME}:
		return "the selection starts on line %d acting %s" % [hub.selected_line(), str(hub.selected())]
	if hub.lines()[1] != plain.lines()[1]:
		return "the first row is \"%s\", without a waiting run \"%s\"" % [hub.lines()[1], plain.lines()[1]]
	return ""


func test_pressing_the_resume_row_resumes() -> String:
	var hub: HubText = _hub(_save())
	var resume: int = hub.lines().find(_words().row("resume_row", {"level": LEVEL, "seed": SEED}))
	if not _select_line(hub, resume) or hub.selected() != {"action": HubText.ACTION_RESUME}:
		return "the resume row at line %d acts %s" % [resume, str(hub.selected())]
	var reason: String = hub.press()
	if reason != "" or hub.resumed != {"resume": true} or not hub.launched.is_empty():
		return "pressing resume gave reason \"%s\", resumed %s, launched %s" % [reason, str(hub.resumed), str(hub.launched)]
	return ""


func test_pressing_the_launch_row_launches_while_a_run_waits() -> String:
	var hub: HubText = _hub(_save())
	var plain: HubText = _hub(null)
	var launch: int = hub.lines().find(_words().row("launch_row"))
	if not _select_line(hub, launch) or hub.selected() != {"action": HubText.ACTION_LAUNCH}:
		return "the launch row at line %d acts %s" % [launch, str(hub.selected())]
	var reason: String = hub.press()
	if reason != "" or hub.launched.is_empty() or hub.launched != plain.model.launch() or not hub.resumed.is_empty():
		return "pressing launch gave reason \"%s\", launched %s, resumed %s" % [reason, str(hub.launched), str(hub.resumed)]
	return ""


func test_no_waiting_run_leaves_the_page_as_before() -> String:
	var hub: HubText = _hub(null)
	var lines: Array[String] = hub.lines()
	if lines.has(_words().row("resume_row", {"level": LEVEL, "seed": SEED})):
		return "a resume row with no waiting run: %s" % str(lines)
	for i: int in lines.size():
		if hub.selected() == {"action": HubText.ACTION_RESUME}:
			return "a selectable resume row with no waiting run"
		hub.move(1)
	return ""


## The discard warning is the launch row's note, shown only while it is selected (#1300).
func test_the_discard_note_sits_under_the_launch_row_only_when_a_run_waits() -> String:
	var hub: HubText = _hub(_save())
	var lines: Array[String] = hub.lines()
	var launch: int = lines.find(_words().row("launch_row"))
	if launch != lines.size() - 1 or lines.has(_words().row("launch_discard_note")):
		return "the launch row is not last or the note is a row of its own: %s" % str(lines)
	hub.move(1000)
	if hub.selected_line() != launch or hub.selected() != {"action": HubText.ACTION_LAUNCH}:
		return "the last selectable line is %d, launch is %d" % [hub.selected_line(), launch]
	if hub.note() != _words().row("launch_discard_note"):
		return "the selected launch row's note is \"%s\"" % hub.note()
	hub.move(-1)
	if hub.note() == _words().row("launch_discard_note"):
		return "the discard note shows under another row"
	return ""


func test_launch_is_unchanged_while_a_run_waits() -> String:
	var plain: HubText = _hub(null)
	var waiting: HubText = _hub(_save())
	if plain.model.launch() != waiting.model.launch() or plain.model.launch_check() != waiting.model.launch_check():
		return "launch differs while a run waits"
	return ""
