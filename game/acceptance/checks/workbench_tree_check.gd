extends RefCounted

## The `workbench_tree` check (#1367, CRF-3, CRF-6, CRW-2, DEV-6, decision
## record 0005), lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "workbench_tree", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/craft_and_fit_profile.json",
##      "checks": ["no_script_errors", "workbench_tree"]}
##
## After the replay the hub opens on the run (`HubWiring.open_for`) with the
## profile and fitting in scratch files. Scripted stick and A presses take the
## Workbench into use: it must draw the tech tree with edges, nodes that can
## be built and locked ones, the selected node ringed and icons beside its
## detail rows; a screenshot is taken settled forward. A on the first weapon
## the profile can build must build it through the Workbench and redraw its
## node as built. Seeing at a glance what can be built and what it costs
## stays a headset check.

const CHECK: String = "workbench_tree"
const PROFILE_FILE: String = "user://meltdown_acceptance_workbench_tree_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_workbench_tree_fitting.json"
const STATION: String = "craft"


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
		verdict = _tree_and_build(runner, step.id, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _tree_and_build(runner: AcceptanceRunner, step_id: String, hub: HubWiring, measurements: Dictionary) -> Array:
	var main: Node = runner.main
	if hub.stations == null:
		return [AcceptanceReport.RESULT_FAIL, "the hub opened on the flat panel, not the stations"]
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, STATION):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Workbench into use"]
	var view: HubTreeView = hub.stations.tree_view(STATION)
	if view == null or not view.visible:
		return [AcceptanceReport.RESULT_FAIL, "the Workbench draws no tree"]
	measurements["nodes_drawn"] = view.nodes.size()
	measurements["edges_drawn"] = view.edge_count
	measurements["row_icons"] = view.row_icons.size()
	var states: Array = view.states.values()
	if view.edge_count == 0 or not states.has(HubTreeView.READY) or not states.has(HubTreeView.LOCKED):
		return [AcceptanceReport.RESULT_FAIL, "the tree draws %d edges and states %s" % [view.edge_count, view.states]]
	if view.selected_node == "" or view.row_icons.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no node is ringed, or its detail rows have no icons"]
	hub.stations.advance(HubStations.SETTLE_SECONDS)
	measurements["screenshot"] = _screenshot(runner, step_id)
	var weapon: String = AcceptanceCraftAndFitCheck.first_weapon(hub.text.model)
	measurements["built"] = weapon
	if weapon == "" or not AcceptanceCraftAndFitCheck.press_in_station(main, hub, {"action": HubText.ACTION_CRAFT, "id": weapon}):
		return [AcceptanceReport.RESULT_FAIL, "no Workbench node builds a weapon from the profile's bank"]
	if not hub.text.model.profile.crafted.has(weapon) or view.states.get(weapon, "") != HubTreeView.BUILT:
		return [AcceptanceReport.RESULT_FAIL, "after A %s is not built and drawn built (%s)" % [weapon, view.states.get(weapon, "")]]
	return [AcceptanceReport.RESULT_PASS, "tree drew %d nodes and %d edges, %s built and drawn built" %
		[view.nodes.size(), view.edge_count, weapon]]


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
	var path: String = folder.path_join("%s_tree.png" % step_id)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _remove_scratch() -> void:
	for path: String in [PROFILE_FILE, FITTING_FILE]:
		for each: String in [path, SafeFileWrite.temp_path(path)]:
			if FileAccess.file_exists(each):
				DirAccess.remove_absolute(each)
