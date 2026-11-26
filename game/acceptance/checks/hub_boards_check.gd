extends RefCounted

## The `hub_boards` check (#1368, CRW-1, CRW-2, DEV-6, decision record 0005),
## lane-c's file under `acceptance/checks/`. In `suites/m6/base.json`:
##
##     {"id": "hub_boards", "run": 12345, "replay": "res://...craft_and_fit_idle.replay",
##      "profile": "res://acceptance/fittings/hub_boards_profile.json",
##      "checks": ["no_script_errors", "hub_boards"]}
##
## After the replay the hub opens on the run (`HubWiring.open_for`) with the
## profile (three crew roles, some runs logged) and fitting in scratch files.
## Scripted stick and A presses take the Crew Quarters into use: it must draw
## a card per crew role with the selected one framed; the stick down onto the
## ship numbers must draw them as bars with a stock mark. The Logbook must
## draw a figure per counter with the won runs as a bar. A screenshot is taken
## settled forward on each. Telling at a glance what the crew give and how the
## last runs went stays a headset check.

const CHECK: String = "hub_boards"
const PROFILE_FILE: String = "user://meltdown_acceptance_hub_boards_profile.json"
const FITTING_FILE: String = "user://meltdown_acceptance_hub_boards_fitting.json"
const CREW: String = "crew"
const LOGBOOK: String = "logbook"
const MAX_MOVES: int = 40


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
		verdict = _boards(runner, step.id, hub, measurements)
	if hub.is_open():
		hub.close()
	_remove_scratch()
	return verdict


static func _boards(runner: AcceptanceRunner, step_id: String, hub: HubWiring, measurements: Dictionary) -> Array:
	var main: Node = runner.main
	if hub.stations == null:
		return [AcceptanceReport.RESULT_FAIL, "the hub opened on the flat panel, not the stations"]
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, CREW):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Crew Quarters into use"]
	var view: HubBoardView = hub.stations.board_view(CREW)
	if view == null or not view.visible:
		return [AcceptanceReport.RESULT_FAIL, "the Crew Quarters draws no board"]
	var cards: int = view.items.keys().filter(func(id: String) -> bool: return id.begins_with("crew:")).size()
	measurements["cards_drawn"] = cards
	if cards != hub.text.model.crew_groups().size() or not view.selected_item.begins_with("crew:") \
			or view.items[view.selected_item].get_node_or_null("Selected") == null:
		return [AcceptanceReport.RESULT_FAIL, "the Crew Quarters drew %s with %s framed" % [view.items.keys(), view.selected_item]]
	hub.stations.advance(HubStations.SETTLE_SECONDS)
	measurements["screenshot_cards"] = _screenshot(runner, step_id, "cards")
	for i: int in MAX_MOVES:
		if view.selected_item.begins_with("summary:"):
			break
		AcceptanceCraftAndFitCheck._tap(main, {}, AcceptanceCraftAndFitCheck.STICK_DOWN)
	measurements["bars_drawn"] = view.fills.size()
	if not view.selected_item.begins_with("summary:") or view.fills.is_empty() or view.marks.size() != view.fills.size():
		return [AcceptanceReport.RESULT_FAIL, "the ship numbers are not drawn as bars (%s)" % view.selected_item]
	measurements["screenshot_bars"] = _screenshot(runner, step_id, "bars")
	if not AcceptanceCraftAndFitCheck.choose_station(main, hub, LOGBOOK):
		return [AcceptanceReport.RESULT_FAIL, "the stick and A did not take the Logbook into use"]
	var log: HubBoardView = hub.stations.board_view(LOGBOOK)
	if log == null or log.items.size() != ProfileStats.KEYS.size() or not log.fills.has("stats:runs_won"):
		return [AcceptanceReport.RESULT_FAIL, "the Logbook draws %s" % [log.items.keys() if log != null else "nothing"]]
	measurements["figures_drawn"] = log.items.size()
	measurements["won_bar"] = snappedf(log.fills["stats:runs_won"], 0.01)
	hub.stations.advance(HubStations.SETTLE_SECONDS)
	measurements["screenshot_logbook"] = _screenshot(runner, step_id, "logbook")
	return [AcceptanceReport.RESULT_PASS, "%d crew cards, %d bars, %d Logbook figures (won bar %.2f)" %
		[cards, view.fills.size(), log.items.size(), log.fills["stats:runs_won"]]]


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
