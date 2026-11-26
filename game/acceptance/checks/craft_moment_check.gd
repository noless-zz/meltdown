extends RefCounted

## The `craft_moment` check (#1402, CRF-3, CRW-2, CMF-3, DEV-6, decision
## record 0005), lane-c's file under `acceptance/checks/`. In
## `suites/m6/base.json` it has its own step, after `workbench_tree`:
##
##     {"id": "craft_moment", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_moment_profile.json",
##      "checks": ["no_script_errors", "craft_moment"]}
##
## After the replay the hub opens on the run with the profile and fitting in
## scratch files; scripted stick and A presses take the Workbench into use and
## build `BUILD`. The build must start the crafting moment (`HubCraftMoment`) on
## that node; a screenshot is taken half way through the fill. Played to its
## end, the node must be drawn built and every node the build unlocked drawn
## buildable, all at rest. Whether it feels like making something stays a
## headset check.

const CHECK: String = "craft_moment"
## The base room opens behind an arrival fade; the mid-craft picture must wait
## for it or it shows a dark room (#1425).
const ROOM_CHECK: GDScript = preload("res://acceptance/checks/hub_room_check.gd")
const PROFILE_FILE: String = "user://meltdown_acceptance_craft_moment_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_craft_moment_fitting.json"
const STATION: String = "craft"
## Built in the step; `craft_moment_profile.json` banks enough for it and for
## the upgrade it unlocks, so the unlock shows as buildable.
const BUILD: String = "needle_gun"


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
		var arrival: String = ROOM_CHECK.wait_for_arrival(main, hub)
		verdict = _build_and_watch(runner, step.id, hub, measurements) if arrival == "" \
			else [AcceptanceReport.RESULT_FAIL, arrival]
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _build_and_watch(runner: AcceptanceRunner, step_id: String, hub: HubWiring, measurements: Dictionary) -> Array:
	var main: Node = runner.main
	if hub.stations == null or not AcceptanceCraftAndFitCheck.choose_station(main, hub, STATION):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Workbench into use"]
	var view: HubTreeView = hub.stations.tree_view(STATION)
	var weapon: String = BUILD
	measurements["built"] = weapon
	if view == null or not hub.text.model.craftable().has(weapon) \
			or not AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "the Workbench cannot build %s from the profile's bank" % weapon]
	if not view.moment.running() or view.moment.crafted != weapon:
		return [AcceptanceReport.RESULT_FAIL, "building %s started no crafting moment (%s)" % [weapon, view.moment.crafted]]
	var unlocked: Array[String] = view.moment.unlocked.duplicate()
	measurements["unlocked"] = ",".join(unlocked)
	measurements["components_flying"] = view.moment.flying_count()
	hub.stations.advance(HubStations.SETTLE_SECONDS)  # The screen forward; the moment has its own clock.
	var half: float = float(HubScreenLook.load_file()["craft_fill_seconds"]) * 0.5
	view.advance(maxf(0.0, half - view.moment.elapsed))
	measurements["fill_at_screenshot"] = snappedf(view.moment.fill(), 0.01)
	measurements["room_fade"] = ROOM_CHECK.room_fade(hub.launching)  # What covers the room as the picture is taken.
	measurements["screenshot"] = _screenshot(runner, step_id)
	view.advance(view.moment.duration())
	if view.moment.running():
		return [AcceptanceReport.RESULT_FAIL, "the moment is still playing after its %.2f s" % view.moment.duration()]
	if view.states.get(weapon, "") != HubTreeView.BUILT:
		return [AcceptanceReport.RESULT_FAIL, "after the moment %s is drawn %s, not built" % [weapon, view.states.get(weapon, "")]]
	for id: String in unlocked:
		if view.states.get(id, "") != HubTreeView.READY:
			return [AcceptanceReport.RESULT_FAIL, "after the moment %s is drawn %s, not buildable" % [id, view.states.get(id, "")]]
	if unlocked.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "building %s unlocked no drawn node, so no glow was seen" % weapon]
	return [AcceptanceReport.RESULT_PASS, "%s filled and ended built, %s ended buildable" % [weapon, ", ".join(unlocked)]]


## Draws the frame and saves it; returns the path, or why there is none.
static func _screenshot(runner: AcceptanceRunner, step_id: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped: headless display, nothing is drawn"
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped: %s" % str(got)
	var folder: String = runner.screenshots.dir.path_join(CHECK)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("%s_mid_craft.png" % step_id)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
