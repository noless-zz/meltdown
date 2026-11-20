extends RefCounted

## The `comfort_motion` check and the m1 `comfort_preset_*` steps (#687,
## CMF-1, CMF-3, CMF-8, ARC-3, DEV-6, umbrella #153). The check is fed fake
## camera rotations here, then flown in the real main scene by the runner.
##
## The steps for presets 1 and 2 are not in the suite: the runner hands a
## replay's recorded inputs straight to the session, past the comfort filter,
## so the smooth turns of `m1_flight_axes.replay` reach the view on every
## preset. `test_the_raw_replay_breaks_presets_1_and_2` pins that, so the
## follow-up that routes replays through the filter sees it change.

const SUITE_PATH: String = "res://acceptance/suites/m1.json"
const REPLAY_PATH: String = "res://acceptance/replays/m1_flight_axes.replay"
const STEP_IDS: Array[String] = ["comfort_preset_3", "comfort_preset_4"]
const FLIGHT_AXES_ID: String = "flight_axes"
## Rendered frames in the runner are one tick long.
const FRAME_SECONDS: float = ShipState.TICK_DT
const FRAME_LIMIT: int = 6000

var _quit_codes: Array[int] = []


func _check(preset_number: int) -> AcceptanceComfortCheck:
	return AcceptanceComfortCheck.new(preset_number, ComfortPresetFiles.load_number(preset_number))


## Feeds `check` a view yawing `yaw_steps[i]` degrees on frame i.
static func _fly(check: AcceptanceComfortCheck, yaw_steps: Array[float]) -> void:
	var view: Basis = Basis.IDENTITY
	check.sample(view, FRAME_SECONDS)
	for step_deg: float in yaw_steps:
		view = view * Basis(Vector3.UP, deg_to_rad(step_deg))
		check.sample(view, FRAME_SECONDS)


static func _repeat(value: float, count: int) -> Array[float]:
	var values: Array[float] = []
	for i: int in count:
		values.append(value)
	return values


func test_preset_1_passes_a_view_that_only_snaps() -> String:
	var check: AcceptanceComfortCheck = _check(1)
	var steps: Array[float] = _repeat(0.0, 20)
	steps.append(30.0)
	steps.append_array(_repeat(0.0, 20))
	steps.append(-30.0)
	_fly(check, steps)
	var result: Array = check.run({})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "snaps only: %s" % [result]
	if check.snap_frames != 2 or check.smooth_rotation_frames != 0:
		return "%d snaps and %d smooth frames counted" % [check.snap_frames, check.smooth_rotation_frames]
	return ""


func test_preset_1_fails_a_view_that_turns_smoothly() -> String:
	var check: AcceptanceComfortCheck = _check(1)
	_fly(check, _repeat(1.0, 30))
	var measurements: Dictionary = {}
	var result: Array = check.run(measurements)
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("smoothly"):
		return "a smooth turn gave %s" % [result]
	if measurements.get("smooth_rotation_frames") != 30:
		return "measurements %s" % measurements
	if absf(float(measurements.get("max_yaw_deg_s")) - 60.0) > 0.1:
		return "1° a frame at 60 frames a second measured %s°/s" % measurements.get("max_yaw_deg_s")
	return ""


## Preset 2 caps yaw at 60°/s: 54°/s passes, 63.6°/s (just under 5 % over)
## passes, 90°/s fails.
func test_preset_2_fails_only_above_its_yaw_cap() -> String:
	var cap: float = ComfortPresetFiles.load_number(2).yaw_rate_cap_deg_per_s
	if cap <= 0.0:
		return "preset 2 has no yaw cap to test against"
	for case: Array in [[0.9, true], [cap * 1.04 * FRAME_SECONDS, true], [1.5, false]]:
		var check: AcceptanceComfortCheck = _check(2)
		_fly(check, _repeat(float(case[0]), 30))
		var result: Array = check.run({})
		if (result[0] == AcceptanceReport.RESULT_PASS) != bool(case[1]):
			return "%.2f° a frame gave %s" % [case[0], result]
	return ""


func test_presets_3_and_4_only_report() -> String:
	for preset_number: int in [3, 4]:
		var check: AcceptanceComfortCheck = _check(preset_number)
		_fly(check, _repeat(3.0, 30))
		var result: Array = check.run({})
		if result[0] != AcceptanceReport.RESULT_PASS or check.max_yaw_deg_s < 179.0:
			return "preset %d: %s" % [preset_number, result]
	return ""


func test_no_frames_fails() -> String:
	var result: Array = _check(1).run({})
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "nothing sampled gave %s" % [result]


## The camera's world rotation is composed from its parents, so it also reads
## right outside a scene tree.
func test_world_basis_composes_parents() -> String:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	rig.add_child(camera)
	rig.basis = Basis(Vector3.UP, deg_to_rad(40.0))
	camera.basis = Basis(Vector3.UP, deg_to_rad(5.0))
	var yaw: float = rad_to_deg(AcceptanceComfortCheck.world_basis(camera).get_euler().y)
	rig.free()
	return "" if absf(yaw - 45.0) < 0.01 else "world yaw %.3f" % yaw


func test_the_check_needs_a_replay_and_is_known() -> String:
	if not AcceptanceStep.KNOWN_CHECKS.has(AcceptanceStep.CHECK_COMFORT_MOTION):
		return "comfort_motion is not a known check"
	var without: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t\", \"steps\": [{\"id\": \"a\", \"preset\": 1, \"checks\": [\"comfort_motion\"]}]}")
	if not without.error.contains("needed by the comfort_motion check"):
		return "a step without a replay gave '%s'" % without.error
	return ""


func test_the_steps_fly_flight_axes_on_its_hash() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	if suite.error != "":
		return suite.error
	var axes_hash: int = AcceptanceStep.NO_HASH
	var found: Dictionary = {}
	for step: AcceptanceStep in suite.steps:
		if step.id == FLIGHT_AXES_ID:
			axes_hash = step.expected_hash
		found[step.id] = step
	for index: int in STEP_IDS.size():
		var step: AcceptanceStep = found.get(STEP_IDS[index])
		if step == null:
			return "m1 has no step %s" % STEP_IDS[index]
		if step.replay_path != REPLAY_PATH or step.preset != index + 3:
			return "%s flies %s on preset %d" % [step.id, step.replay_path, step.preset]
		if step.checks != [AcceptanceStep.CHECK_COMFORT_MOTION, AcceptanceStep.CHECK_FINAL_HASH]:
			return "%s checks %s" % [step.id, step.checks]
		# ARC-3: a preset never changes the simulation, so the hash is flight_axes' own.
		if step.expected_hash != axes_hash or axes_hash == AcceptanceStep.NO_HASH:
			return "%s expects hash %d, flight_axes %d" % [step.id, step.expected_hash, axes_hash]
	return ""


## Both steps pass in the real main scene, on the same final hash, and the
## view really is read: preset 4's hit spin turns it on the wall hits, which
## the other presets never do.
func test_the_steps_pass_in_the_main_scene() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var rolls: Array[float] = []
	for step: AcceptanceStep in suite.steps:
		if not STEP_IDS.has(step.id):
			continue
		var report: Array = _run_step(step)
		if report[0] != AcceptanceRunner.EXIT_PASS:
			return "%s exit %d: %s" % [step.id, report[0], report[1]]
		var measurements: Dictionary = report[2]
		if int(measurements.get("comfort_frames", 0)) < 2000 or int(measurements.get("smooth_rotation_frames", 0)) == 0:
			return "%s measured %s" % [step.id, measurements]
		rolls.append(float(measurements.get("max_roll_deg_s")))
	if rolls.size() != 2 or rolls[1] <= rolls[0]:
		return "roll at most %s on presets 3 and 4" % [rolls]
	return ""


## The raw replay's smooth turns reach the view on presets 1 and 2, so their
## steps would fail today (see the top of this file). The final hash is the
## same on every preset (ARC-3).
func test_the_raw_replay_breaks_presets_1_and_2() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_file(SUITE_PATH)
	var template: AcceptanceStep = null
	for step: AcceptanceStep in suite.steps:
		if step.id == STEP_IDS[0]:
			template = step
	if template == null:
		return "m1 has no step %s" % STEP_IDS[0]
	for case: Array in [[1, "smoothly"], [2, "yawed"]]:
		var step: AcceptanceStep = AcceptanceStep.new()
		step.id = "comfort_preset_%d" % case[0]
		step.replay_path = template.replay_path
		step.preset = case[0]
		step.checks.assign(template.checks)
		step.expected_hash = template.expected_hash
		var report: Array = _run_step(step)
		if report[0] == AcceptanceRunner.EXIT_PASS or not str(report[1]).contains(case[1]) \
				or report[2].get("final_hash") != template.expected_hash:
			return "preset %d gave exit %d: %s" % [case[0], report[0], report[1]]
	return ""


## [exit code, messages and step results, the step's measurements] of the
## runner flying `step` alone in the main scene.
func _run_step(step: AcceptanceStep) -> Array:
	_quit_codes.clear()
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


func _on_quit(code: int) -> void:
	_quit_codes.append(code)
