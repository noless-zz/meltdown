extends RefCounted

## The m6 `cockpit_look` step (#1306, GFX-2, CMF-1, DEV-6): the owner's G6
## "screenshots approved" check needs the cockpit's new look on record on
## every preset, so the step flies the gentle test-tunnel sweep, starting on
## preset 1 and changing to 2, 3 and 4 along it, with a screenshot before each
## change and at the end. Its pinned hash is the sweep's own, so the look
## leaves the simulation alone (ARC-1, ARC-2). It must pass through the
## acceptance runner in the main scene.

const PART_PATH: String = "res://acceptance/suites/m6/ship.json"
const STEP_ID: String = "cockpit_look"
## The hash the m6 `wall_material` step pins for the same sweep.
const SWEEP_HASH: int = 1960961122
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


func test_the_step_is_in_the_ship_part_on_every_preset() -> String:
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
	if step.expected_hash != SWEEP_HASH:
		return "the step pins %d, not the sweep's own hash %d" % [step.expected_hash, SWEEP_HASH]
	var flown: Array[int] = [step.preset]
	var shots_before: int = 0
	for index: int in step.preset_change_ticks.size():
		flown.append(step.preset_change_presets[index])
		for tick: int in step.screenshot_ticks:
			if tick < step.preset_change_ticks[index]:
				shots_before += 1
	flown.sort()
	if flown != [1, 2, 3, 4]:
		return "the step flies presets %s, not each of the four" % [flown]
	if shots_before < 1 + 2 + 3:
		return "the step does not take a screenshot on each preset before changing it"
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
