extends RefCounted

## The m3 suite flown once, as `--acceptance=m3` flies it, and its report shared
## by every test that needs a step to pass through the runner (#1139, DEV-3).
## Each of those tests used to fly its step alone in a fresh main scene, and
## `test_m3_suite.gd` then flew all seven again: about 95 s of the unit test job
## spent repeating the same flights. The same replays, seeds and data always
## give the same flights (ARC-2), so one run serves them all, and each test
## still asserts its own measurements on its own step's entry.
##
## Only tests read this. Nothing here changes how the runner flies a step. The
## entries are deep copies, so a test that changes one cannot change another's.

const SUITE_NAME: String = "m3"
## Seven steps of a few thousand ticks each; the runner flies one per frame.
const FRAME_LIMIT: int = 160000

static var _flown: bool = false
static var _finished: bool = false
static var _exit_code: int = -1
static var _passed: bool = false
static var _messages: Array[String] = []
static var _steps: Array[Dictionary] = []
static var _quit_codes: Array[int] = []


## Flies the suite the first time it is asked for; later calls do nothing.
static func fly() -> void:
	if _flown:
		return
	_flown = true
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(code: int) -> void: _quit_codes.append(code)
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	# Built and readied as on the headset, so the map in the hand and the
	# cockpit that `map_route`, `map_markers` and `escape_cue` read are there.
	main.get_node("XRRig").call("build")
	main.call("_ready")
	runner.setup(main, AcceptanceSuite.load_named(SUITE_NAME), null)
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	_finished = runner.finished
	_exit_code = runner.exit_code
	_messages.assign(runner.messages)
	if not runner.reports.is_empty():
		_passed = runner.reports[0].passed()
		for step: Dictionary in runner.reports[0].steps:
			_steps.append(step.duplicate(true))
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.main != null:
		runner.main.free()
	runner.free()


## "" when the whole suite finished, exited with a pass and its report passed;
## otherwise why not, with the runner's log.
static func suite_problem() -> String:
	fly()
	if not _finished:
		return "the m3 suite did not finish in %d frames" % FRAME_LIMIT
	if _exit_code != AcceptanceRunner.EXIT_PASS or not _passed:
		return "exit %d: %s" % [_exit_code, "\n".join(_messages)]
	return ""


## The report entry of step `step_id` (id, result, message, measurements), a
## copy; empty if the suite did not run it.
static func step(step_id: String) -> Dictionary:
	fly()
	for found: Dictionary in _steps:
		if found.get("id") == step_id:
			return found.duplicate(true)
	return {}


## The entries of every step, in the order they ran, copies.
static func steps() -> Array[Dictionary]:
	fly()
	var copies: Array[Dictionary] = []
	for found: Dictionary in _steps:
		copies.append(found.duplicate(true))
	return copies


## "" when step `step_id` ran and passed; otherwise why not, with the log.
static func step_problem(step_id: String) -> String:
	var found: Dictionary = step(step_id)
	if found.is_empty():
		return "the m3 suite did not run %s: %s" % [step_id, "\n".join(_messages)]
	if found.get("result") != AcceptanceReport.RESULT_PASS:
		return "%s %s: %s" % [step_id, found.get("result"), found.get("message")]
	return ""


static func messages() -> Array[String]:
	fly()
	return _messages.duplicate()
