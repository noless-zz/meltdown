extends RefCounted

## Acceptance steps that fly a level (#334): the optional `level` key, the
## `robots_cleared` and `ship_alive` checks, and the m2 G2 step flown by the
## runner in the flat main scene. The scene is instantiated outside the tree,
## as in `test_acceptance_runner.gd`, so no XR session or renderer is needed.

const G2_STEP: String = "bot_clears_g2_level"
const G2_REPLAY: String = "res://acceptance/replays/bot_g2_level.replay"
const TUNNEL_REPLAY: String = "res://acceptance/replays/bot_test_tunnel.replay"
const DOCTORED_REPLAY: String = "user://t334_doctored.replay"
## Ticks cut from the end of the G2 replay for the doctored copy: the last
## robot dies on the last tick, so it is still alive a second earlier.
const CUT_TICKS: int = 60
const FRAME_LIMIT: int = 10000
const G2Level := preload("res://tests/test_m2_g2_level.gd")

var _quit_codes: Array[int] = []


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


func _run(suites: Array[AcceptanceSuite]) -> AcceptanceRunner:
	_quit_codes.clear()
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	runner.setup(scene.instantiate(), suites, null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	return runner


func _done(runner: AcceptanceRunner) -> void:
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()


func _suite(step_json: String) -> AcceptanceSuite:
	return AcceptanceSuite.parse_json("{\"name\": \"t334\", \"steps\": [%s]}" % step_json)


func _one(suite: AcceptanceSuite) -> Array[AcceptanceSuite]:
	var found: Array[AcceptanceSuite] = [suite]
	return found


func _g2_step_json() -> String:
	var step: AcceptanceStep = G2Level.step()
	return ("{\"id\": \"g2\", \"level\": \"g2\", \"replay\": \"%s\", "
		+ "\"checks\": [\"final_hash\", \"robots_cleared\", \"ship_alive\"], \"expected_hash\": %d}") % [
		G2_REPLAY, step.expected_hash if step != null else 0]


func test_level_key_is_read() -> String:
	var suite: AcceptanceSuite = _suite(_g2_step_json())
	if suite.error != "":
		return suite.error
	if suite.steps[0].level != "g2":
		return "level read as '%s'" % suite.steps[0].level
	return ""


func test_bad_level_values_and_replay_checks_without_a_replay_are_rejected() -> String:
	var cases: Dictionary[String, String] = {
		"{\"id\": \"a\", \"level\": \"../g2\", \"replay\": \"r\", \"checks\": [\"ship_alive\"]}": "steps[0].level",
		"{\"id\": \"a\", \"level\": 2, \"replay\": \"r\", \"checks\": [\"ship_alive\"]}": "steps[0].level",
		"{\"id\": \"a\", \"level\": \"g2\", \"checks\": [\"no_script_errors\"]}": "steps[0].level",
		"{\"id\": \"a\", \"checks\": [\"robots_cleared\"]}": "steps[0].replay",
		"{\"id\": \"a\", \"checks\": [\"ship_alive\"]}": "steps[0].replay",
		"{\"id\": \"a\", \"replay\": \"r\", \"checks\": [\"robot_cleared\"]}": "unknown check",
	}
	for text: String in cases:
		var suite: AcceptanceSuite = _suite(text)
		if not suite.error.contains(cases[text]):
			return "%s gave '%s', expected it to name %s" % [text, suite.error, cases[text]]
	return ""


func test_g2_step_passes_in_the_flat_main_scene_with_all_three_checks() -> String:
	var runner: AcceptanceRunner = _run(_one(_suite(_g2_step_json())))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS or not runner.reports[0].passed():
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		var message: String = step["message"]
		for check: String in AcceptanceStep.REPLAY_CHECKS:
			if not message.contains(check + ": "):
				problem = "the report does not name %s: '%s'" % [check, message]
		var measured: Dictionary = step["measurements"]
		if problem == "" and (measured.get("robots_alive") != 0 or float(measured.get("hull", 0.0)) <= 0.0):
			problem = "measured %s" % measured
		var session: LocalSession = runner.main.get("session")
		if problem == "" and session.sim.walls.boxes.size() != G2Level.level().union.boxes.size():
			problem = "the replay flew in %d boxes" % session.sim.walls.boxes.size()
		if problem == "" and runner.main.get_node_or_null(LevelView.NODE_NAME) == null:
			problem = "the scene does not draw the level"
		if problem == "" and runner.main.get_node_or_null(LevelSwitch.TUNNEL_NODE) != null:
			problem = "the test tunnel is still drawn"
	_done(runner)
	return problem


## The G2 replay with its last second cut off, so one robot outlives it.
func _write_doctored_replay() -> String:
	var replay: Replay = Replay.load_file(G2_REPLAY)
	if replay.error != "":
		return replay.error
	replay.frames.resize(replay.frames.size() - CUT_TICKS)
	replay.expected_hash = Replay.NO_HASH
	var error: Error = replay.save(DOCTORED_REPLAY)
	return "" if error == OK else "could not write %s: %s" % [DOCTORED_REPLAY, error_string(error)]


func test_a_robot_left_alive_fails_robots_cleared_naming_its_type() -> String:
	var problem: String = _write_doctored_replay()
	if problem != "":
		return problem
	var expected: Sim = Replay.load_file(DOCTORED_REPLAY).run()
	if expected == null or G2Level.live_robots(expected) != 1:
		DirAccess.remove_absolute(DOCTORED_REPLAY)
		return "the doctored replay should leave exactly one robot alive"
	var survivor: String = expected.robots[0].def.id
	var runner: AcceptanceRunner = _run(_one(_suite(
		"{\"id\": \"g2\", \"level\": \"g2\", \"replay\": \"%s\", \"checks\": [\"robots_cleared\", \"ship_alive\"]}"
		% DOCTORED_REPLAY)))
	if runner.exit_code != AcceptanceRunner.EXIT_FAIL:
		problem = "exit %d with a robot left alive" % runner.exit_code
	else:
		var step: Dictionary = runner.reports[0].steps[0]
		var message: String = step["message"]
		if step["result"] != AcceptanceReport.RESULT_FAIL:
			problem = "the step is %s" % step["result"]
		elif not message.contains("robots_cleared: 1 robots still alive: %s" % survivor):
			problem = "the message does not name the %s: '%s'" % [survivor, message]
		elif not message.contains("ship_alive: hull"):
			problem = "ship_alive did not report the hull: '%s'" % message
	_done(runner)
	DirAccess.remove_absolute(DOCTORED_REPLAY)
	return problem


func test_a_step_without_a_level_still_flies_the_test_tunnel() -> String:
	var tunnel: AcceptanceStep = null
	for step: AcceptanceStep in AcceptanceSuite.load_file(G2Level.SUITE_PATH).steps:
		if step.replay_path == TUNNEL_REPLAY:
			tunnel = step
	if tunnel == null:
		return "m2 has no test tunnel step"
	var runner: AcceptanceRunner = _run(_one(_suite(
		"{\"id\": \"tunnel\", \"replay\": \"%s\", \"checks\": [\"final_hash\", \"robots_cleared\"], \"expected_hash\": %d}"
		% [TUNNEL_REPLAY, tunnel.expected_hash])))
	var problem: String = ""
	if runner.exit_code != AcceptanceRunner.EXIT_PASS:
		problem = "exit %d: %s" % [runner.exit_code, "\n".join(runner.messages)]
	elif (runner.main.get("session") as LocalSession).sim.walls.boxes.size() != 1:
		problem = "the tunnel step did not fly one box"
	elif runner.main.get_node_or_null(LevelSwitch.TUNNEL_NODE) == null:
		problem = "the test tunnel is no longer drawn"
	elif runner.main.get_node_or_null(LevelView.NODE_NAME) != null:
		problem = "a level is drawn for a step without one"
	_done(runner)
	return problem
