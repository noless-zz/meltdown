class_name AcceptanceSuspendResumeCheck
extends RefCounted

## The `suspend_resume` check of a run step (#1107, RUN-8, DEV-6, gate G4's
## "save and resume survive forced kills", decision record 0005). In a suite:
##
##     {"id": "suspend_resume", "run": 12345, "replay": "res://...",
##      "checks": ["outcome", "no_script_errors", "suspend_resume"],
##      "expected_next_level_hash": 123}
##
## After the step's replay escapes the run's first level, scripted controller
## values go through the scene's own `apply_controls` and `advance_frame`, as
## `AcceptanceShaftChoiceCheck` drives them: A on the escape screen opens the
## shaft panel, the stick moves to its last row, "Suspend run", and A takes it.
## The run is saved into a scratch store and the hub must open. A second save
## is then killed before its rename: the hub must still find the first save
## whole. A fresh store on the same file resumes the run as the hub's resume
## row does, and the scene flies it as the hub's answer flies it: level 2
## through the first offered shaft, as the uninterrupted run flies it when no
## shaft is chosen, with level hash `expected_next_level_hash`. The save must
## be gone after, so the run cannot resume twice. Like run_advances it swaps
## the scene's session, so it is the step's last check.

const SCRATCH_PATH: String = "user://acceptance_suspend_resume_run.json"


## [result, message]; `measurements` gets the saves and the level flown.
static func run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	var result: Array = _run(step, main, flown, measurements)
	RunSaveStore.new(SCRATCH_PATH).discard()
	return result


static func _run(step: AcceptanceStep, main: Node, flown: bool, measurements: Dictionary) -> Array:
	if not flown:
		return [AcceptanceReport.RESULT_FAIL, "no replay was flown"]
	var level_start: LevelStart = main.get("level_start") as LevelStart
	var destroyed: DestroyedWiring = main.get("destroyed") as DestroyedWiring
	var hub: HubWiring = main.get("hub") as HubWiring
	if level_start == null or destroyed == null or hub == null or level_start.run == null \
			or not level_start.run.active():
		return [AcceptanceReport.RESULT_FAIL, "the scene flies no run"]
	var ended: LocalSession = main.get("session")
	if ended.sim.outcome() != ExitRule.Outcome.ESCAPED:
		return [AcceptanceReport.RESULT_FAIL, "the run's level ended %s, not escaped" %
			AcceptanceStateChecks.outcome_name(ended.sim.outcome())]
	var run: RunWiring = level_start.run
	run.saves = RunSaveStore.new(SCRATCH_PATH)
	run.saves.discard()
	var choice: ShaftChoiceWiring = destroyed.escape.choice
	var waited: int = 0
	while not destroyed.escape.sequence.prompt_shown() and waited < AcceptanceShaftChoiceCheck.WAIT_FRAMES:
		_frames(main, {}, 1)
		waited += 1
	_frames(main, {}, 1)
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	if not choice.is_open():
		return [AcceptanceReport.RESULT_FAIL, "A on the escape screen did not open the shaft panel"]
	var first: String = run.state.offer()[0]
	var last: int = choice.model.kinds.size() - 1
	if choice.model.kinds[last] != RunSuspend.ROW_KIND:
		return [AcceptanceReport.RESULT_FAIL, "the shaft panel has no suspend row: %s" % [choice.model.kinds]]
	for i: int in last:
		_frames(main, {}, AcceptanceShaftChoiceCheck.HOLD_FRAMES)
		_frames(main, {}, AcceptanceShaftChoiceCheck.HOLD_FRAMES, AcceptanceShaftChoiceCheck.STICK_DOWN)
	_frames(main, {}, AcceptanceShaftChoiceCheck.HOLD_FRAMES)
	_frames(main, {DestroyedWiring.RESTART_BUTTON: true}, 1)
	if choice.is_open() or not hub.is_open() or not run.saves.has_save():
		return [AcceptanceReport.RESULT_FAIL, "suspend: panel open %s, hub open %s, saved %s, error '%s'" % [
			choice.is_open(), hub.is_open(), run.saves.has_save(), run.error]]
	var saved: RunSave = HubOpening.waiting_save(run.saves)
	measurements["saved"] = saved.to_json().strip_edges() if saved != null else ""
	var killed: RunSaveStore = RunSaveStore.new(SCRATCH_PATH)
	killed.stop_before_rename = true
	var later: RunSave = RunSave.parse_json(saved.to_json() if saved != null else "")
	later.next_level += 1
	killed.save(later)
	var survived: RunSave = HubOpening.waiting_save(RunSaveStore.new(SCRATCH_PATH))
	if survived == null or survived.to_json() != saved.to_json():
		return [AcceptanceReport.RESULT_FAIL, "a save killed before its rename did not leave the first whole"]
	run.saves = RunSaveStore.new(SCRATCH_PATH)  # A fresh store, as after the app is killed.
	if not hub.resume_run():
		return [AcceptanceReport.RESULT_FAIL, "the hub did not resume the run: '%s'" % run.error]
	main.call("restart_level", true)
	if run.saves.has_save() or HubOpening.waiting_save(run.saves) != null:
		return [AcceptanceReport.RESULT_FAIL, "the save is still there after the resume"]
	var plan: RunPlan = AcceptanceRunStep.plan_for(step.run_seed)
	var want: String = LevelSwitch.seed_source(plan.level_seed_through(1, run.shafts, first),
		float(run.shafts.risks[first]["robot_count"]))
	var session: LocalSession = main.get("session")
	var actual: int = AcceptanceStepLevel.level_hash(session.replay)
	measurements["next_level_source"] = level_start.source
	measurements["next_level_hash"] = actual
	if level_start.source != want:
		return [AcceptanceReport.RESULT_FAIL, "the resumed run flies %s, expected %s" % [level_start.source, want]]
	if actual != step.expected_next_level_hash:
		return [AcceptanceReport.RESULT_FAIL, "next level hash %d, expected %d: the level's data changed" % [
			actual, step.expected_next_level_hash]]
	return [AcceptanceReport.RESULT_PASS, "suspended, a killed save left it whole, resumed %s, level hash %d" % [
		want, actual]]


static func _frames(main: Node, buttons: Dictionary, count: int, stick: Vector2 = Vector2.ZERO) -> void:
	AcceptanceShaftChoiceCheck._frames(main, buttons, count, stick)
