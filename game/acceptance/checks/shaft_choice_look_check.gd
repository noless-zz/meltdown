extends RefCounted

## The `shaft_choice_look` check (#1320, RUN-2, GFX-2, PLT-2, CMF-8, decision
## records 0005 and 0012), lane-b's file under `acceptance/checks/`. In
## `suites/m6/effects.json`:
##
##     {"id": "shaft_choice_look", "run": 12345,
##      "replay": "res://acceptance/replays/run_advances.replay",
##      "checks": ["outcome", "no_script_errors", "shaft_choice_look"]}
##
## The step's run has the shipped shafts (`AcceptanceRunStep.begin`). After the
## replay escapes the run's first level, scripted controller values
## go through the scene's own `apply_controls` and `advance_frame` until the
## escape screen's prompt shows, then A opens the shaft choice. Every offered
## shaft must stand as a card with its look's parts and one gauge per entry of
## the shapes file, and any row that is not a shaft must sit below them. The
## open panel is then drawn and saved as `<step id>_open.png` beside the
## replay screenshots; a screenshot that cannot be taken is noted and never
## fails the step. The panel is closed again without choosing. Whether the
## shafts can be told apart without reading stays human-checked in the headset.

const CHECK: String = "shaft_choice_look"
## The escape screen's fade and hold are a few seconds; 30 s of frames is ample.
const WAIT_FRAMES: int = 1800
const SHOT_FOLDER: String = "m6"


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if destroyed == null or level_start == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var waited: int = 0
	while not destroyed.escape.sequence.prompt_shown() and waited < WAIT_FRAMES:
		_frame(main, {})
		waited += 1
	if not destroyed.escape.sequence.prompt_shown():
		return [AcceptanceReport.RESULT_FAIL, "the escape screen's prompt never showed"]
	_frame(main, {})
	_frame(main, {DestroyedWiring.RESTART_BUTTON: true})
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	if not choice.is_open() or choice.panel == null:
		return [AcceptanceReport.RESULT_FAIL, "A on the escape screen did not open the shaft choice"]
	_frame(main, {})
	var verdict: Array = judge_open(choice, measurements)
	measurements["screenshot"] = _screenshot(runner, step.id)
	choice.close()
	return verdict


## Whether the open `choice` draws its shafts as things with gauges and the
## other rows apart below them.
static func judge_open(choice: ShaftChoiceWiring, measurements: Dictionary) -> Array:
	var model: ShaftPanelModel = choice.model
	var cards: Array[ShaftPanelCard] = choice.panel.cards()
	measurements["offered"] = ",".join(model.kinds.slice(0, model.shaft_count))
	measurements["looks"] = ",".join(model.looks.slice(0, model.shaft_count))
	if choice.shapes.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the shapes file was refused: %s" % choice.shapes.error]
	if cards.size() != model.shaft_count:
		return [AcceptanceReport.RESULT_FAIL, "%d shafts offered, %d drawn as things" % [model.shaft_count, cards.size()]]
	for i: int in cards.size():
		if cards[i].part_count() == 0 or cards[i].fill_lengths().size() != choice.shapes.gauges.size():
			return [AcceptanceReport.RESULT_FAIL, "shaft %s shows %d parts and %d gauges" % [model.kinds[i],
				cards[i].part_count(), cards[i].fill_lengths().size()]]
	var points: Dictionary[String, Vector3] = choice.panel.entry_points()
	for row: int in range(model.shaft_count, model.kinds.size()):
		for card: ShaftPanelCard in cards:
			if points[model.kinds[row]].y >= card.position.y - choice.shapes.lengths["plate_drop_m"]:
				return [AcceptanceReport.RESULT_FAIL, "the row %s is not below the shafts" % model.kinds[row]]
	return [AcceptanceReport.RESULT_PASS, "%d shafts drawn as %s" % [cards.size(), measurements["looks"]]]


## Draws the frame and saves it; returns the path, or why there is none.
static func _screenshot(runner: AcceptanceRunner, step_id: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped: headless display, nothing is drawn"
	RenderingServer.force_draw(true, 0.0)
	var got: Variant = runner.screenshots.grab.call() if runner.screenshots.grab.is_valid() else "nothing to take it with"
	if not got is Image:
		return "skipped: %s" % str(got)
	var folder: String = runner.screenshots.dir.path_join(SHOT_FOLDER)
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join("%s_open.png" % step_id)
	var error: Error = (got as Image).save_png(path)
	return path if error == OK else "skipped: cannot write %s: %s" % [path, error_string(error)]


static func _frame(main: Node, buttons: Dictionary) -> void:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons.duplicate()
	main.call("apply_controls", values)
	main.call("advance_frame", ShipState.TICK_DT)
