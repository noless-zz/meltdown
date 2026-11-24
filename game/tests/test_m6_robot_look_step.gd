extends RefCounted

## The m6 `robot_look` step (#1307, GFX-2, CMB-3, DEV-6): the owner's G6
## "screenshots approved" check needs the robots' new bodies on record, so the
## step flies the test-tunnel bot replay, which faces all six robot types from
## 3 to 26 m for its whole length, with screenshots along it and at its end.
## Its pinned hash is the replay's own (m2 `bot_clears_test_tunnel`), so the
## look leaves the simulation alone (ARC-1, ARC-2). It must pass through the
## acceptance runner in the main scene.

const PART_PATH: String = "res://acceptance/suites/m6/ship.json"
const STEP_ID: String = "robot_look"
const REPLAY: String = "res://acceptance/replays/bot_test_tunnel.replay"
## The hash m2 `bot_clears_test_tunnel` pins for the same replay.
const REPLAY_HASH: int = 517117812
const ROBOTS_DIR: String = "res://data/robots"
const FRAME_SECONDS: float = 0.25
const FRAME_LIMIT: int = 600


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


func test_the_step_shows_every_robot_type_with_screenshots() -> String:
	if not FileAccess.get_file_as_string(PART_PATH).contains("\"%s\"" % STEP_ID):
		return "%s does not hold the %s step" % [PART_PATH, STEP_ID]
	var suite: AcceptanceSuite = _shipped_step()
	if suite.steps.size() != 1:
		return "m6 has %d %s steps" % [suite.steps.size(), STEP_ID]
	var step: AcceptanceStep = suite.steps[0]
	if step.replay_path != REPLAY:
		return "the step flies %s, not the test-tunnel bot replay" % step.replay_path
	if step.screenshot_ticks.is_empty() or not step.screenshot_at_end:
		return "the step takes no screenshots along the flight and at its end"
	if not step.checks.has(AcceptanceStep.CHECK_FINAL_HASH) or not step.checks.has(AcceptanceStep.CHECK_NO_SCRIPT_ERRORS):
		return "the step checks %s" % [step.checks]
	if step.expected_hash != REPLAY_HASH:
		return "the step pins %d, not the replay's own hash %d" % [step.expected_hash, REPLAY_HASH]
	var replay: Replay = Replay.load_file(REPLAY)
	var placed: Dictionary[String, bool] = {}
	for spawn: RobotSpawn in replay.robots:
		placed[spawn.def.id] = true
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.ends_with(".json") and not placed.has(file.get_basename()):
			return "the replay places no %s" % file.get_basename()
	for tick: int in step.screenshot_ticks:
		if tick >= replay.frames.size():
			return "screenshot tick %d is past the replay's %d ticks" % [tick, replay.frames.size()]
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
