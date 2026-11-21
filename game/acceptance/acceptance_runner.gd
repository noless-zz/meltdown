class_name AcceptanceRunner
extends Node

## Flies an acceptance suite inside the running game and quits with its result
## (DEV-6, PLT-1, PLT-4, #165). `main.gd` adds one only when the launch switch
## is set, so a normal start never sees it.
##
## Each step sets its comfort preset, switches to its level (#334) or builds its seed's
## level (#460), flies its replay through the scene's `advance_frame` (one tick per frame,
## replay inputs in place of the controllers), takes its screenshots (#718), runs its checks
## and records them in an `AcceptanceReport` in `user://acceptance/` and the log. Exit 0 if all pass.

## Desktop: `godot --path game -- --acceptance=m1`.
const ARG_PREFIX: String = "--acceptance="
## Headset: `adb shell am start ... --es meltdown_acceptance m1`.
const INTENT_EXTRA: String = "meltdown_acceptance"
const REPORT_DIR: String = "user://acceptance"
const EXIT_PASS: int = 0
const EXIT_FAIL: int = 1
## How long a step waits for the session to begin or the rate in use (#598): 10 s at 90 Hz.
const XR_WAIT_FRAMES: int = 900
const LOG_PREFIX: String = "Meltdown: acceptance"

## The game scene (`main.gd`): read through `session`, `build_info`,
## `advance_frame`, `set_comfort_preset` and `use_level`.
var main: Node = null
var suites: Array[AcceptanceSuite] = []
## The OpenXR interface, or null when there is none; tests pass their own.
var xr_interface: XRInterface = null
## Whether this is the Quest itself, where frame times count (#643); tests set it.
var on_headset: bool = OS.get_name() == "Android"
## Called once with the exit code; quits the game unless a test replaces it.
var quit_callback: Callable = Callable()
## Reads the hands for the controllers_bound check (#717); tests pass a fake.
var controllers: AcceptanceControllersCheck = AcceptanceControllersCheck.live()
## Saves a step's screenshots (#718); tests pass their own image source.
var screenshots: AcceptanceScreenshots = AcceptanceScreenshots.live()
## One report per suite, in run order, and where each was written.
var reports: Array[AcceptanceReport] = []
var report_paths: Array[String] = []
## Every line this runner printed, so tests can read them.
var messages: PackedStringArray = PackedStringArray()
## Data file text by `res://` path, used in place of the file when a step
## builds its level from a seed (`SeedLevel.load_level`); tests change one.
var seed_overrides: Dictionary = {}
var finished: bool = false
var exit_code: int = -1

var _errors: AcceptanceErrorLog = AcceptanceErrorLog.new()
var _logging: bool = false
var _xr_begun: bool = false
var _suite_index: int = 0
var _step_index: int = 0
var _step_started: bool = false
var _xr_waited: int = 0
var _errors_at_step_start: int = 0
var _source: ReplayInputSource = null
var _level_problem: String = ""  # Why the step's level could not be flown, or "".
## What a frame_budget, comfort_motion or view_not_flat (#737) step samples here, or null.
var _frames: AcceptanceFrameBudgetCheck = null
var _comfort: AcceptanceComfortCheck = null
var _view: AcceptanceViewFlatCheck = null


## The suite asked for, or "" when the switch is off. A command-line argument
## wins over the intent extra; the last `--acceptance=` given counts.
static func requested_suite(user_args: PackedStringArray, intent_value: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	return asked if asked != "" else intent_value.strip_edges()


## The one call `main.gd` makes. Returns the runner it added, or null when the
## switch is off.
static func start_if_requested(scene: Node) -> AcceptanceRunner:
	var runtime: Object = InstallerProbe.android_runtime()
	var intent_value: String = InstallerProbe.intent_extra(runtime, INTENT_EXTRA) if runtime != null else ""
	var suite_name: String = requested_suite(OS.get_cmdline_user_args(), intent_value)
	if suite_name == "":
		return null
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.setup(scene, AcceptanceSuite.load_named(suite_name), XRServer.find_interface("OpenXR"))
	scene.add_child(runner)
	return runner


func setup(scene: Node, p_suites: Array[AcceptanceSuite], p_xr_interface: XRInterface) -> void:
	main = scene
	suites = p_suites
	xr_interface = p_xr_interface
	if not _logging:
		OS.add_logger(_errors)
		_logging = true
	var openxr: OpenXRInterface = xr_interface as OpenXRInterface
	if openxr != null and not openxr.session_begun.is_connected(_on_xr_session_begun):
		openxr.session_begun.connect(_on_xr_session_begun)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_stop_logging()


func _process(delta: float) -> void:
	process_frame(delta)


## One frame of work, which took `frame_seconds` to show; public so tests drive it.
func process_frame(frame_seconds: float = 0.0) -> void:
	if finished:
		return
	if _suite_index == 0 and _step_index == 0 and not _step_started:
		var unreadable: String = AcceptanceSuite.unreadable(suites)
		if unreadable != "":
			_say("%s: %s" % [LOG_PREFIX, unreadable])
			_finish(EXIT_FAIL)
			return
	if _suite_index >= suites.size():
		_finish(EXIT_PASS if AcceptanceReport.all_passed(reports) else EXIT_FAIL)
		return
	var suite: AcceptanceSuite = suites[_suite_index]
	if _step_index >= suite.steps.size():
		_write_report(reports[_suite_index])
		_suite_index += 1
		_step_index = 0
		return
	if reports.size() <= _suite_index:
		reports.append(AcceptanceReport.new(suite.name, _build().commit, "%s (%s)" % [OS.get_model_name(), OS.get_name()]))
	var step: AcceptanceStep = suite.steps[_step_index]
	if not _step_started:
		_start_step(step)
	elif _frames != null:
		_frames.add(frame_seconds)
	if _view != null:
		_view.add(frame_seconds)
	if not _step_ready(step):
		return
	_record_step(step)
	_step_index += 1
	_step_started = false


func _start_step(step: AcceptanceStep) -> void:
	_step_started = true
	_xr_waited = 0
	_source = null
	_level_problem = ""
	_frames = null
	if step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET) \
			and AcceptanceFrameBudgetCheck.measures_here(_xr_available(), on_headset):
		_frames = AcceptanceFrameBudgetCheck.new(step)
	_view = AcceptanceViewFlatCheck.for_step(step, _xr_available(), on_headset, screenshots.grab)
	_errors_at_step_start = _errors.count()
	_say("%s: step %s" % [LOG_PREFIX, step.id])
	screenshots.begin(suites[_suite_index].name, step)
	if step.preset != AcceptanceStep.NO_PRESET:
		main.call("set_comfort_preset", step.preset)
	_comfort = AcceptanceComfortCheck.for_step(step, main)
	if step.replay_path == "":
		return
	# The scene draws the level and drops the tunnel, as `--level=` does; the
	# session it builds is replaced by the replay's below.
	if step.level != "" and not main.call("use_level", LevelSwitch.path_for(step.level)):
		_level_problem = "level %s: the scene could not switch to it" % step.level
		return
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "" or replay.ship_count != 1:
		return  # `replay_problem` reports it when the step is recorded.
	_source = ReplayInputSource.new(replay)
	if step.level_seed == AcceptanceStep.NO_SEED:
		main.set("session", _source.new_session())
	else:
		_level_problem = AcceptanceStepLevel.fly_seed(main, step.level_seed, replay, _source, seed_overrides)
		if _level_problem != "":
			_source = null
			return
	main.set_process(false)  # The runner drives the frames until the replay ends.


## False while the step still needs frames: replay, sampling, or the OpenXR session.
func _step_ready(step: AcceptanceStep) -> bool:
	if _source != null:
		var session: LocalSession = main.get("session")
		screenshots.take(session.sim.tick, _source.tick_count())
		if session.sim.tick < _source.tick_count():
			main.call("advance_frame", ShipState.TICK_DT)
			if _comfort != null:
				_comfort.sample_main(main, ShipState.TICK_DT)
			return false
		main.set_process(true)
	if (_frames != null and not _frames.done()) or (_view != null and not _view.done()):
		return false
	if _waits_for_xr(step) and _xr_waited < XR_WAIT_FRAMES:
		_xr_waited += 1
		return false
	return true


## Whether a check of `step` still waits on the headset's session, controllers or refresh rate.
func _waits_for_xr(step: AcceptanceStep) -> bool:
	if not _xr_available():
		return false
	if step.has_check(AcceptanceStep.CHECK_XR_SESSION) and not _xr_begun:
		return true
	if step.has_check(AcceptanceStep.CHECK_CONTROLLERS_BOUND) and not controllers.settled():
		return true
	var reads_rate: bool = step.has_check(AcceptanceStep.CHECK_REFRESH_RATE) \
		or step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET)
	return reads_rate and not AcceptanceRefreshCheck.settled(main)


func _record_step(step: AcceptanceStep) -> void:
	var outcomes: Array[String] = []
	var notes: PackedStringArray = PackedStringArray()
	var measurements: Dictionary = {}
	var problem: String = _level_problem if _level_problem != "" \
		else AcceptanceStepLevel.replay_problem(step, _source)
	if problem != "":
		outcomes.append(AcceptanceReport.RESULT_FAIL)
		notes.append(problem)
	for check: String in step.checks:
		var outcome: Array = _run_check(check, step, measurements)
		outcomes.append(outcome[0])
		notes.append("%s: %s" % [check, outcome[1]])
	var result: String = AcceptanceReport.combine(outcomes)
	reports[_suite_index].add_step(step.id, result, "; ".join(notes), measurements, screenshots.finish_step())
	_say("%s: step %s %s" % [LOG_PREFIX, step.id, result])


## [result, message] for one check, adding its measurements.
func _run_check(check: String, step: AcceptanceStep, measurements: Dictionary) -> Array:
	if AcceptanceStep.REPLAY_CHECKS.has(check):
		return AcceptanceStateChecks.run(check, step, main.get("session"), _source != null, measurements)
	match check:
		AcceptanceStep.CHECK_COMFORT_MOTION:
			return _comfort.run(measurements) if _comfort != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]
		AcceptanceStep.CHECK_XR_SESSION:
			return AcceptanceXrSessionCheck.run(_xr_available(), _xr_begun, _xr_waited, XR_WAIT_FRAMES,
				step.required, measurements)
		AcceptanceStep.CHECK_NO_SCRIPT_ERRORS:
			return _errors.judge(_errors_at_step_start, measurements)
		AcceptanceStep.CHECK_CONTROLLERS_BOUND:
			return controllers.run(_xr_available(), step.required, measurements)
		AcceptanceStep.CHECK_REFRESH_RATE:
			return AcceptanceRefreshCheck.run(main, _xr_available(), step.required, measurements)
		AcceptanceStep.CHECK_FRAME_BUDGET:
			return AcceptanceFrameBudgetCheck.run(main, _xr_available(), on_headset, step, _frames, measurements)
		AcceptanceStep.CHECK_VIEW_NOT_FLAT:
			return AcceptanceViewFlatCheck.run(_xr_available(), on_headset, step, _view, measurements)
	return [AcceptanceReport.RESULT_FAIL, "unknown check"]


func _xr_available() -> bool:
	return xr_interface != null and xr_interface.is_initialized()


func _on_xr_session_begun() -> void:
	_xr_begun = true


## Writes the report to REPORT_DIR and the log; a failed write is said, the log still has it.
func _write_report(report: AcceptanceReport) -> void:
	var path: String = report.write_file(REPORT_DIR, _build().short_commit())
	if path == "":
		_say("%s: %s" % [LOG_PREFIX, report.write_error])
	else:
		report_paths.append(path)
	for line: String in report.to_log_lines():
		_say(line)


func _finish(code: int) -> void:
	finished = true
	exit_code = code
	_say("%s: exit %d" % [LOG_PREFIX, code])
	_stop_logging()
	if quit_callback.is_valid():
		quit_callback.call(code)
	elif is_inside_tree():
		get_tree().quit(code)


func _stop_logging() -> void:
	if _logging:
		OS.remove_logger(_errors)
		_logging = false


func _build() -> BuildInfo:
	var info: Variant = main.get("build_info") if main != null else null
	return info if info is BuildInfo else BuildInfo.new()


func _say(line: String) -> void:
	messages.append(line)
	print(line)
