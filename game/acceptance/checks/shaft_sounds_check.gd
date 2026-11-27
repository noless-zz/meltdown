extends RefCounted

## The `shaft_sounds` check (#1455, AUD-1, RUN-1, DEV-6, decision record 0005),
## lane-b's file under `acceptance/checks/`. In `suites/m6/sound.json`:
##
##     {"id": "shaft_sounds", "run": 12345,
##      "replay": "res://acceptance/replays/run_advances.replay",
##      "checks": ["outcome", "no_script_errors", "shaft_sounds"]}
##
## The step's run has the shipped shafts (`AcceptanceRunStep.begin`). After the
## replay escapes the run's first level, scripted controller values go through
## the scene's own `apply_controls` and `advance_frame`: A on the escape
## screen's prompt opens the shaft choice, the stick moves the highlight down
## onto the second shaft and back up onto the first, and A chooses it. The
## shaft choice's sounds (`ShaftChoiceWiring.sounds`) must then have requested
## point, point and select in that order. The flat simulator has no tracked
## controller, so the stick does the pointing; the aim's own pointing is unit
## tested. Choosing moves the scene to the next level, so it is the step's last
## check. Whether it sounds like the base stays a headset check.

const CHECK: String = "shaft_sounds"
## The escape screen's fade and hold are a few seconds; 30 s of frames is ample.
const WAIT_FRAMES: int = 1800
## Frames each stick position is held; longer together than the point sound's gap.
const HOLD_FRAMES: int = 10
const STICK_DOWN: Vector2 = Vector2(0.0, -1.0)
const STICK_UP: Vector2 = Vector2(0.0, 1.0)
const EXPECTED: Array[String] = [ShaftSoundTable.POINT, ShaftSoundTable.POINT, ShaftSoundTable.SELECT]


static func judges() -> Dictionary[String, Callable]:
	return {CHECK: _judge}


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if not runner.flown():
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var main: Node = runner.main
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var level_start: LevelStart = main.get("level_start") as LevelStart
	if destroyed == null or level_start == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var waited: int = 0
	while not destroyed.escape.sequence.prompt_shown() and waited < WAIT_FRAMES:
		_frames(main, {}, 1)
		waited += 1
	if not destroyed.escape.sequence.prompt_shown():
		return [AcceptanceReport.RESULT_FAIL, "the escape screen's prompt never showed"]
	_frames(main, {}, 1)
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	if not choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A on the escape screen did not open the shaft choice"]
	if choice.sounds == null:
		return [AcceptanceReport.RESULT_FAIL, "the shaft choice has no sounds"]
	if choice.sounds.table.error != "":
		return [AcceptanceReport.RESULT_FAIL, "the shaft sounds file was refused: %s" % choice.sounds.table.error]
	if choice.model.shaft_count < 2:
		return [AcceptanceReport.RESULT_FAIL, "only %d shaft offered; two are needed" % choice.model.shaft_count]
	_frames(main, {}, HOLD_FRAMES)
	_frames(main, {}, HOLD_FRAMES, STICK_DOWN)
	_frames(main, {}, HOLD_FRAMES)
	_frames(main, {}, HOLD_FRAMES, STICK_UP)
	_frames(main, {}, HOLD_FRAMES)
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	var heard: Array[String] = choice.sounds.requested.duplicate()
	measurements["shaft_sounds"] = ",".join(heard)
	if choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A did not take the highlighted shaft; heard %s" % [heard]]
	return judge_heard(heard)


## Whether `heard` holds point, point and select in that order.
static func judge_heard(heard: Array[String]) -> Array:
	var from: int = 0
	for want: String in EXPECTED:
		var found: int = heard.find(want, from)
		if found < 0:
			return [AcceptanceReport.RESULT_FAIL, "no %s sound after the earlier ones: %s" % [want, heard]]
		from = found + 1
	return [AcceptanceReport.RESULT_PASS, "requested %s (%d sounds)" % [", ".join(heard), heard.size()]]


static func _frames(main: Node, buttons: Dictionary, count: int, stick: Vector2 = Vector2.ZERO) -> void:
	for i: int in count:
		var values: Dictionary = ControllerSampler.idle_values()
		values["buttons"] = buttons.duplicate()
		values["right_stick"] = stick
		main.call("apply_controls", values)
		main.call("advance_frame", ShipState.TICK_DT)
