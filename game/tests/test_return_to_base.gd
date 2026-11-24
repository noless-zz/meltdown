extends RefCounted

## The menu's "Return to base" row (#1246, RUN-1, RUN-7, CRF-2, SLV-3, CRW-1,
## CRW-2, CMF-8, DEV-7): shown only while a run's level flies, a confirm step
## that moving or closing cancels, and an abandon that ends the run as a
## destroyed ship does, then fades to the hub. No scene: the menu, the run and
## the hub are built here, and the session restart is a recorded call.

const THREE_LEVELS: String = "{\"min_levels\": 3, \"max_levels\": 3, \"seed_salt\": 2654435769}"
const RUN_SEED: int = 12345
const NEXT_RUN_SEED: int = 77
const DIR: String = "user://t1246_return_to_base"
const FRAME: float = 1.0 / 72.0
const LEVEL_1_CARRY: Dictionary = {"scrap_alloy": 2, "cell_salts": 3}
## Picked up on level 2 before the pilot gives up; none of it may be banked.
const LEVEL_2_CARRY: Dictionary = {"core_glass": 2, "scrap_alloy": 5}


func _path(name: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path: String = "%s/%s.json" % [DIR, name]
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	return path


func _run(store: ProfileStore = null) -> RunWiring:
	return RunWiring.new(RUN_SEED, store, func() -> int: return NEXT_RUN_SEED, THREE_LEVELS, false)


func _flying(run: RunWiring) -> LevelStart:
	var level_start: LevelStart = LevelStart.new()
	level_start.run = run
	level_start.source = run.level_source() if run != null else ""
	return level_start


## A save as the shaft panel's suspend row leaves one.
func _saved(store: RunSaveStore) -> bool:
	var save: RunSave = RunSave.new()
	save.run_seed = RUN_SEED
	save.next_level = 2
	save.ship = "default_ship"
	save.loadout = {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}
	return store.save(save)


func _return_index(model: DevMenuModel) -> int:
	for index: int in model.spec.entries.size():
		if str(model.spec.entries[index]["kind"]) == DevMenuSpec.KIND_RETURN:
			return index
	return -1


## Presses `action` once: down on one frame, up on the next.
func _press(model: DevMenuModel, action: String) -> String:
	var result: String = model.press({action: true})
	model.press({})
	return result


## Moves the highlight down to the Return to base row; false if it never gets there.
func _to_return(model: DevMenuModel) -> bool:
	return DevMenuWalk.select(model, DevMenuSpec.KIND_RETURN, func(action: String) -> void: _press(model, action))


func test_the_shipped_menu_has_the_row_and_its_texts() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "":
		return "dev_menu.json rejected: %s" % spec.error
	var model: DevMenuModel = DevMenuModel.new(spec, [])
	var index: int = _return_index(model)
	if index < 0 or str(spec.entries[index]["label"]) != "Return to base":
		return "dev_menu.json has no \"Return to base\" row"
	if spec.confirm_return_text != "Confirm: abandon run":
		return "confirm text is '%s'" % spec.confirm_return_text
	if DevMenuSpec.parse("{\"entries\": [{\"kind\": \"return\", \"label\": \"R\"}], \"corners\": [\"centre\"], " +
			"\"confirm_return_text\": \" \"}").error == "":
		return "an empty confirm_return_text was accepted"
	return ""


func test_the_row_shows_only_while_a_run_flies() -> String:
	var problems: Array[String] = []
	var model: DevMenuModel = DevMenuModel.new(DevMenuSpec.load_file(), [])
	var index: int = _return_index(model)
	model.set_run(false)
	if model.is_shown(index):
		problems.append("shown without a run")
	model.set_run(true)
	if not model.is_shown(index):
		problems.append("hidden while a run flies")
	var run: RunWiring = _run()
	var level_start: LevelStart = _flying(run)
	if not RunAbandon.flying_run(level_start):
		problems.append("a run's level does not count as flying the run")
	level_start.source = "res://data/levels/g2_level.json"
	if RunAbandon.flying_run(level_start):
		problems.append("a single level from the Level entry counts as the run")
	level_start.source = ""
	if RunAbandon.flying_run(level_start):
		problems.append("the test tunnel counts as the run")
	if RunAbandon.flying_run(_flying(null)):
		problems.append("no run counts as a run")
	level_start.source = run.level_source()
	run.stop()
	if RunAbandon.flying_run(level_start):
		problems.append("a left run still counts")
	var entry: DevMenuReturn = DevMenuReturn.new()
	entry.level_start = _flying(null)
	model.set_run(true)
	entry.show_on(model)
	if model.is_shown(index):
		problems.append("the entry showed the row in the tunnel")
	return "\n".join(problems)


func test_confirm_and_each_way_to_cancel() -> String:
	var problems: Array[String] = []
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	var model: DevMenuModel = menu.model
	model.set_run(true)
	menu.open("centre", "")
	if not _to_return(model):
		menu.free()
		return "the highlight never reached the row"
	if _press(model, DevMenuModel.CONFIRM) != "" or not model.return_armed:
		problems.append("the first press did not only arm the row")
	menu.update({})
	if not menu.texts().has("> Confirm: abandon run"):
		problems.append("the armed row shows %s" % [menu.texts()])
	if _press(model, DevMenuModel.CONFIRM) != DevMenuModel.RETURN:
		problems.append("the second press did not abandon")
	_press(model, DevMenuModel.CONFIRM)
	_press(model, DevMenuModel.DOWN)
	_press(model, DevMenuModel.UP)
	if model.return_armed or _press(model, DevMenuModel.CONFIRM) != "":
		problems.append("moving to another row did not cancel")
	menu.close()
	if model.return_armed:
		problems.append("closing the menu did not cancel")
	menu.open("centre", "")
	_to_return(model)
	if _press(model, DevMenuModel.CONFIRM) != "":
		problems.append("after closing, one press abandoned")
	model.open("centre", "")
	if model.return_armed:
		problems.append("opening the menu again did not cancel")
	menu.update({})
	if menu.texts().has("Confirm: abandon run") or menu.texts().has("> Confirm: abandon run"):
		problems.append("the confirm text stayed after cancelling: %s" % [menu.texts()])
	menu.free()
	return "\n".join(problems)


func test_abandon_keeps_earlier_escapes_and_loses_the_level() -> String:
	var problems: Array[String] = []
	var path: String = _path("abandon")
	var run: RunWiring = _run(ProfileStore.new(path))
	run.saves = RunSaveStore.new(_path("save"))
	run.after_level(ExitRule.Outcome.ESCAPED, 50.0, LEVEL_1_CARRY.duplicate(), 1)
	if run.error != "" or run.state.level_index != 1:
		return "the escape did not move to level 2: '%s'" % run.error
	if run.state.carry(LEVEL_2_CARRY.duplicate()) != "":
		return "level 2 could not carry %s" % [LEVEL_2_CARRY]
	if not _saved(run.saves):
		return "the scratch save was not written: %s" % run.saves.message
	var crew: Array[Dictionary] = run.profile.crew.duplicate(true)
	var lost: int = run.profile.stats.runs_lost
	var played: RunState = run.state
	if not run.abandon():
		return "abandon refused a run in flight"
	var read: Profile = ProfileStore.new(path).load_profile()
	for id: String in LEVEL_1_CARRY:
		if read.count_of(id) != LEVEL_1_CARRY[id]:
			problems.append("%s: %d banked, expected level 1's %d" % [id, read.count_of(id), LEVEL_1_CARRY[id]])
	if read.count_of("core_glass") != 0:
		problems.append("level 2's core_glass was banked")
	if read.crew != crew:
		problems.append("crew %s, expected it unchanged at %s" % [read.crew, crew])
	if read.stats.runs_lost != lost + 1:
		problems.append("%d lost runs, expected %d" % [read.stats.runs_lost, lost + 1])
	if run.saves.has_save():
		problems.append("the suspended-run save is still there")
	if run.ended != played or not played.lost or not played.carried.is_empty():
		problems.append("the abandoned run is not the ended, lost one with nothing carried")
	if not run.active() or run.state.plan.run_seed != NEXT_RUN_SEED or run.state.level_index != 0:
		problems.append("no new run starts on its first level")
	return "\n".join(problems)


func test_abandon_without_a_run_changes_nothing() -> String:
	var calls: Array[bool] = []
	var restart: Callable = func(moved_on: bool) -> void: calls.append(moved_on)
	if RunAbandon.abandon(_flying(null), null, null, restart) or not calls.is_empty():
		return "abandoned with no run"
	var run: RunWiring = _run()
	var level_start: LevelStart = _flying(run)
	level_start.source = ""
	if RunAbandon.abandon(level_start, null, null, restart) or not calls.is_empty() or run.ended != null:
		return "abandoned while the tunnel flies"
	return ""


## Also from the menu that pauses solo play (#1245): the session is held while
## the menu is open and let go when the confirming press closes it.
func test_the_row_fades_to_the_hub_from_the_paused_menu() -> String:
	var problems: Array[String] = []
	var session: LocalSession = LocalSession.new(7, LatestInputSource.new())
	var run: RunWiring = _run()
	var level_start: LevelStart = _flying(run)
	var hub: HubWiring = HubWiring.new()
	var destroyed: DestroyedWiring = DestroyedWiring.new()
	var calls: Array[bool] = []
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.corner_store = PanelCorner.new(_path("panel"))
	wiring.attach(null, null, level_start, func(moved_on: bool) -> void: calls.append(moved_on), null,
		destroyed, DevMenu.new(DevMenuSpec.load_file(), []), hub.is_open, func() -> LocalSession: return session)
	var now: float = 1.0
	wiring.read(_values({ControllerSampler.MENU_BUTTON: true}), now)
	now = _idle(wiring, now + 0.2, 0.1)
	if not wiring.is_open() or not wiring.menu.model.run_shown:
		wiring.menu.free()
		return "the menu did not open with the row shown"
	now = DevMenuWalk.select_wired(wiring, DevMenuSpec.KIND_RETURN, now)
	if not session.paused_by(LocalSession.PAUSE_MENU):
		problems.append("the open menu did not pause the session")
	for press: int in 2:
		wiring.read(_values({"right_button_lower": true}), now)
		now = _idle(wiring, now + FRAME, FRAME)
	if wiring.is_open() or session.paused_by(LocalSession.PAUSE_MENU):
		problems.append("the confirming press left the menu open or the session paused")
	var last: float = -1.0
	while now < 3.0 and not hub.is_open():
		wiring.read(_values(), now)
		now += FRAME
		if hub.is_open():
			break
		if wiring.alpha < last:
			problems.append("the fade went down at %.2f s before the hub opened" % now)
		last = wiring.alpha
	if not hub.is_open():
		problems.append("the hub did not open")
	elif last < 0.9:
		problems.append("the hub opened at fade %.2f, before the view was black" % last)
	if calls != [true]:
		problems.append("the session restarted %s, expected once with the run moved on" % [calls])
	if run.ended == null or not run.ended.lost or level_start.source != run.level_source():
		problems.append("the run was not ended as lost with the new run's level next")
	if hub.alpha() < 1.0 or destroyed.sequence.state != DestroyedSequence.State.RESTARTED:
		problems.append("the hub is not dark and holding the ship as after a loss")
	if hub.panel != null:
		hub.panel.free()
	wiring.menu.free()
	return "\n".join(problems)


static func _values(buttons: Dictionary = {}, stick: Vector2 = Vector2.ZERO) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	values["right_stick"] = stick
	return values


static func _idle(wiring: DevMenuWiring, from: float, seconds: float) -> float:
	var now: float = from
	while now < from + seconds:
		wiring.read(_values(), now)
		now += FRAME
	return now
