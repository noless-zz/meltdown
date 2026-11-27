class_name AcceptanceRunner
extends Node

## Flies an acceptance suite inside the running game and quits with its result (DEV-6, PLT-1,
## PLT-4, #165). `main.gd` adds one only when the launch switch is set, so a normal start never sees it.
## Each step sets its comfort preset, switches to its level (#334) or builds its seed's level (#460), flies
## its replay through the scene's `advance_frame` (one tick per frame, replay inputs in place of the controllers),
## takes screenshots (#718), runs its checks and records them in an `AcceptanceReport` and the log. Exit 0 if all pass.
## A step past its time limit fails and the next starts (#1444); the exit code also goes to a file.

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

## The game scene (`main.gd`), read through its `session`, `advance_frame` and the like.
var main: Node = null
var suites: Array[AcceptanceSuite] = []
var xr_interface: XRInterface = null  # OpenXR, or null when there is none; tests pass their own.
var on_headset: bool = OS.get_name() == "Android"  # Frame times count only there (#643).
var quit_callback: Callable = Callable()  # Called with the exit code; quits unless a test sets it.
## Reads the hands for the controllers_bound check (#717); tests pass a fake.
var controllers: AcceptanceControllersCheck = AcceptanceControllersCheck.live()
## Saves a step's screenshots (#718); tests pass their own image source.
var screenshots: AcceptanceScreenshots = AcceptanceScreenshots.live()
## One report per suite, in run order, and where each was written.
var reports: Array[AcceptanceReport] = []
var report_paths: Array[String] = []
## Where the exit file was written, or "" (#1444).
var exit_path: String = ""
## Milliseconds of wall time, for the step time limit; tests pass a fake clock.
var clock_msec: Callable = Callable(Time, "get_ticks_msec")
## Every line this runner printed, so tests can read them.
var messages: PackedStringArray = PackedStringArray()
## Data file text by `res://` path, used in place of the file for a seed step; tests change one.
var seed_overrides: Dictionary = {}
var finished: bool = false
var exit_code: int = -1
## Read by `AcceptanceChecks`: the script error log, whether the OpenXR session began and how many
## frames the step has waited for the headset. `AcceptanceShaftStep` swaps the step's replay source
## and sets why its level could not be flown, or "" (#1065).
var replay_source: ReplayInputSource = null
var level_problem: String = ""
var errors: AcceptanceErrorLog = AcceptanceErrorLog.new()
var xr_begun: bool = false
var xr_waited: int = 0

var _logging: bool = false
var _suite_index: int = 0
var _step_index: int = 0
var _step_started: bool = false
var _step_deadline_msec: int = 0  # On `clock_msec`: the step fails when it is reached (#1444).
var _checks: AcceptanceChecks = null  # The step's samplers and check dispatch (#817).


## The suite asked for, or "" when the switch is off. A command-line argument
## wins over the intent extra; the last `--acceptance=` given counts.
static func requested_suite(user_args: PackedStringArray, intent_value: String) -> String:
	var asked: String = ""
	for arg: String in user_args:
		if arg.begins_with(ARG_PREFIX):
			asked = arg.substr(ARG_PREFIX.length()).strip_edges()
	return asked if asked != "" else intent_value.strip_edges()


## The one call `main.gd` makes. Returns the runner it added, or null when the switch is off.
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
		OS.add_logger(errors)
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
	if reports.size() <= _suite_index:  # Before the end test: a suite with no steps still reports (#1297).
		reports.append(AcceptanceReport.new(suite.name, _build().commit, "%s (%s)" % [OS.get_model_name(), OS.get_name()]))
	if _step_index >= suite.steps.size():
		_write_report(reports[_suite_index])
		_suite_index += 1
		_step_index = 0
		return
	var step: AcceptanceStep = suite.steps[_step_index]
	var was_running: bool = _step_started
	if not _step_started:
		_start_step(step)
	_checks.add_frame(frame_seconds, was_running)
	if int(clock_msec.call()) >= _step_deadline_msec:  # Stuck: fail it, go on (#1444).
		var limit: float = AcceptanceTimeLimit.seconds_for(step, suite.default_time_limit_seconds)
		var message: String = AcceptanceStepRecord.time_out(self, step, _checks, reports[_suite_index], limit)
		_say("%s: step %s %s %s (%s)" % [LOG_PREFIX, step.id, AcceptanceReport.RESULT_FAIL, _step_fields(), message])
	elif _step_ready(step):
		_record_step(step)
	else:
		return
	_step_index += 1
	_step_started = false


func _start_step(step: AcceptanceStep) -> void:
	_step_started = true
	_step_deadline_msec = AcceptanceTimeLimit.deadline_msec(step, suites[_suite_index], clock_msec)
	xr_waited = 0
	replay_source = null
	level_problem = ""
	_checks = AcceptanceChecks.begin(step, xr_available(), on_headset, screenshots.grab)
	_checks.errors_at_start = errors.count()
	_say("%s: step %s %s" % [LOG_PREFIX, step.id, _step_fields()])
	screenshots.begin(suites[_suite_index].name, step)
	AcceptanceStepLevel.clear_end_screens(main)  # Before any screenshot or frame of the step (#917).
	if step.preset != AcceptanceStep.NO_PRESET:
		main.call("set_comfort_preset", step.preset)
	level_problem = AcceptanceCustomComfort.apply(main, step)  # #836.
	_checks.begin_scene(step, main)
	if step.replay_path == "" or level_problem != "":
		return
	# The scene draws the level and drops the tunnel, as `--level=` does; the
	# session it builds is replaced by the replay's below.
	if step.level != "" and not main.call("use_level", LevelSwitch.path_for(step.level)):
		level_problem = "level %s: the scene could not switch to it" % step.level
		return
	var replay: Replay = Replay.load_file(step.replay_path)
	if replay.error != "" or (replay.ship_count != 1 and not AcceptanceStepLevel.flies_ships(step)):
		return  # `replay_problem` reports it when the step is recorded.
	replay_source = AcceptanceControlsScript.source_for(step, replay, main)  # Its inputs, or scripted controls (#818).
	if step.level_seed == AcceptanceStep.NO_SEED:
		main.set("session", replay_source.new_session())
	else:
		level_problem = AcceptanceStepLevel.fly_seed(main, step.level_seed, replay, replay_source, seed_overrides)
		if level_problem != "":
			replay_source.finish()
			replay_source = null
			return
	main.set_process(false)  # The runner drives the frames until the replay ends.


## False while the step still needs frames: replay, sampling, or the OpenXR session.
func _step_ready(step: AcceptanceStep) -> bool:
	if replay_source != null:
		var session: LocalSession = main.get("session")
		screenshots.take(session.sim.tick, replay_source.tick_count())
		if session.sim.tick < replay_source.tick_count() or AcceptanceLoopReplay.keeps_flying(step, _checks.frames):
			_checks.before_tick(main, session.sim.tick)
			main.call("advance_frame", ShipState.TICK_DT)
			_checks.after_tick(main)
			return false
		replay_source.finish()
		if AcceptanceShaftStep.flies_on(self, step, _checks):  # Level 2 of a shaft step (#1065).
			return false
		main.set_process(true)
	if _checks.sampling():
		return false
	if _checks.waits_for_xr(step, self) and xr_waited < XR_WAIT_FRAMES:
		xr_waited += 1
		return false
	return true


func _record_step(step: AcceptanceStep) -> void:
	var result: String = AcceptanceStepRecord.record(self, step, _checks, reports[_suite_index])
	_say("%s: step %s %s %s" % [LOG_PREFIX, step.id, result, _step_fields()])


func _step_fields() -> String:
	return AcceptanceRunOutput.step_fields(suites[_suite_index].name, _step_index, suites[_suite_index].steps.size())


func xr_available() -> bool:
	return xr_interface != null and xr_interface.is_initialized()


## Whether the step's replay was loaded and flown; a check that reads its end fails without it.
func flown() -> bool:
	return replay_source != null


func _on_xr_session_begun() -> void:
	xr_begun = true


## Writes the report to REPORT_DIR as soon as its suite ends, and to the log.
func _write_report(report: AcceptanceReport) -> void:
	var path: String = AcceptanceRunOutput.write_report(report, REPORT_DIR, _build().short_commit(), _say)
	if path != "":
		report_paths.append(path)


func _finish(code: int) -> void:
	finished = true
	exit_code = code
	exit_path = AcceptanceRunOutput.write_exit(REPORT_DIR,
		AcceptanceRunOutput.exit_data(_build().commit, reports, code, AcceptanceRunOutput.now_utc()), _say)
	_say("%s: exit %d" % [LOG_PREFIX, code])
	_stop_logging()
	if quit_callback.is_valid():
		quit_callback.call(code)
	elif is_inside_tree():
		get_tree().quit(code)


func _stop_logging() -> void:
	if _logging:
		OS.remove_logger(errors)
		_logging = false


func _build() -> BuildInfo:
	var info: Variant = main.get("build_info") if main != null else null
	return info if info is BuildInfo else BuildInfo.new()


func _say(line: String) -> void:
	messages.append(line)
	print(line)
