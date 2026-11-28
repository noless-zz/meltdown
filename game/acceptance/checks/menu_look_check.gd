extends RefCounted

## The `menu_look` check (#1458, CRW-2, PLT-5, DEV-6, decision record 0005),
## lane-c's file under `acceptance/checks/`. In `suites/m6/menu.json`:
##
##     {"id": "menu_look", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "checks": ["no_script_errors", "menu_look"]}
##
## After the flight, scripted controller values go through the scene's own
## `apply_controls` and `advance_frame`: a tap opens the menu in the mine, and
## every row it shows must draw its icon from the base's set (no plain marker)
## and every value row its drawing. A opens the Comfort section, whose rows are
## checked the same way, and a screenshot is saved of each list. A tap closes
## it. Then the ship is lost and restart pressed, so the hub opens in the room
## (`hub_room_check.gd`), and the same is checked and saved at the base. The
## profile and fitting are kept in scratch files. Whether the menu reads at a
## glance with fewer words stays a headset check.

const CHECK: String = "menu_look"
const HubRoomCheck := preload("res://acceptance/checks/hub_room_check.gd")
const MenuAtBase := preload("res://acceptance/checks/menu_at_base_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_menu_look_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_menu_look_fitting.json"
const A: String = "right_button_lower"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var menu: DevMenuWiring = main.get("dev_menu") as DevMenuWiring
	var hub: HubWiring = main.get("hub") as HubWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if menu == null or hub == null or level_start == null or level_start.run == null:
		return [AcceptanceReport.RESULT_FAIL, "the scene has no dev menu, hub or run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = _look(runner, step.id, menu, DevMenuPlaces.MINE, "mine", measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = HubRoomCheck.judge_open_room(main, hub, measurements)
	if verdict[0] == AcceptanceReport.RESULT_PASS:
		verdict = _look(runner, step.id, menu, DevMenuPlaces.BASE, "base", measurements)
	if menu.is_open():
		menu.menu.close()
		MenuAtBase.frame(main, {})
	hub.close()
	_remove_scratch()
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return verdict
	return [AcceptanceReport.RESULT_PASS, "in the mine and at the base every row drew its icon and value: %s rows" %
		measurements.get("rows_checked", 0)]


## Opens the menu at `place`, checks the top list and the first section, saves both, closes it.
static func _look(runner: AcceptanceRunner, step_id: String, menu: DevMenuWiring, place: String,
		where: String, measurements: Dictionary) -> Array:
	var main: Node = runner.main
	MenuAtBase.frame(main, {})
	MenuAtBase.tap(main)
	if not menu.is_open() or menu.menu.model.place != place:
		return [AcceptanceReport.RESULT_FAIL, "a tap did not open the menu in the %s" % where]
	for list: String in ["top", "section"]:
		var problem: String = rows_problem(menu.menu)
		measurements["rows_%s_%s" % [where, list]] = " | ".join(menu.menu.texts())
		measurements["rows_checked"] = int(measurements.get("rows_checked", 0)) + menu.menu.shown_rows().size()
		measurements["screenshot_%s_%s" % [where, list]] = _screenshot(runner, step_id, "%s_%s" % [where, list])
		if problem != "":
			return [AcceptanceReport.RESULT_FAIL, "in the %s's %s list %s" % [where, list, problem]]
		if list == "top":
			MenuAtBase.frame(main, {"buttons": {A: true}})  # The first row is the Comfort section.
			MenuAtBase.frame(main, {})
			if menu.menu.model.rows.section == DevMenuRows.TOP:
				return [AcceptanceReport.RESULT_FAIL, "A on the first row in the %s opened no section" % where]
	MenuAtBase.tap(main)
	if menu.is_open():
		return [AcceptanceReport.RESULT_FAIL, "the second tap left the menu open in the %s" % where]
	return [AcceptanceReport.RESULT_PASS, ""]


## Why the rows `menu` shows do not each draw an icon and, for a value, its drawing; "" when they do.
static func rows_problem(menu: DevMenu) -> String:
	var rows: Array[int] = menu.model.rows.visible_rows()
	var drawn: Array[DevMenuRow] = menu.shown_rows()
	if drawn.size() != rows.size() or rows.is_empty():
		return "%d rows drew for %d shown" % [drawn.size(), rows.size()]
	for i: int in rows.size():
		var text: String = DevMenu.row_text(menu.model, rows[i], false)
		if drawn[i].icon == null or drawn[i].icon.part_count() == 0:
			return "\"%s\" has no icon" % text
		var has_value: bool = rows[i] >= 0 and menu.model.value(str(menu.model.spec.entries[rows[i]]["kind"])) != null
		if has_value and drawn[i].drawing.part_count() == 0:
			return "\"%s\" does not draw its value" % text
	if not menu.icons.fell_back.is_empty():
		return "fell back to the plain marker for %s" % [menu.icons.fell_back]
	return ""


## Draws the frame and saves it; returns the path, or why there is none.
static func _screenshot(runner: AcceptanceRunner, step_id: String, what: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped: headless display, nothing is drawn"
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped: %s" % str(got)
	var folder: String = runner.screenshots.dir.path_join(CHECK)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("%s_%s.png" % [step_id, what])
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
