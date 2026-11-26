extends RefCounted

## The test checklist in the headset (#1325, DEV-6, ARC-3, MP-2, CMF-8): only
## development builds offer it; the dev menu entry opens it; marks go through
## the stick and A and are saved with the context; a step's action takes the
## dev menu's own choice; the open page takes the controls and pauses solo play.

const Menu := preload("res://tests/test_dev_menu_wiring.gd")
const SCRATCH: String = "user://test_checklist_wiring_"
const FILE: String = "user://test_checklist_wiring_t1.json"


## A checklist wired to a dev menu, with its choices collected in `applied`.
static func wired(applied: Array[String], available: bool = true) -> Array:
	var restarts: Array[String] = []
	var menu: DevMenuWiring = Menu.wired("seed:5", restarts)
	var checklist: ChecklistWiring = ChecklistWiring.new()
	checklist.available = available
	checklist.store.prefix = SCRATCH
	DirAccess.remove_absolute(checklist.store.path_for("t1"))
	checklist.apply_choice = func(choice: String) -> void: applied.append(choice)
	var path: String = Menu.scratch("checklist_t1.json")
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(ChecklistFixtures.TEXT)
	file.close()
	var level_start: LevelStart = LevelStart.new()
	level_start.source = "seed:5"
	checklist.attach(null, menu, null, level_start, Callable(), "abc123", path)
	return [menu, checklist]


static func done(pair: Array) -> void:
	Menu.done(pair[0])
	var checklist: ChecklistWiring = pair[1]
	if checklist.page != null:
		checklist.page.free()


static func press(checklist: ChecklistWiring, values: Dictionary) -> Dictionary:
	var passed: Dictionary = checklist.read(values)
	checklist.read(Menu.pad_values())
	return passed


static func confirm(checklist: ChecklistWiring) -> void:
	press(checklist, Menu.pad_values({"right_button_lower": true}))


static func right(checklist: ChecklistWiring) -> void:
	var values: Dictionary = Menu.pad_values()
	values["right_stick"] = Vector2(1.0, 0.0)
	press(checklist, values)


func test_a_release_build_attaches_nothing_and_the_menu_hides_the_row() -> String:
	var pair: Array = wired([], false)
	var menu: DevMenuWiring = pair[0]
	var checklist: ChecklistWiring = pair[1]
	var entry: DevMenuChecklist = menu.entry_for(DevMenuSpec.KIND_CHECKLIST) as DevMenuChecklist
	entry.show_on(menu.menu.model)
	var shown: bool = menu.menu.model.checklist_shown
	var problem: String = ""
	if checklist.page != null or shown:
		problem = "page %s, row shown %s" % [checklist.page, shown]
	done(pair)
	return problem


func test_the_menu_row_opens_the_page_on_the_next_step() -> String:
	var pair: Array = wired([])
	var menu: DevMenuWiring = pair[0]
	var checklist: ChecklistWiring = pair[1]
	Menu.tap(menu, 1.0)
	var at: float = Menu.select(menu, DevMenuSpec.KIND_CHECKLIST, 2.0)
	Menu.confirm(menu, at)
	var problem: String = ""
	if menu.is_open() or not checklist.is_open():
		problem = "menu open %s, page open %s" % [menu.is_open(), checklist.is_open()]
	elif not checklist.page.text().contains("Do: A"):
		problem = "page shows %s" % checklist.page.text()
	done(pair)
	return problem


func test_a_marks_the_step_and_saves_it_with_the_context() -> String:
	var pair: Array = wired([])
	var checklist: ChecklistWiring = pair[1]
	checklist.open()
	checklist.read(Menu.pad_values())  # The opening press let go.
	right(checklist)
	confirm(checklist)
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(FILE))
	var problem: String = ""
	if typeof(data) != TYPE_DICTIONARY:
		problem = "no results file at %s" % FILE
	else:
		var first: Dictionary = data["steps"][0]
		if first["mark"] != "fail" or first["source"] != "seed:5" or data["build"] != "abc123":
			problem = "saved %s" % [data]
		elif checklist.model.step != 1 or not checklist.page.text().contains("Do: B"):
			problem = "the page stayed on step %d" % checklist.model.step
	done(pair)
	return problem


func test_the_open_page_takes_the_controls_and_the_pinned_one_does_not() -> String:
	var pair: Array = wired([])
	var checklist: ChecklistWiring = pair[1]
	checklist.open()
	var values: Dictionary = Menu.pad_values({"right_button_lower": true})
	values["left_stick"] = Vector2(0.0, 1.0)
	var open_passed: Dictionary = checklist.read(values)
	checklist.pin()
	checklist.read(Menu.pad_values())
	var pinned_passed: Dictionary = checklist.read(values)
	var problem: String = ""
	if open_passed["left_stick"] != Vector2.ZERO or bool(open_passed["buttons"].get("right_button_lower", false)):
		problem = "the open page let %s through" % open_passed
	elif pinned_passed["left_stick"] != Vector2(0.0, 1.0) or not checklist.is_pinned():
		problem = "the pinned page held %s" % pinned_passed
	done(pair)
	return problem


func test_do_takes_the_dev_menu_choice_and_pins_the_page() -> String:
	var applied: Array[String] = []
	var pair: Array = wired(applied)
	var checklist: ChecklistWiring = pair[1]
	checklist.open()
	checklist.read(Menu.pad_values())
	checklist.model.choice = checklist.model.choices().find(ChecklistPageModel.DO)
	confirm(checklist)
	var problem: String = ""
	if applied != ["comfort:1"] or not checklist.is_pinned():
		problem = "applied %s, pinned %s" % [applied, checklist.is_pinned()]
	elif checklist.page.text() != "1/3  A":
		problem = "pinned shows %s" % checklist.page.text()
	done(pair)
	return problem


func test_each_action_maps_to_the_dev_menus_own_choice() -> String:
	var cases: Dictionary = {
		{"comfort": 3}: "comfort:3",
		{"seed": 31}: "level:seed:31",
		{"level": "res://data/levels/g2_level.json"}: "level:res://data/levels/g2_level.json",
		{"tunnel": true}: "level:",
	}
	for action: Dictionary in cases:
		var step: ChecklistStep = ChecklistStep.new()
		var problem: String = Checklist._read_action(action, step)
		if problem != "" or ChecklistWiring.menu_choice(step) != cases[action]:
			return "%s gave %s %s" % [action, problem, ChecklistWiring.menu_choice(step)]
	return ""


func test_the_open_page_pauses_the_solo_session_under_its_own_reason() -> String:
	var pair: Array = wired([])
	var checklist: ChecklistWiring = pair[1]
	var session: LocalSession = LevelStart.tunnel_session(LatestInputSource.new())
	checklist._session_of = func() -> LocalSession: return session
	checklist.open()
	checklist.read(Menu.pad_values())
	var while_open: bool = session.paused_by(ChecklistWiring.PAUSE_REASON)
	checklist.close()
	checklist.read(Menu.pad_values())
	var after: bool = session.paused
	done(pair)
	return "" if while_open and not after else "paused while open %s, after %s" % [while_open, after]


func test_the_shipped_checklist_attaches_in_a_development_build() -> String:
	var menu: DevMenuWiring = Menu.wired("", [] as Array[String])
	var checklist: ChecklistWiring = ChecklistWiring.new()
	checklist.available = true
	checklist.store.prefix = SCRATCH
	checklist.attach(null, menu, null, null)
	var problem: String = ""
	if checklist.checklist == null or checklist.checklist.id != "g6":
		problem = "attached %s" % checklist.checklist
	if checklist.page != null:
		checklist.page.free()
	Menu.done(menu)
	return problem
