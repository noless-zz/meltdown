extends RefCounted

## The `ship_summary` check (#1357, CRF-4, CRW-1, CRW-2, DEV-6, decision record
## 0005), lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "ship_summary", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "ship_summary"]}
##
## After the replay the hub opens on the run (`HubWiring.open_for`) with the
## profile and fitting in scratch files. Scripted stick and A presses build the
## engine upgrade the profile's bank pays for, then take the Fitting Bay into
## use: its screen must show the summary at stock; with the engine slot chosen
## on the ship (#1366) and the stick on the mount row (not yet pressed) the screen must show each attribute the part changes
## as before and after; once mounted the summary must read the new value
## against stock and the fitting file hold the part; the strip row must then
## empty the saved fitting and bring the summary back to stock. Whether the
## rows read well stays human-checked in the headset.

const CHECK: String = "ship_summary"
const PROFILE_FILE: String = "user://meltdown_acceptance_ship_summary_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_ship_summary_fitting.json"
const SLOT: String = "engine"
const Helper: GDScript = preload("res://acceptance/acceptance_craft_and_fit_check.gd")


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or hub == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	_remove_scratch()
	level_start.run.store = ProfileStore.new(PROFILE_FILE)
	level_start.run.ship.fittings = FittingStore.new(FITTING_FILE)
	var verdict: Array = [AcceptanceReport.RESULT_FAIL, "the hub did not open"]
	if hub.open_for(level_start.run):
		verdict = _summary_fit_strip(main, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _summary_fit_strip(main: Node, hub: HubWiring, measurements: Dictionary) -> Array:
	var model: HubModel = hub.text.model
	var engine: String = _first_engine(model)
	measurements["crafted"] = engine
	if engine == "" or not Helper.press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": engine}):
		return [AcceptanceReport.RESULT_FAIL, "no Workbench row builds an engine part from the profile's bank"]
	var mount: Dictionary = {"action": HubText.ACTION_FIT, "slot": SLOT, "id": engine}
	var changes: Array[Dictionary] = model.preview(mount)
	if changes.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "mounting %s changes no attribute" % engine]
	var stat: String = changes[0]["stat"]
	if not Helper.choose_station(main, hub, "fit"):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Fitting Bay into use"]
	var stock: String = _value_line(model, stat)
	if not _scroll_to(main, hub, {}, stock):
		return [AcceptanceReport.RESULT_FAIL, "the Fitting Bay never shows \"%s\": %s" % [stock, hub.text.lines()]]
	var before_after: String = HubSummaryRows.change_text(model.config.words, changes[0])
	measurements["before_after"] = before_after
	var slot_row: Dictionary = {"action": HubFitBay.ACTION_SLOT, "slot": SLOT}
	if not Helper.press_in_station(main, hub, slot_row) or not _scroll_to(main, hub, mount, before_after):
		return [AcceptanceReport.RESULT_FAIL, "with the mount row selected the screen does not show \"%s\": %s" %
			[before_after, hub.stations.texts()]]
	Helper._tap(main, Helper.A, Vector2.ZERO)
	if FittingStore.new(FITTING_FILE).load_fitting().parts[SLOT] != engine:
		return [AcceptanceReport.RESULT_FAIL, "mounting %s was not saved to the fitting" % engine]
	var fitted: String = _value_line(model, stat)
	measurements["fitted"] = fitted
	if fitted == stock or not hub.text.lines().has(fitted):
		return [AcceptanceReport.RESULT_FAIL, "after the mount the summary does not read \"%s\"" % fitted]
	if not Helper.press_in_station(main, hub, {"action": HubText.ACTION_STRIP}):
		return [AcceptanceReport.RESULT_FAIL, "no Fitting Bay row strips the ship to stock"]
	if not FittingStore.new(FITTING_FILE).load_fitting().is_empty() or _value_line(model, stat) != stock:
		return [AcceptanceReport.RESULT_FAIL, "after the strip the fitting is %s and the summary reads \"%s\"" %
			[FittingStore.new(FITTING_FILE).load_fitting().to_json(), _value_line(model, stat)]]
	return [AcceptanceReport.RESULT_PASS, "summary read \"%s\", mount showed \"%s\", then \"%s\", strip went back to stock" %
		[stock, before_after, fitted]]


## The first engine upgrade the profile can build now, or "".
static func _first_engine(model: HubModel) -> String:
	for id: String in model.craftable():
		if model.tree.get_upgrade(id).kind == SLOT:
			return id
	return ""


## The summary row's words for attribute `stat` as the model stands.
static func _value_line(model: HubModel, stat: String) -> String:
	for entry: Dictionary in model.summary():
		if entry["stat"] == stat:
			return HubSummaryRows.value_text(model.config.words, entry)
	return ""


## From the top of the station in use, moves the stick down until the selected
## row's action is `want` and the station's screen shows `line`, without
## pressing. False when the foot is reached first.
static func _scroll_to(main: Node, hub: HubWiring, want: Dictionary, line: String) -> bool:
	for i: int in Helper.MAX_MOVES:
		var before: int = hub.text.selected_line()
		Helper._tap(main, {}, Helper.STICK_UP)
		if hub.text.selected_line() == before:
			break
	for i: int in Helper.MAX_MOVES:
		if hub.text.selected() == want and _shows(hub, line):
			return true
		var at: int = hub.text.selected_line()
		Helper._tap(main, {}, Helper.STICK_DOWN)
		if hub.text.selected_line() == at:
			return false
	return false


## Whether the station's screen shows `line`, plain or as the marked selected
## row: picking a slot on the bay's ship leaves room for one row (#1366).
static func _shows(hub: HubWiring, line: String) -> bool:
	var texts: Array[String] = hub.stations.texts()
	return texts.has(line) or texts.has(str(HubPanelLook.load_file()["mark_text"]) + line)


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
