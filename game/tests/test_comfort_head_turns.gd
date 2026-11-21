extends RefCounted

## The `comfort_motion` check judges what the game does to the view, not the
## tester's head (#735, CMF-1, CMF-3, DEV-6). On the owner's Quest 3 presets 1
## and 2 failed at 103 and 115°/s while he looked around during the suite.

## Rendered frames in the runner are one tick long.
const FRAME_SECONDS: float = ShipState.TICK_DT
## The head's turn per frame for 100°/s.
const HEAD_STEP_DEG: float = 100.0 * ShipState.TICK_DT


func _check(preset_number: int) -> AcceptanceComfortCheck:
	return AcceptanceComfortCheck.new(preset_number, ComfortPresetFiles.load_number(preset_number))


## Feeds `check` `count` frames: the game yaws the rig `game_step_deg` and the
## head yaws `head_step_deg` inside it, each frame. `head_start` tilts the head.
static func _fly(check: AcceptanceComfortCheck, count: int, game_step_deg: float, head_step_deg: float,
		head_start: Basis = Basis.IDENTITY) -> void:
	var rig: Basis = Basis.IDENTITY
	var head: Basis = head_start
	check.sample(rig * head, FRAME_SECONDS, head)
	for i: int in count:
		rig = rig * Basis(Vector3.UP, deg_to_rad(game_step_deg))
		head = Basis(Vector3.UP, deg_to_rad(head_step_deg)) * head
		check.sample(rig * head, FRAME_SECONDS, head)


func test_a_head_turning_100_deg_s_passes_presets_1_and_2() -> String:
	for preset_number: int in [1, 2]:
		var check: AcceptanceComfortCheck = _check(preset_number)
		_fly(check, 60, 0.0, HEAD_STEP_DEG)
		var measurements: Dictionary = {}
		var result: Array = check.run(measurements)
		if result[0] != AcceptanceReport.RESULT_PASS:
			return "preset %d failed on head turns alone: %s" % [preset_number, result]
		if check.smooth_rotation_frames != 0 or check.max_yaw_deg_s > 0.01:
			return "preset %d counted head turns as the game's: %s" % [preset_number, measurements]
		if absf(float(measurements.get("max_head_deg_s", 0.0)) - 100.0) > 0.5:
			return "preset %d head speed %s, expected 100°/s" % [preset_number, measurements.get("max_head_deg_s")]
		# 60 frames at 100°/s is 100°.
		if absf(float(measurements.get("head_turn_deg", 0.0)) - 100.0) > 0.5:
			return "preset %d head turn %s, expected 100°" % [preset_number, measurements.get("head_turn_deg")]
		if not str(result[1]).contains("the head turned up to 100°"):
			return "preset %d result line does not name the head turn: %s" % [preset_number, result[1]]
	return ""


## The filter bypassed: the game yaws smoothly while the head turns the other
## way, so the view the camera sees barely moves. The game's turn still fails.
func test_a_bypassed_filter_still_fails_while_the_head_turns() -> String:
	var preset_1: AcceptanceComfortCheck = _check(1)
	_fly(preset_1, 30, 1.0, -1.0)
	var result: Array = preset_1.run({})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("smoothly"):
		return "preset 1 with smooth game yaw gave %s" % [result]
	var preset_2: AcceptanceComfortCheck = _check(2)
	_fly(preset_2, 30, 1.5, HEAD_STEP_DEG)
	result = preset_2.run({})
	if result[0] != AcceptanceReport.RESULT_FAIL or not str(result[1]).contains("yawed"):
		return "preset 2 with 90°/s game yaw gave %s" % [result]
	return ""


## A still head, level or tilted, gives the same numbers as the view alone.
func test_a_still_head_changes_nothing() -> String:
	var plain: AcceptanceComfortCheck = _check(2)
	_fly(plain, 30, 0.9, 0.0)
	var tilted: AcceptanceComfortCheck = _check(2)
	_fly(tilted, 30, 0.9, 0.0, Basis(Vector3.RIGHT, deg_to_rad(-20.0)) * Basis(Vector3.UP, deg_to_rad(35.0)))
	var a: Dictionary = {}
	var b: Dictionary = {}
	var result_a: Array = plain.run(a)
	var result_b: Array = tilted.run(b)
	if result_a != result_b:
		return "results differ: %s and %s" % [result_a, result_b]
	for key: String in ["max_yaw_deg_s", "max_pitch_deg_s", "max_roll_deg_s"]:
		if absf(float(a[key]) - float(b[key])) > 0.01:
			return "%s %s with a level head, %s with a tilted one" % [key, a[key], b[key]]
	if float(b["head_turn_deg"]) > 0.01 or str(result_b[1]).contains("head"):
		return "a still head was reported as turning: %s" % [result_b]
	return ""


## The runner's path: the head pose is the camera's own transform under the
## rig, read from the main scene's nodes.
func test_the_main_scene_camera_gives_the_head() -> String:
	var main: Node3D = Node3D.new()
	var rig: Node3D = Node3D.new()
	rig.name = "XRRig"
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	main.add_child(rig)
	rig.add_child(camera)
	var check: AcceptanceComfortCheck = _check(1)
	for i: int in 31:
		camera.basis = Basis(Vector3.UP, deg_to_rad(HEAD_STEP_DEG * i))
		check.sample_main(main, FRAME_SECONDS)
	main.free()
	var result: Array = check.run({})
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "head turns read from the camera failed preset 1: %s" % [result]
	if absf(check.max_head_deg_s - 100.0) > 0.5:
		return "head speed %.2f°/s from the camera, expected 100" % check.max_head_deg_s
	return ""
