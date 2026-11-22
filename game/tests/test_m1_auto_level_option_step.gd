extends RefCounted

## The m1 `auto_level_option` step and its check (#1247, CMF-1, CMF-5, DEV-6):
## the shipped step passes through the acceptance runner in the main scene and
## leaves the scene's choice as it was; the judge fails a bank that stays with
## the option on or moves with it off; presets 1 and 2 are refused.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "auto_level_option"
const FRAME_SECONDS: float = 0.25
const FRAME_LIMIT: int = 200

var _quit_codes: Array[int] = []


## [exit code, messages, measurements, scene's choice after] of the runner
## flying `suite` in the main scene.
func _run(suite: AcceptanceSuite) -> Array:
	_quit_codes.clear()
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(code: int) -> void: _quit_codes.append(code)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		main.call("apply_controls", {})
		main.call("advance_frame", FRAME_SECONDS)
		runner.process_frame(FRAME_SECONDS)
		frames += 1
	var text: String = "\n".join(runner.messages)
	var measurements: Dictionary = {}
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
			measurements = entry["measurements"]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var comfort: ComfortWiring = main.get("comfort") as ComfortWiring
	var after: Array = [comfort.auto_level_choice, comfort.preset.levels_roll()]
	var code: int = runner.exit_code if runner.finished else -1
	main.free()
	runner.free()
	return [code, text, measurements, after]


## The shipped m1 suite with only the step `STEP_ID`.
static func _shipped_step() -> AcceptanceSuite:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = suite.name
	for step: AcceptanceStep in suite.steps:
		if step.id == STEP_ID:
			only.steps.append(step)
	return only


func test_the_shipped_step_passes_and_restores_the_choice() -> String:
	var suite: AcceptanceSuite = _shipped_step()
	if suite.steps.size() != 1:
		return "m1 has %d %s steps" % [suite.steps.size(), STEP_ID]
	var step: AcceptanceStep = suite.steps[0]
	if step.preset != 4 or step.checks != [AcceptanceStep.CHECK_AUTO_LEVEL_OPTION,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS] or step.replay_path != "":
		return "the step is preset %d, checks %s, replay \"%s\"" % [step.preset, step.checks, step.replay_path]
	var result: Array = _run(suite)
	if result[0] != AcceptanceRunner.EXIT_PASS:
		return "the step failed: %s" % result[1]
	var measurements: Dictionary = result[2]
	if absf(float(measurements.get("released_on_deg", 0.0))) < AcceptanceAutoLevelCheck.TARGET_DEG \
			or absf(float(measurements.get("after_on_deg", 99.0))) > AcceptanceAutoLevelCheck.LEVEL_DEG:
		return "measurements %s" % measurements
	if result[3] != [AutoLevelChoice.UNSET, false]:
		return "the scene was left with choice and levelling %s" % str(result[3])
	return ""


func test_the_judge() -> String:
	var cases: Array = [
		[Vector2(-60.5, 0.0), Vector2(-60.5, -60.5), AcceptanceReport.RESULT_PASS],
		[Vector2(-60.5, -3.0), Vector2(-60.5, -60.5), AcceptanceReport.RESULT_FAIL],
		[Vector2(-60.5, 0.0), Vector2(-60.5, -50.0), AcceptanceReport.RESULT_FAIL],
		[Vector2(-20.0, 0.0), Vector2(-60.5, -60.5), AcceptanceReport.RESULT_FAIL],
	]
	for case: Array in cases:
		var got: Array = AcceptanceAutoLevelCheck.judge(case[0], case[1])
		if got[0] != case[2]:
			return "on %s off %s judged %s: %s" % [case[0], case[1], got[0], got[1]]
	return ""


func test_a_preset_that_always_levels_is_refused() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json('{"name": "m1", "steps": [{"id": "%s", ' % STEP_ID
		+ '"preset": 2, "checks": ["auto_level_option"]}]}')
	if suite.error != "":
		return "the step was rejected: %s" % suite.error
	var result: Array = _run(suite)
	if result[0] == AcceptanceRunner.EXIT_PASS or not str(result[1]).contains("always levels"):
		return "preset 2 was not refused: %s" % result[1]
	return ""
