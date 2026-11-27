extends RefCounted

## A check's wait for the next drawn frame (#1480, DEV-6, PRF-7): the hook calls back once a frame
## was drawn after the request, or on the next frame where nothing is drawn; the runner keeps the
## step open meanwhile, under its time limit, and the checks' work leaves the scene afterwards.
## Fake clocks keep the tests independent of the machine's speed.

const SCRATCH_DIR: String = "user://test_acceptance_frame_hook"
const FRAME_LIMIT: int = 200
const PROBE: String = "FrameProbe"

## A check file whose frame work puts a node in the scene, asks for one drawn frame and leaves
## whether it was drawn for its judge. `frames.draws` is set from the file, so a test can stand in
## for a machine that draws frames, where none will come here.
const PROBE_SCRIPT: String = """extends RefCounted

static func judges() -> Dictionary[String, Callable]:
	return {"%s": _judge}


static func frame_work() -> Dictionary[String, Callable]:
	return {"%s": _start}


static func _start(_step: AcceptanceStep, runner: AcceptanceRunner, frames: AcceptanceFrameHook) -> void:
	frames.draws = %s
	var probe: Node = Node.new()
	probe.name = "%s"
	runner.main.add_child(probe)
	frames.on_end(func() -> void:
		runner.main.remove_child(probe)
		probe.free())
	frames.next_drawn_frame(func(drawn: bool, _usec: int) -> void:
		frames.results["probe"] = {"drawn": drawn, "in_scene": runner.main.has_node("%s")})


static func _judge(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	var found: Dictionary = runner.frame_hook().results.get("probe", {}) if runner.frame_hook() != null else {}
	if found.is_empty():
		return [AcceptanceReport.RESULT_FAIL, "no frame came"]
	measurements["drawn"] = found["drawn"]
	measurements["in_scene"] = found["in_scene"]
	return [AcceptanceReport.RESULT_PASS, "frame came"]
"""

var _now_usec: int = 0
var _now_msec: int = 0
var _step_msec: int = 0
var _calls: Array[Array] = []


func _usec() -> int:
	return _now_usec


func _msec() -> int:
	_now_msec += _step_msec
	return _now_msec


func _record(drawn: bool, usec: int) -> void:
	_calls.append([drawn, usec])


func _hook(draws: bool) -> AcceptanceFrameHook:
	_calls.clear()
	var hook: AcceptanceFrameHook = AcceptanceFrameHook.new()
	hook.draws = draws
	hook.clock_usec = _usec
	return hook


func test_where_nothing_is_drawn_the_callback_comes_next_frame_not_drawn() -> String:
	var hook: AcceptanceFrameHook = _hook(false)
	_now_usec = 100
	hook.next_drawn_frame(_record)
	if not hook.waiting():
		return "the request does not wait"
	_now_usec = 250
	if hook.still_waiting():
		return "still waiting after a frame"
	return "" if _calls == [[false, 250]] else "called %s" % [_calls]


func test_where_frames_are_drawn_the_callback_waits_for_one_drawn_after_the_request() -> String:
	var hook: AcceptanceFrameHook = _hook(true)
	_now_usec = 50
	hook.frame_drawn()  # Before any request: does not count.
	hook.next_drawn_frame(_record)
	if not hook.still_waiting() or not _calls.is_empty():
		return "called before a frame was drawn: %s" % [_calls]
	_now_usec = 400
	hook.frame_drawn()
	_now_usec = 900
	hook.frame_drawn()  # A second draw before the runner's frame keeps the first time.
	if hook.still_waiting():
		return "still waiting after a drawn frame"
	return "" if _calls == [[true, 400]] else "called %s" % [_calls]


func test_a_request_made_in_a_callback_waits_for_a_later_frame() -> String:
	var hook: AcceptanceFrameHook = _hook(true)
	var chain: Callable = func(drawn: bool, usec: int) -> void:
		_record(drawn, usec)
		if _calls.size() < 2:
			hook.next_drawn_frame(_record)
	hook.next_drawn_frame(chain)
	_now_usec = 10
	hook.frame_drawn()
	if not hook.still_waiting() or _calls.size() != 1:
		return "after the first frame: %s, waiting %s" % [_calls, hook.waiting()]
	if not hook.still_waiting() or _calls.size() != 1:
		return "the second request was answered by the first frame: %s" % [_calls]
	_now_usec = 20
	hook.frame_drawn()
	if hook.still_waiting():
		return "still waiting after the second frame"
	return "" if _calls == [[true, 10], [true, 20]] else "called %s" % [_calls]


func test_end_drops_waiting_callbacks_and_runs_each_cleanup_once() -> String:
	var hook: AcceptanceFrameHook = _hook(false)
	var cleaned: Array[int] = [0]
	hook.on_end(func() -> void: cleaned[0] += 1)
	hook.next_drawn_frame(_record)
	hook.end()
	hook.end()
	if hook.waiting() or not _calls.is_empty():
		return "a callback outlived the end: %s" % [_calls]
	return "" if cleaned[0] == 1 else "cleaned %d times" % cleaned[0]


func test_the_live_hook_draws_nothing_on_the_headless_display() -> String:
	if DisplayServer.get_name() != "headless":
		return ""
	var hook: AcceptanceFrameHook = AcceptanceFrameHook.live()
	hook.end()
	return "" if not hook.draws else "the headless hook expects drawn frames"


func test_a_step_without_frame_work_makes_no_hook() -> String:
	var step: AcceptanceStep = AcceptanceStep.new()
	step.checks = ["no_script_errors"] as Array[String]
	var hook: AcceptanceFrameHook = AcceptanceFrameHook.start_work(step, null, null)
	return "" if hook == null else "a hook was made for no frame work"


func test_frame_work_must_name_its_own_checks() -> String:
	var bad: String = PROBE_SCRIPT % ["probe_a", "probe_b", "false", PROBE, PROBE]
	_use("bad_name", {"bad.gd": bad})
	var problem: String = AcceptanceCheckFiles.problem()
	_restore()
	return "" if problem.contains("frame_work(): 'probe_b' is not one of this file's checks") \
		else "problem '%s'" % problem


## Headless: the frame work runs before the judge, its node is in the scene for the frame and gone
## after the step, and the judge sees "not drawn".
func test_the_runner_holds_the_step_for_the_frame_and_the_judge_reads_it() -> String:
	_use("not_drawn", {"probe.gd": PROBE_SCRIPT % ["frame_probe", "frame_probe", "false", PROBE, PROBE]})
	var runner: AcceptanceRunner = _runner("{\"id\": \"probe\", \"checks\": [\"frame_probe\"]}")
	_run(runner)
	var problem: String = ""
	var steps: Array[Dictionary] = runner.reports[0].steps if not runner.reports.is_empty() else []
	if steps.size() != 1 or steps[0]["result"] != AcceptanceReport.RESULT_PASS:
		problem = "the step gave %s: %s" % [steps, "\n".join(runner.messages)]
	elif steps[0]["measurements"] != {"drawn": false, "in_scene": true}:
		problem = "measured %s" % steps[0]["measurements"]
	elif runner.main.has_node(PROBE):
		problem = "the frame work's node stayed in the scene"
	_done(runner)
	return problem


## A machine that should draw but never does: the step fails at its time limit, and the frame
## work's node still leaves the scene.
func test_a_frame_that_never_comes_fails_at_the_time_limit_and_cleans_up() -> String:
	_use("never_drawn", {"probe.gd": PROBE_SCRIPT % ["frame_probe", "frame_probe", "true", PROBE, PROBE]})
	_step_msec = 1000
	var runner: AcceptanceRunner = _runner("{\"id\": \"probe\", \"checks\": [\"frame_probe\"], \"time_limit_seconds\": 5}")
	_run(runner)
	var problem: String = ""
	var steps: Array[Dictionary] = runner.reports[0].steps if not runner.reports.is_empty() else []
	if steps.size() != 1 or steps[0]["result"] != AcceptanceReport.RESULT_FAIL \
			or not str(steps[0]["message"]).begins_with("timed out after 5 s"):
		problem = "the step gave %s" % [steps]
	elif runner.main.has_node(PROBE):
		problem = "the frame work's node stayed in the scene after the time-out"
	_done(runner)
	return problem


func _runner(step_json: String) -> AcceptanceRunner:
	_now_msec = 0
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json("{\"name\": \"t1480\", \"steps\": [%s]}" % step_json)
	var suites: Array[AcceptanceSuite] = [suite]
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = func(_code: int) -> void: pass
	runner.clock_msec = _msec
	runner.setup(Node.new(), suites, null)
	return runner


func _run(runner: AcceptanceRunner) -> void:
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1


func _done(runner: AcceptanceRunner) -> void:
	_step_msec = 0
	_restore()
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	if runner.exit_path != "":
		DirAccess.remove_absolute(runner.exit_path)
	runner.main.free()
	runner.free()


## A fresh scratch folder `name` holding `files`, read as the check files; a loaded script stays
## cached by its path, so each test uses its own folder.
static func _use(name: String, files: Dictionary[String, String]) -> void:
	var dir: String = SCRATCH_DIR.path_join(name)
	DirAccess.make_dir_recursive_absolute(dir)
	for old: String in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(old))
	for file_name: String in files:
		var file: FileAccess = FileAccess.open(dir.path_join(file_name), FileAccess.WRITE)
		file.store_string(files[file_name])
		file.close()
	AcceptanceCheckFiles.use_dir(dir)


static func _restore() -> void:
	AcceptanceCheckFiles.use_dir(AcceptanceCheckFiles.CHECKS_DIR)
