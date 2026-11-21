extends RefCounted

## The `vignette` check and the m1 suite's `vignette_preset_1` to `_4` steps
## (#850, CMF-1, CMF-2, DEV-6): the comfort table's "Vignette" row as the
## player sees it. Each real preset passes its step in the main scene; preset 4
## never shows a vignette, and the check catches a vignette that is too strong,
## missing while the trigger is met, or left on once the motion stops.

const M1_PATH: String = "res://acceptance/suites/m1.json"
const STEPS: Dictionary[int, Array] = {
	1: ["vignette_preset_1", "res://acceptance/replays/m1_comfort_preset_1.replay", 1382224616],
	2: ["vignette_preset_2", "res://acceptance/replays/m1_comfort_preset_2.replay", 157308001],
	3: ["vignette_preset_3", "res://acceptance/replays/m1_flight_axes.replay", 3139276631],
	4: ["vignette_preset_4", "res://acceptance/replays/m1_flight_axes.replay", 3139276631],
}
const FRAME_LIMIT: int = 8000
const DT: float = 1.0 / 60.0
const SETTLE: float = 0.75


static func _find(id: String) -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(M1_PATH).steps:
		if step.id == id:
			return step
	return null


func test_the_four_steps_are_listed_with_their_checks_and_hash() -> String:
	var wanted: Array[String] = [AcceptanceStep.CHECK_VIGNETTE, AcceptanceStep.CHECK_FINAL_HASH,
		AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	for number: int in STEPS:
		var step: AcceptanceStep = _find(STEPS[number][0])
		if step == null:
			return "m1 has no step %s" % STEPS[number][0]
		if step.preset != number or step.replay_path != STEPS[number][1]:
			return "%s flies preset %d on %s" % [step.id, step.preset, step.replay_path]
		if step.checks != wanted:
			return "%s checks %s" % [step.id, step.checks]
		if step.expected_hash != int(STEPS[number][2]):
			return "%s expects %d" % [step.id, step.expected_hash]
	return ""


func test_the_check_needs_a_replay() -> String:
	var parsed: AcceptanceSuite = AcceptanceSuite.parse_json(
		'{"name": "t", "steps": [{"id": "s", "checks": ["vignette"]}]}')
	if parsed.error.find("needed by the vignette check") < 0:
		return "a step without a replay was accepted: %s" % parsed.error
	return ""


## The four real presets pass, read from their files: each frame shows the
## eased strength their row asks for. Preset 4 shows none.
func test_the_check_passes_the_four_real_presets() -> String:
	for number: int in [1, 2, 3, 4]:
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		var check: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
		var wiring: VignetteWiring = VignetteWiring.new()
		var still: ShipState = ShipState.new()
		var moving: ShipState = ShipState.new()
		moving.velocity = Vector3(0.0, 0.0, -15.0)
		var turned: ShipState = ShipState.new()
		turned.velocity = moving.velocity
		turned.orientation = Basis(Vector3.UP, deg_to_rad(150.0) * ShipState.TICK_DT)
		# Turning fast, then travelling straight, then hovering still.
		for phase: Array in [[still, turned], [moving, moving], [still, still]]:
			for i: int in 60:
				var shown: float = wiring.advance(preset, phase[0], phase[1], 1.0, false, false, DT)
				var turn: float = AcceptanceVignetteCheck.turn_rate(phase[0], phase[1])
				check.sample(number, preset, turn, (phase[1] as ShipState).velocity.length(), shown, DT, SETTLE)
		var result: Array = check.run({})
		if result[0] != AcceptanceReport.RESULT_PASS:
			return "preset %d failed: %s" % [number, result[1]]
		if (check.shown_frames > 0) != (number != 4):
			return "preset %d showed the vignette on %d frames" % [number, check.shown_frames]
	return ""


## A stand-in preset 4 with a strength above 0 shows a vignette, which CMF-2
## forbids on preset 4 whatever its file says.
func test_a_stand_in_preset_4_with_strength_fails() -> String:
	var stand_in: ComfortPreset = ComfortPresetFiles.load_number(4).duplicate() as ComfortPreset
	stand_in.vignette_strength = 0.5
	stand_in.vignette_trigger = ComfortPreset.VignetteTrigger.ALL_MOTION
	var check: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	check.sample(4, stand_in, 0.0, 10.0, 0.2, DT, SETTLE)
	var result: Array = check.run({})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]).find(
			"preset 4 frame 1 (turn 0.0°/s, speed 10.00 m/s): vignette shown at 0.2000, but the preset never shows one") < 0:
		return "a stand-in preset 4 with strength: %s" % [result]
	return ""


## The same stand-in in the main scene fails the real step, naming preset 4.
func test_a_stand_in_preset_4_fails_its_step() -> String:
	var stand_in: ComfortPreset = ComfortPresetFiles.load_number(4).duplicate() as ComfortPreset
	stand_in.vignette_strength = 0.5
	stand_in.vignette_trigger = ComfortPreset.VignetteTrigger.ALL_MOTION
	var report: Array = _run_step(_find(STEPS[4][0]), stand_in, 4)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS:
		return "a stand-in preset 4 with strength passed: %s" % text
	if RegEx.create_from_string("vignette: preset 4 frame \\d+ \\(turn [0-9.]+°/s, speed [0-9.]+ m/s\\): " +
			"vignette shown at [0-9.]+, but the preset never shows one").search(text) == null:
		return "the failure does not name preset 4's vignette: %s" % text
	return ""


func test_a_vignette_left_off_while_preset_1_moves_fails() -> String:
	var check: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	check.sample(1, ComfortPresetFiles.load_number(1), 0.0, 12.0, 0.0, DT, SETTLE)
	var result: Array = check.run({})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]).find(
			"preset 1 frame 1 (turn 0.0°/s, speed 12.00 m/s): vignette off (0) while the preset's trigger is met") < 0:
		return "an off vignette on a moving preset 1: %s" % [result]
	return ""


func test_a_vignette_above_the_presets_strength_fails() -> String:
	var check: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	check.sample(3, ComfortPresetFiles.load_number(3), deg_to_rad(200.0), 5.0, 0.9, DT, SETTLE)
	var result: Array = check.run({})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]).find("above the preset's strength") < 0:
		return "a too strong preset 3 vignette: %s" % [result]
	return ""


## Once the trigger stops the vignette may fade, but not rise, and must be off
## after the settle time.
func test_an_unmet_trigger_allows_a_fade_but_not_a_rise_or_a_vignette_left_on() -> String:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(2)
	var fading: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	fading.sample(2, preset, deg_to_rad(90.0), 0.0, 0.4, DT, SETTLE)
	fading.sample(2, preset, 0.0, 0.0, 0.3, DT, SETTLE)
	if fading.run({})[0] != AcceptanceReport.RESULT_PASS:
		return "a fade failed: %s" % fading.first_failure
	var rising: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	rising.sample(2, preset, 0.0, 0.0, 0.1, DT, SETTLE)
	rising.sample(2, preset, 0.0, 0.0, 0.2, DT, SETTLE)
	if rising.first_failure.find("rose to 0.2000 from 0.1000") < 0:
		return "a rise passed: %s" % rising.first_failure
	var stuck: AcceptanceVignetteCheck = AcceptanceVignetteCheck.new()
	for i: int in 60:
		stuck.sample(2, preset, 0.0, 0.0, 0.2, DT, SETTLE)
	if stuck.first_failure.find("still shown at 0.2000") < 0:
		return "a vignette left on passed: %s" % stuck.first_failure
	return ""


## Each real preset passes its step in the main scene; presets 1 and 2 show
## the vignette on that flight and preset 4 never does.
func test_each_preset_passes_its_step() -> String:
	for number: int in STEPS:
		var report: Array = _run_step(_find(STEPS[number][0]), null)
		if report[0] != AcceptanceRunner.EXIT_PASS:
			return "preset %d: exit %d: %s" % [number, report[0], report[1]]
		var measured: Dictionary = report[2]
		var shown: int = int(measured.get("vignette_shown_frames", -1))
		if int(measured.get("vignette_frames", 0)) <= 0 or (number == 4 and shown != 0) \
				or (number <= 2 and shown <= 0):
			return "preset %d measured %s" % [number, measured]
	return ""


## [exit code, messages and results, the step's measurements] of the runner
## flying `step` alone in the main scene; with `stand_in`, preset `number` in
## the scene's comfort wiring is replaced by it before the step starts.
func _run_step(step: AcceptanceStep, stand_in: ComfortPreset, number: int = 0) -> Array:
	var only: AcceptanceSuite = AcceptanceSuite.new()
	only.name = "m1"
	only.steps.append(step)
	var suites: Array[AcceptanceSuite] = [only]
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	if stand_in != null:
		step.preset = AcceptanceStep.NO_PRESET  # The runner keeps the stand-in set below.
		var wiring: ComfortWiring = main.get("comfort")
		wiring.set_preset(number)
		wiring.preset = stand_in
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.setup(main, suites, null)
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
	runner.main.free()
	runner.free()
	return [code, text, measurements]
