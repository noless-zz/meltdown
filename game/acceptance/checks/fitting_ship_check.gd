extends RefCounted

## The `fitting_ship` check (#1366, CRF-4, CRW-2, DEV-6, decision record 0005),
## lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "fitting_ship", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "fitting_ship"]}
##
## After the replay the hub opens on the run (`HubWiring.open_for`) with the
## profile and fitting in scratch files. Scripted stick and A presses build
## the first weapon the Workbench offers and take the Fitting Bay into use: it
## must draw the ship with every slot on it, and a screenshot is taken of the
## bay settled forward. A on Primary 1 must swap the ship for the item list,
## with an icon beside each item row and no more than five rows; a second
## screenshot is taken. A on the weapon's mount row must save it to the
## fitting file and put the ship back with the weapon's icon in Primary 1,
## ringed as the selected slot. Whether the ship reads as a ship and fitting
## works without reading a list stays a headset check.

const CHECK: String = "fitting_ship"
const PROFILE_FILE: String = "user://meltdown_acceptance_fitting_ship_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_fitting_ship_fitting.json"
const SLOT: String = "primary[0]"
const SHOT_FOLDER: String = "fitting_ship"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
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
		verdict = _ship_list_fit(runner, step.id, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _ship_list_fit(runner: AcceptanceRunner, step_id: String, hub: HubWiring, measurements: Dictionary) -> Array:
	var main: Node = runner.main
	if hub.stations == null:
		return [AcceptanceReport.RESULT_FAIL, "the hub opened on the flat panel, not the stations"]
	var model: HubModel = hub.text.model
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(model)
	measurements["crafted"] = weapon
	if weapon == "" or not AcceptanceCraftAndFitCheck.press_row(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Workbench row builds a weapon from the profile's bank"]
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, HubFitBay.STATION):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Fitting Bay into use"]
	var view: HubFittingView = hub.stations.view(HubFitBay.STATION)
	if view == null or not view.visible or not view.ship.visible:
		return [AcceptanceReport.RESULT_FAIL, "the Fitting Bay draws no ship"]
	measurements["slots_drawn"] = view.slot_nodes.size()
	if view.slot_nodes.size() != model.fit_slots().size():
		return [AcceptanceReport.RESULT_FAIL, "the ship draws %d slots, the ship has %d" %
			[view.slot_nodes.size(), model.fit_slots().size()]]
	hub.stations.advance(HubStations.SETTLE_SECONDS)
	measurements["screenshot_ship"] = _screenshot(runner, step_id, "ship")
	if not AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubFitBay.ACTION_SLOT, "slot": SLOT}) \
			or hub.text.fit_slot != SLOT or view.ship.visible:
		return [AcceptanceReport.RESULT_FAIL, "A on %s did not open its list of items" % SLOT]
	measurements["item_icons"] = view.row_icons.size()
	if view.row_icons.is_empty() or hub.text.rows_shown() > 5:
		return [AcceptanceReport.RESULT_FAIL, "the item list draws %d icons in a window of %d rows" %
			[view.row_icons.size(), hub.text.rows_shown()]]
	measurements["screenshot_items"] = _screenshot(runner, step_id, "items")
	if not AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_FIT, "slot": SLOT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no item row mounts %s in %s" % [weapon, SLOT]]
	if FittingStore.new(FITTING_FILE).load_fitting().primary[0] != weapon:
		return [AcceptanceReport.RESULT_FAIL, "mounting %s was not saved to the fitting" % weapon]
	var drawn: HubIcon = view.slot_nodes[SLOT].get_child(0) as HubIcon if view.slot_nodes.has(SLOT) else null
	var icon: Dictionary = HubFitBay.upgrade_icon(model, weapon)
	var parts: int = (HubIcons.load_file().icon(icon["group"], icon["id"])["parts"] as Array).size()
	if not view.ship.visible or view.selected_slot != SLOT or drawn == null or drawn.part_count() != parts:
		return [AcceptanceReport.RESULT_FAIL, "after the mount the ship is not back with %s's icon ringed in %s" %
			[weapon, SLOT]]
	return [AcceptanceReport.RESULT_PASS, "ship drew %d slots, %s opened %d item icons, %s mounted and drawn" %
		[view.slot_nodes.size(), SLOT, measurements["item_icons"], weapon]]


## Draws the frame and saves it; returns the path, or why there is none.
static func _screenshot(runner: AcceptanceRunner, step_id: String, what: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped: headless display, nothing is drawn"
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped: %s" % str(got)
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("%s_%s.png" % [step_id, what])
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
