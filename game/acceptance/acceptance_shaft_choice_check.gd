class_name AcceptanceShaftChoiceCheck
extends RefCounted

## The `shaft_choice` check of a run step (#990, RUN-1, DEV-6, decision record
## 0005). After the step's replay escapes the run's first level, scripted
## controller values go through the scene's own `apply_controls` and
## `advance_frame`, one tick per frame, as a pilot's would:
##
## 1. idle until the escape screen's prompt shows, and one frame more;
## 2. A pressed: the shaft panel must open in place of the restart;
## 3. A released, right stick down, released: the second shaft is highlighted;
## 4. A pressed: the shaft is taken and the next level flies.
##
## The next level's source must be `RunPlan.level_seed_through` level 2 and
## that shaft, scaled by the shaft's `risk.robot_count` (#1011), and its level
## hash `expected_next_level_hash`, so a riskier shaft's busier level is pinned. Like run_advances
## it swaps the scene's session, so it is the step's last check. How the panel
## reads in the headset stays human-checked (#950).

## The escape screen's fade and hold are a few seconds; 30 s of frames is ample.
const WAIT_FRAMES: int = 1800
## Frames each scripted press or release is held.
const HOLD_FRAMES: int = 3
const PICK: int = 1
const STICK_DOWN: Vector2 = Vector2(0.0, -1.0)


## [result, message]; `measurements` gets the offer, the pick and the level flown.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	if level_start == null or destroyed == null or level_start.run == null or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	var waited: int = 0
	while not destroyed.escape.sequence.prompt_shown() and waited < WAIT_FRAMES:
		_frames(main, {}, 1)
		waited += 1
	if not destroyed.escape.sequence.prompt_shown():
		return [AcceptanceReport.RESULT_FAIL, "the escape screen's prompt never showed"]
	_frames(main, {}, 1)
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	if not choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A on the escape screen did not open the shaft panel"]
	var offered: Array[String] = choice.model.kinds.duplicate()
	measurements["offered"] = ",".join(offered)
	if offered != run.state.offer() or offered.size() <= PICK:
		return [AcceptanceReport.RESULT_FAIL, "the panel lists %s, the run offers %s" % [offered, run.state.offer()]]
	_frames(main, {}, HOLD_FRAMES)
	_frames(main, {}, HOLD_FRAMES, STICK_DOWN)
	_frames(main, {}, HOLD_FRAMES)
	if choice.model == null or choice.model.highlight != PICK:
		return [AcceptanceReport.RESULT_FAIL, "the stick did not move the highlight to shaft %d" % (PICK + 1)]
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	if choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A did not take the highlighted shaft"]
	var kind: String = offered[PICK]
	var plan: RunPlan = AcceptanceRunStep.plan_for(step.run_seed)
	var want: String = LevelSwitch.seed_source(plan.level_seed_through(1, run.shafts, kind),
		float(run.shafts.risks[kind]["robot_count"]))
	var session: LocalSession = main.get("session")
	var actual: int = AcceptanceStepLevel.level_hash(session.replay)
	measurements["chosen"] = kind
	measurements["next_level_source"] = level_start.source
	measurements["next_level_hash"] = actual
	if level_start.source != want:
		return [AcceptanceReport.RESULT_FAIL, "the run flies %s after %s, expected %s" % [level_start.source, kind, want]]
	if actual != step.expected_next_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "next level hash %d, expected %d: the level's data changed" % [
			actual, step.expected_next_level_hash]]
	return [AcceptanceReport.RESULT_PASS, "shaft %s flies %s, level hash %d" % [kind, want, actual]]


## `count` frames with `buttons` held and the right stick at `stick`.
static func _frames(main: Node, buttons: Dictionary, count: int, stick: Vector2 = Vector2.ZERO) -> void:
	for i: int in count:
		var values: Dictionary = ControllerSampler.idle_values()
		values["buttons"] = buttons.duplicate()
		values["right_stick"] = stick
		main.call("apply_controls", values)
		main.call("advance_frame", ShipState.TICK_DT)
