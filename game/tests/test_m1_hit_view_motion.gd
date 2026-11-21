extends RefCounted

## The `hit_view_motion` check and the m1 suite's `comfort_hits_preset_2` to
## `_4` steps (#849, CMF-1, CMF-6, DEV-6): the comfort table's "Hits" row as
## the player sees it. Presets 2 and 3 shake without spin, preset 4 shakes and
## spins, and each step ends on m2's destroyed-ship hash, because a preset never
## changes the simulation.

const M1_PATH: String = "res://acceptance/suites/m1.json"
const REPLAY_PATH: String = "res://acceptance/replays/ship_destroyed_test_tunnel.replay"
const PRESET_1_STEP: String = "comfort_preset_1_destroyed"
const STEP_IDS: Dictionary[int, String] = {
	2: "comfort_hits_preset_2",
	3: "comfort_hits_preset_3",
	4: "comfort_hits_preset_4",
}
const FRAME_LIMIT: int = 4000


static func _find(id: String) -> AcceptanceStep:
	for step: AcceptanceStep in AcceptanceSuite.load_file(M1_PATH).steps:
		if step.id == id:
			return step
	return null


func test_the_three_steps_are_listed_with_their_checks_and_hash() -> String:
	var preset_1: AcceptanceStep = _find(PRESET_1_STEP)
	if preset_1 == null:
		return "m1 has no step %s" % PRESET_1_STEP
	var wanted: Array[String] = [AcceptanceStep.CHECK_HIT_VIEW_MOTION, AcceptanceStep.CHECK_COMFORT_MOTION,
		AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS]
	for number: int in STEP_IDS:
		var step: AcceptanceStep = _find(STEP_IDS[number])
		if step == null:
			return "m1 has no step %s" % STEP_IDS[number]
		if step.preset != number or step.replay_path != REPLAY_PATH:
			return "%s flies preset %d on %s" % [step.id, step.preset, step.replay_path]
		if step.checks != wanted:
			return "%s checks %s" % [step.id, step.checks]
		# CMF-6: the same hash as preset 1's step on the same replay.
		if step.expected_hash != preset_1.expected_hash or step.expected_hash != 3298909347:
			return "%s expects %d, preset 1's step %d" % [step.id, step.expected_hash, preset_1.expected_hash]
	return ""


func test_the_check_needs_a_replay() -> String:
	var parsed: AcceptanceSuite = AcceptanceSuite.parse_json(
		'{"name": "t", "steps": [{"id": "s", "checks": ["hit_view_motion"]}]}')
	if parsed.error.find("needed by the hit_view_motion check") < 0:
		return "a step without a replay was accepted: %s" % parsed.error
	return ""


## The rig is placed as pose × hit offset × recentre offset; the check gets the
## hit offset back, whatever the pose and recentre.
func test_unexplained_recovers_the_hit_offset() -> String:
	var pose: Transform3D = Transform3D(Basis(Vector3(0.3, 1.0, -0.2).normalized(), 1.1), Vector3(40.0, -12.0, 85.0))
	var hit: Transform3D = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(3.0)), Vector3(0.004, -0.002, 0.001))
	var offset: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.1, -1.6, 0.2)).affine_inverse()
	var found: Transform3D = AcceptanceHitMotionCheck.unexplained(pose, pose * hit * offset, offset)
	if found.origin.distance_to(hit.origin) > 0.0001:
		return "shake %s, wanted %s" % [found.origin, hit.origin]
	var angle: float = rad_to_deg(found.basis.get_rotation_quaternion().get_angle())
	if absf(angle - 3.0) > 0.01:
		return "spin %.3f°, wanted 3°" % angle
	return ""


## Preset 1's real values (no shake, no spin) pass a still view, and fail a
## frame that shakes, naming the preset and the frame.
func test_preset_1_passes_still_and_fails_a_shaken_frame() -> String:
	var preset: ComfortPreset = ComfortPresetFiles.load_number(1)
	var check: AcceptanceHitMotionCheck = AcceptanceHitMotionCheck.new()
	for i: int in 10:
		check.sample(Transform3D.IDENTITY, 1, preset)
	var result: Array = check.run({})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "a still preset 1 failed: %s" % result[1]
	check.sample(Transform3D(Basis.IDENTITY, Vector3(0.003, 0.0, 0.0)), 1, preset)
	result = check.run({})
	if result[0] == AcceptanceReport.RESULT_PASS or str(result[1]).find("preset 1 frame 11: the view shook 3.0 mm") < 0:
		return "a shaken preset 1 frame: %s" % [result]
	return ""


## Noise under the floors is neither shake nor spin.
func test_noise_is_not_motion() -> String:
	var check: AcceptanceHitMotionCheck = AcceptanceHitMotionCheck.new()
	var noise: Transform3D = Transform3D(Basis(Vector3.FORWARD, deg_to_rad(0.01)), Vector3(0.0001, 0.0, 0.0))
	check.sample(noise, 1, ComfortPresetFiles.load_number(1))
	if check.shake_frames != 0 or check.spin_frames != 0:
		return "noise counted: shake %d, spin %d" % [check.shake_frames, check.spin_frames]
	return ""


## Each real preset passes its step in the main scene, with the motion its
## hits row asks for: 2 and 3 shake without spin, 4 shakes and spins, and
## preset 3's full shake reaches further than preset 2's light one.
func test_each_preset_passes_its_step_with_its_own_motion() -> String:
	var shake_mm: Dictionary[int, float] = {}
	for number: int in STEP_IDS:
		var report: Array = _run_step(_find(STEP_IDS[number]), null)
		if report[0] != AcceptanceRunner.EXIT_PASS:
			return "preset %d: exit %d: %s" % [number, report[0], report[1]]
		var measured: Dictionary = report[2]
		var spins: int = int(measured.get("hit_spin_frames", -1))
		if int(measured.get("hit_shake_frames", 0)) <= 0 or (spins > 0) != (number == 4):
			return "preset %d measured %s" % [number, measured]
		shake_mm[number] = float(measured.get("max_hit_shake_mm", 0.0))
	if shake_mm[2] >= shake_mm[3]:
		return "preset 2 shook up to %.2f mm, preset 3 %.2f mm" % [shake_mm[2], shake_mm[3]]
	return ""


## A stand-in preset 2 whose hits row spins fails the step, naming spin.
func test_a_spinning_preset_2_fails_naming_spin() -> String:
	var stand_in: ComfortPreset = ComfortPresetFiles.load_number(2).duplicate() as ComfortPreset
	stand_in.hit_spin = true
	var report: Array = _run_step(_find(STEP_IDS[2]), stand_in, 2)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS:
		return "a spinning preset 2 passed: %s" % text
	var line: RegEx = RegEx.create_from_string("hit_view_motion: preset 2 frame \\d+: the view spun [0-9.]+°, but hit_spin is off")
	if line.search(text) == null:
		return "the failure does not name the spin: %s" % text
	return ""


## A stand-in preset 4 without shake fails the step, naming shake.
func test_a_still_preset_4_fails_naming_shake() -> String:
	var stand_in: ComfortPreset = ComfortPresetFiles.load_number(4).duplicate() as ComfortPreset
	stand_in.hit_shake = 0.0
	var report: Array = _run_step(_find(STEP_IDS[4]), stand_in, 4)
	var text: String = str(report[1])
	if report[0] == AcceptanceRunner.EXIT_PASS:
		return "a still preset 4 passed: %s" % text
	if text.find("hit_view_motion: preset 4: no frame shook the view, but hit_shake is") < 0:
		return "the failure does not name the shake: %s" % text
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
		wiring.hit_shake.preset = stand_in
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
