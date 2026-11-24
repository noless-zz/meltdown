extends RefCounted

## The m6 `wall_depth` step (#1323, GFX-2, PRF-2, DEV-6): the owner's G6
## "screenshots approved" check needs the framed openings and bevelled edges
## on record. The `wall_material` step flies the test tunnel, which has no
## opening, so this one flies m2's `bot_clears_g2_level` flight through G2,
## with screenshots where the ship faces a doorway at 8 to 12 m (ticks 1275,
## 1815, 2340, 2625, 2745). Its pinned hash is m2's, so the look leaves the
## simulation alone (ARC-1, ARC-2). `wall_depth_shown` then reads the view.

const WallDepthCheck := preload("res://acceptance/checks/wall_depth_check.gd")

const PART_PATH: String = "res://acceptance/suites/m6/effects.json"
const M2_PATH: String = "res://acceptance/suites/m2.json"
const STEP_ID: String = "wall_depth"
const M2_STEP_ID: String = "bot_clears_g2_level"
const FRAME_LIMIT: int = 8000


static func _step_from(steps: Array[AcceptanceStep], id: String) -> AcceptanceStep:
	for found: AcceptanceStep in steps:
		if found.id == id:
			return found
	return null


static func _shipped_step() -> AcceptanceStep:
	var found: Array[AcceptanceSuite] = AcceptanceSuite.load_named("m6")
	if found.size() != 1 or found[0].error != "":
		return null
	return _step_from(found[0].steps, STEP_ID)


func test_the_step_flies_the_g2_flight_with_screenshots_and_the_check() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var step: AcceptanceStep = _shipped_step()
	var m2: AcceptanceStep = _step_from(AcceptanceSuite.load_file(M2_PATH).steps, M2_STEP_ID)
	if step == null or m2 == null:
		return "steps found: m6 %s %s, m2 %s %s" % [STEP_ID, step, M2_STEP_ID, m2]
	if step.replay_path != m2.replay_path or step.expected_hash != m2.expected_hash:
		return "the step flies %s pinned at %d, not m2 %s's flight" % [step.replay_path, step.expected_hash, M2_STEP_ID]
	for check: String in [AcceptanceStep.CHECK_FINAL_HASH, AcceptanceStep.CHECK_NO_SCRIPT_ERRORS, WallDepthCheck.CHECK]:
		if not step.checks.has(check):
			return "the step does not check %s: %s" % [check, step.checks]
	if not WallDepthCheck.judges().has(WallDepthCheck.CHECK):
		return "the check file does not judge %s" % WallDepthCheck.CHECK
	var replay: Replay = Replay.load_file(step.replay_path)
	if step.screenshot_ticks.size() < 4:
		return "the step takes %d screenshots" % step.screenshot_ticks.size()
	for tick: int in step.screenshot_ticks:
		if tick >= replay.frames.size():
			return "screenshot tick %d is past the replay's %d ticks" % [tick, replay.frames.size()]
	return ""


func test_a_level_with_no_opening_fails_the_check() -> String:
	var view: LevelView = LevelView.new()
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	view.build(BoxUnion.new(boxes))
	var measurements: Dictionary = {}
	var verdict: Array = WallDepthCheck.judge_view(view, measurements)
	view.free()
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not String(verdict[1]).contains("framed"):
		return "one box with no opening gave %s" % [verdict]
	if WallDepthCheck.judge_view(null, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "no level view passed"
	return ""


func test_the_shipped_step_passes_in_the_main_scene() -> String:
	var step: AcceptanceStep = _shipped_step()
	if step == null:
		return "m6 has no %s step" % STEP_ID
	var suite: AcceptanceSuite = AcceptanceSuite.new()
	suite.name = "m6"
	suite.steps.append(step)
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var text: String = "\n".join(runner.messages)
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	var code: int = runner.exit_code if runner.finished else -1
	if runner.main != null:
		runner.main.free()
	runner.free()
	if code != AcceptanceRunner.EXIT_PASS:
		return "the step did not pass (exit %d): %s" % [code, text]
	return ""
