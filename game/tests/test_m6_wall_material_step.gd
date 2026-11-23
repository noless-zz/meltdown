extends RefCounted

## The m6 `wall_material` step (#1292, GFX-2, DEV-6): the owner's G6
## "screenshots approved" check needs the physically based walls on record, so
## the step flies the gentle test-tunnel sweep that the m1 `frame_budget` step
## flies, with the headlight on the walls, and asks for screenshots along it
## (#718). It must pass through the acceptance runner in the main scene.

const PART_PATH: String = "res://acceptance/suites/m6/look.json"
const STEP_ID: String = "wall_material"
const FRAME_SECONDS: float = 0.25
const FRAME_LIMIT: int = 600


## The shipped m6 suite with only the step `STEP_ID`.
static func _shipped_step() -> AcceptanceSuite:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m6"
	if found.size() != 1 or found[0].error != "":
		return only
	for step: AcceptanceStep in found[0].steps:
		if step.id == STEP_ID:
			only.steps.append(step)
	return only


func test_the_step_is_in_the_look_part_with_screenshots() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var suite: AcceptanceSuite = _shipped_step()
	if suite.steps.size() != 1:
		return "m6 has %d %s steps" % [suite.steps.size(), STEP_ID]
	var step: AcceptanceStep = suite.steps[0]
	if step.replay_path != "res://acceptance/replays/frame_budget_flight.replay":
		return "the step flies %s, not the test-tunnel sweep" % step.replay_path
	if step.screenshot_ticks.is_empty() or not step.screenshot_at_end:
		return "the step takes no screenshots along the sweep and at its end"
	if not step.checks.has(AcceptanceStep.CHECK_FINAL_HASH) or not step.checks.has(AcceptanceStep.CHECK_NO_SCRIPT_ERRORS):
		return "the step checks %s" % [step.checks]
	return ""


func test_the_shipped_step_passes_in_the_main_scene() -> String:
	var suite: AcceptanceSuite = _shipped_step()
	if suite.steps.size() != 1:
		return "m6 has %d %s steps" % [suite.steps.size(), STEP_ID]
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		main.call("apply_controls", {})
		main.call("advance_frame", FRAME_SECONDS)
		runner.process_frame(FRAME_SECONDS)
		frames += 1
	var text: String = "\n".join(runner.messages)
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code if runner.finished else -1
	main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS:
		return "the step did not pass (exit %d): %s" % [code, text]
	return ""
