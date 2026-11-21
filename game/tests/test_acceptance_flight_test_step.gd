extends RefCounted

## The m1 `first_launch_flight_test` step and its `flight_test_result` check
## (#762, CMF-4, CMF-1, CMF-6, ARC-3, DEV-6). The runner drives the real
## `FlightTestWiring` in the main scene from scripted answers; the scene's
## frames are driven by hand here, as `main._process` drives them in the game.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "first_launch_flight_test"
## Long frames keep the test short; the wiring is handed real frame time.
const FRAME_SECONDS: float = 0.25
const FRAME_LIMIT: int = 2000
const ALL_FINE: Array[String] = ["fine", "fine", "fine", "fine", "fine", "fine"]

var _quit_codes: Array[int] = []


static func _step_json(answers: Array, expected: int, extra: String = "") -> String:
	return '{"name": "m1", "steps": [{"id": "%s", "checks": ["flight_test_result", "no_script_errors"], ' \
		% STEP_ID + '"flight_test_answers": %s, "expected_preset": %d%s}]}' % [JSON.stringify(answers), expected, extra]


static func _plan() -> FlightTestPlan:
	return FlightTestPlan.load_file(FlightTestPlan.DEFAULT_FILE)


static func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else "<missing>"


## [exit code, messages, measurements, scene preset after, wiring restored] of
## the runner flying `suite` in the main scene.
func _run(suite: AcceptanceSuite) -> Array:
	_quit_codes.clear()
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(code: int) -> void: _quit_codes.append(code)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var scene_wiring: FlightTestWiring = main.get("flight_test")
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
	var preset_after: int = (main.get("comfort") as ComfortWiring).number
	var restored: bool = main.get("flight_test") == scene_wiring
	var code: int = runner.exit_code if runner.finished else -1
	main.free()
	runner.free()
	return [code, text, measurements, preset_after, restored]


func test_all_fine_ends_on_the_recommenders_preset() -> String:
	var expected: int = PresetRecommender.recommend(_plan(), ALL_FINE)
	var result: Array = _run(AcceptanceSuite.parse_json(_step_json(ALL_FINE, expected)))
	if result[0] != AcceptanceRunner.EXIT_PASS:
		return "all fine, expected %d: %s" % [expected, result[1]]
	var measurements: Dictionary = result[2]
	if measurements.get("applied_preset") != expected or (measurements.get("answers_given") as Array).size() != 6:
		return "measurements %s" % measurements
	if float(measurements.get("ship_travel_while_held_m")) != 0.0:
		return "the ship moved while held: %s" % measurements
	return ""


## Each answer is pressed only once its segment has flown its full time.
func test_answers_come_when_each_question_is_due() -> String:
	var result: Array = _run(AcceptanceSuite.parse_json(_step_json(ALL_FINE, 4)))
	var times: Array = result[2].get("answer_seconds", [])
	if times.size() != 6:
		return "answer times %s" % [times]
	var due: float = 0.0
	for index: int in times.size():
		due += _plan().segments[index].duration_s
		if float(times[index]) < due:
			return "answer %d at %.2f s, before its question was due at %.2f s" % [index, times[index], due]
	return ""


func test_an_early_stop_ends_on_the_answer_for_that() -> String:
	var answers: Array[String] = ["fine", "fine", "stop", "fine", "fine", "fine"]
	var given: Array[String] = ["fine", "fine", "stop"]
	var expected: int = PresetRecommender.recommend(_plan(), given)
	var result: Array = _run(AcceptanceSuite.parse_json(_step_json(answers, expected)))
	if result[0] != AcceptanceRunner.EXIT_PASS:
		return "early stop, expected %d: %s" % [expected, result[1]]
	if result[2].get("answers_given") != given:
		return "answers given %s" % [result[2].get("answers_given")]
	return ""


func test_a_wrong_expected_preset_fails_naming_both() -> String:
	var result: Array = _run(AcceptanceSuite.parse_json(_step_json(ALL_FINE, 1)))
	if result[0] == AcceptanceRunner.EXIT_PASS or not str(result[1]).contains("applied preset 4, expected preset 1"):
		return "expected 1 for all fine gave exit %d: %s" % [result[0], result[1]]
	return ""


## The step uses its own store: the pilot's file is untouched and the
## throw-away one is gone; the scene gets its wiring and preset back.
func test_the_pilots_saved_choice_is_untouched() -> String:
	var before: String = _read(ComfortChoice.DEFAULT_PATH)
	var result: Array = _run(AcceptanceSuite.parse_json(_step_json(ALL_FINE, 4)))
	if result[0] != AcceptanceRunner.EXIT_PASS:
		return "step failed: %s" % result[1]
	if _read(ComfortChoice.DEFAULT_PATH) != before:
		return "the saved choice changed: %s" % _read(ComfortChoice.DEFAULT_PATH)
	if FileAccess.file_exists(AcceptanceFlightTestCheck.STORE_PATH):
		return "the throw-away store was left behind"
	if result[3] != ComfortPresetFiles.START_NUMBER or not result[4]:
		return "scene left on preset %d, wiring restored %s" % [result[3], result[4]]
	return ""


func test_the_wrong_number_of_answers_is_rejected_on_load() -> String:
	for answers: Array in [["fine", "fine"], ALL_FINE + ["fine"]]:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_step_json(answers, 2))
		if not suite.error.contains("flight_test_answers"):
			return "%d answers gave: '%s'" % [answers.size(), suite.error]
	return ""


func test_bad_flight_test_keys_are_rejected() -> String:
	var cases: Array = [
		[AcceptanceSuite.parse_json(_step_json(["fine", "fine", "maybe", "fine", "fine", "fine"], 2)),
			"flight_test_answers[2]"],
		[AcceptanceSuite.parse_json(_step_json(ALL_FINE, 5)), "expected_preset"],
		[AcceptanceSuite.parse_json(_step_json(ALL_FINE, 2, ', "replay": "res://x.replay"')), "flies no replay"],
		[AcceptanceSuite.parse_json('{"name": "m1", "steps": [{"id": "a", "checks": ["flight_test_result"], ' +
			'"expected_preset": 2}]}'), "needed by the flight_test_result check"],
		[AcceptanceSuite.parse_json('{"name": "m1", "steps": [{"id": "a", "checks": ["no_script_errors"], ' +
			'"expected_preset": 2}]}'), "only used by the flight_test_result check"],
	]
	for case: Array in cases:
		if not (case[0] as AcceptanceSuite).error.contains(case[1]):
			return "expected '%s', got '%s'" % [case[1], (case[0] as AcceptanceSuite).error]
	return ""


## m1 still parses and ends with the step; the steps before it keep their places.
func test_m1_runs_the_flight_test_last() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = suite.steps[suite.steps.size() - 1]
	if step.id != STEP_ID or step.checks != [AcceptanceStep.CHECK_FLIGHT_TEST_RESULT, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		return "last step %s with %s" % [step.id, step.checks]
	if step.flight_test_answers.size() != _plan().segments.size() \
			or PresetRecommender.recommend(_plan(), step.flight_test_answers.slice(0, 3)) != step.expected_preset:
		return "answers %s expect %d" % [step.flight_test_answers, step.expected_preset]
	if suite.steps[0].id != "basic_flight" or suite.steps[7].id != "comfort_preset_2":
		return "earlier steps moved: %s, %s" % [suite.steps[0].id, suite.steps[7].id]
	return ""


## The real m1 step flies on the desktop (no OpenXR) and passes.
func test_the_m1_step_passes_without_a_headset() -> String:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == STEP_ID:
			only.steps.append(step)
	var result: Array = _run(only)
	if result[0] != AcceptanceRunner.EXIT_PASS:
		return "m1 step: %s" % result[1]
	return ""
