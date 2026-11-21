extends RefCounted

## The m1 step `preset_change_mid_flight` and the suite field it uses (#777,
## CMF-4, CMF-6, CMF-3, ARC-3, DEV-6): the preset changes 4 → 1 → 3 → 2 while
## `m1_flight_axes.replay` flies, the run ends on the same hash as presets 3
## and 4 alone, and `comfort_motion` judges each frame against the preset in
## force on that frame.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const STEP_ID: String = "preset_change_mid_flight"
const REPLAY_PATH: String = "res://acceptance/replays/m1_flight_axes.replay"
const FLIGHT_AXES_HASH: int = 3139276631
## `m1_flight_axes.replay` pitches from tick 990 on.
const TURNING_TICK: int = 1000
const FRAME_LIMIT: int = 8000


static func _suite_text(changes_json: String) -> String:
	return ("{\"name\": \"x\", \"steps\": [{\"id\": \"mid\", \"replay\": \"%s\", \"preset\": 4,"
		+ " \"checks\": [\"comfort_motion\"], \"preset_changes\": %s}]}") % [REPLAY_PATH, changes_json]


static func _m1_step() -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(SUITE_PATH).steps:
		if step.id == STEP_ID:
			return step
	return null


func test_preset_changes_parse_in_order() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(
		"[{\"tick\": 10, \"preset\": 1}, {\"tick\": 20, \"preset\": 3}]"))
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = suite.steps[0]
	if step.preset_change_ticks != [10, 20] or step.preset_change_presets != [1, 3] or step.preset != 4:
		return "parsed ticks %s presets %s" % [step.preset_change_ticks, step.preset_change_presets]
	var plain: AcceptanceSuite = AcceptanceSuite.load_file("res://acceptance/suites/m0.json")
	if plain.error != "" or not plain.steps[0].preset_change_ticks.is_empty():
		return "a step without preset_changes has %s" % [plain.steps[0].preset_change_ticks]
	return ""


## An unknown preset, ticks out of order and a tick past the replay are each a
## suite error naming the step's field.
func test_bad_preset_changes_are_rejected() -> String:
	var cases: Dictionary = {
		"[{\"tick\": 10, \"preset\": 5}]": "steps[0].preset_changes[0].preset",
		"[{\"tick\": 20, \"preset\": 1}, {\"tick\": 10, \"preset\": 2}]": "steps[0].preset_changes[1].tick",
		"[{\"tick\": 20, \"preset\": 1}, {\"tick\": 20, \"preset\": 2}]": "steps[0].preset_changes[1].tick",
		"[{\"tick\": 999999, \"preset\": 1}]": "past the replay",
		"[{\"tick\": 10, \"preset\": 1, \"speed\": 2}]": "steps[0].preset_changes[0].speed",
		"[{\"tick\": 10}]": "steps[0].preset_changes[0].preset",
		"[]": "steps[0].preset_changes",
	}
	for changes: String in cases:
		var suite: AcceptanceSuite = AcceptanceSuite.parse_json(_suite_text(changes))
		if suite.error == "" or not suite.error.contains(cases[changes]) or not suite.error.contains("steps[0]"):
			return "%s gave '%s', expected it to name %s" % [changes, suite.error, cases[changes]]
	var no_replay: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"x\", \"steps\": [{\"id\": \"a\", \"checks\": [\"refresh_rate\"], \"preset_changes\": [{\"tick\": 1, \"preset\": 1}]}]}")
	if not no_replay.error.contains("steps[0].preset_changes"):
		return "without a replay: '%s'" % no_replay.error
	return ""


## The shipped step flies flight_axes from preset 4 through 1, 3 and 2, on the
## hash of comfort_preset_3 and comfort_preset_4 (CMF-6).
func test_the_m1_step_is_shipped() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var step: AcceptanceStep = _m1_step()
	if step == null:
		return "m1 has no step %s" % STEP_ID
	if step.replay_path != REPLAY_PATH or step.preset != 4 or step.preset_change_presets != [1, 3, 2]:
		return "%s flies %s from %d through %s" % [step.id, step.replay_path, step.preset, step.preset_change_presets]
	if step.checks != [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_COMFORT_MOTION,
			AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]:
		return "%s checks %s" % [step.id, step.checks]
	for other: AcceptanceStep in suite.steps:
		if other.id in ["comfort_preset_3", "comfort_preset_4"] and other.expected_hash != step.expected_hash:
			return "%s expects %d, %s %d" % [step.id, step.expected_hash, other.id, other.expected_hash]
	return "" if step.expected_hash == FLIGHT_AXES_HASH else "%s expects %d" % [step.id, step.expected_hash]


## Headless in the real main scene the step passes: same end state, every
## preset was flown, and no frame on preset 1 turned the view smoothly.
func test_the_step_passes_in_the_main_scene() -> String:
	var report: Array = _run_step(_m1_step())
	if report[0] != AcceptanceRunner.EXIT_PASS:
		return "exit %d: %s" % [report[0], report[1]]
	var measured: Dictionary = report[2]
	if measured.get("comfort_presets") != [4, 1, 3, 2] or measured.get("final_hash") != FLIGHT_AXES_HASH:
		return "measured %s" % measured
	if not str(report[1]).contains("preset 4→1→3→2"):
		return "the result does not name the presets: %s" % report[1]
	return ""


## The same flight switched to preset 1 while the ship is pitching: the view
## swings smoothly on preset 1, and comfort_motion fails naming the frame,
## while the hash still matches (the change is invisible to the simulation).
func test_a_smooth_swing_on_preset_1_fails() -> String:
	var step: AcceptanceStep = _m1_step()
	step.preset_change_ticks = [TURNING_TICK]
	step.preset_change_presets = [1]
	var report: Array = _run_step(step)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS or not text.contains("comfort_motion: frame ") \
			or not text.contains("smoothly"):
		return "a swing on preset 1 gave exit %d: %s" % [report[0], text]
	if report[2].get("final_hash") != FLIGHT_AXES_HASH:
		return "the change moved the simulation: %s" % report[2]
	return ""


## The check alone: smooth turns pass on preset 4, and the first smooth turn
## after a change to preset 1 fails, naming that frame and the preset 1 rule.
func test_the_check_follows_the_change() -> String:
	var check: AcceptanceComfortCheck = AcceptanceComfortCheck.new(4, ComfortPresetFiles.load_number(4))
	var yaw: float = 0.0
	for frame: int in 11:
		check.sample(Basis(Vector3.UP, deg_to_rad(yaw)), 1.0 / 60.0)
		yaw += 1.0
	if check.first_failure != "":
		return "preset 4 failed: %s" % check.first_failure
	check.change_preset(1, ComfortPresetFiles.load_number(1))
	check.sample(Basis(Vector3.UP, deg_to_rad(yaw)), 1.0 / 60.0)
	var result: Array = check.run({})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("frame 11 turned"):
		return "after the change to preset 1: %s" % [result]
	if check.preset_numbers != [4, 1]:
		return "presets %s" % [check.preset_numbers]
	return ""


## [exit code, messages and results, measurements] of the runner flying
## `step` alone in the main scene, as `test_m1_comfort_replays.gd` does.
func _run_step(step: AcceptanceStep) -> Array:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var code: int = runner.exit_code if runner.finished else -1
	var text: String = "\n".join(runner.messages)
	var measurements: Dictionary = {}
	for report: AcceptanceReport in runner.reports:
		for entry: Dictionary in report.steps:
			text += "\n%s: %s" % [entry["result"], entry["message"]]
			measurements = entry["measurements"]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()
	return [code, text, measurements]


func _on_quit(_code: int) -> void:
	pass
