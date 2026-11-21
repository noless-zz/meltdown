class_name AcceptanceChecks
extends RefCounted

## The one place that maps a check name to the code that judges it (DEV-6, #817),
## with the samplers a step's checks fill while it runs. `AcceptanceRunner` makes
## one per step, feeds it frames and ticks, and asks it for each check's result,
## so a new check adds a judge here and the runner does not grow.
##
## The checks that read the state a replay ended in (`AcceptanceStep.REPLAY_CHECKS`)
## go to `AcceptanceStateChecks`; every other known check has a judge in `_judges`.
## A unit test pins that the two together cover `AcceptanceStep.KNOWN_CHECKS`.

const UNKNOWN_CHECK: String = "unknown check"

## What a frame_budget, comfort_motion, view_not_flat (#737) or flight_test_result
## step samples here, or null when the step does not list it or it cannot run here.
var frames: AcceptanceFrameBudgetCheck = null
var comfort: AcceptanceComfortCheck = null
var view: AcceptanceViewFlatCheck = null
var flight: AcceptanceFlightTestCheck = null
var changes: AcceptancePresetChanges = null  # The step's mid-flight presets (#777), or null.
## Script errors logged before the step started, set by the runner once the
## samplers above exist; no_script_errors counts the rest.
var errors_at_start: int = 0


## The samplers that start with the step, before its comfort preset is set.
static func begin(step: AcceptanceStep, xr_available: bool, on_headset: bool, grab: Callable) -> AcceptanceChecks:
	var checks: AcceptanceChecks = AcceptanceChecks.new()
	if step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET) \
			and AcceptanceFrameBudgetCheck.measures_here(xr_available, on_headset):
		checks.frames = AcceptanceFrameBudgetCheck.new(step)
	checks.view = AcceptanceViewFlatCheck.for_step(step, xr_available, on_headset, grab)
	return checks


## The samplers that read the scene, once the step's comfort preset is set.
func begin_scene(step: AcceptanceStep, main: Node) -> void:
	comfort = AcceptanceComfortCheck.for_step(step, main)
	flight = AcceptanceFlightTestCheck.for_step(step, main)
	changes = AcceptancePresetChanges.for_step(step)


## One rendered frame. The frame the step starts on is not a frame budget sample.
func add_frame(frame_seconds: float, step_was_running: bool) -> void:
	if step_was_running and frames != null:
		frames.add(frame_seconds)
	if view != null:
		view.add(frame_seconds)
	if flight != null:
		flight.add_frame(frame_seconds)


## Before the replay's `tick` flies: a preset change due then.
func before_tick(main: Node, tick: int) -> void:
	if changes != null:
		changes.apply(main, tick, comfort)


## After a replay tick flew: the view's rotation for comfort_motion.
func after_tick(main: Node) -> void:
	if comfort != null:
		comfort.sample_main(main, ShipState.TICK_DT)


## True while a sampler still needs frames.
func sampling() -> bool:
	return (frames != null and not frames.done()) or (view != null and not view.done()) \
		or (flight != null and not flight.done())


## Whether a check of `step` still waits on the headset's session, controllers or refresh rate.
func waits_for_xr(step: AcceptanceStep, runner: AcceptanceRunner) -> bool:
	if not runner.xr_available():
		return false
	if step.has_check(AcceptanceStep.CHECK_XR_SESSION) and not runner.xr_begun:
		return true
	if step.has_check(AcceptanceStep.CHECK_CONTROLLERS_BOUND) and not runner.controllers.settled():
		return true
	var reads_rate: bool = step.has_check(AcceptanceStep.CHECK_REFRESH_RATE) \
		or step.has_check(AcceptanceStep.CHECK_FRAME_BUDGET)
	return reads_rate and not AcceptanceRefreshCheck.settled(runner.main)


## Every check name `run` can judge: the replay checks and those with a judge here.
func judged_checks() -> Array[String]:
	var names: Array[String] = AcceptanceStep.REPLAY_CHECKS.duplicate()
	for check: String in _judges():
		names.append(check)
	return names


## [result, message] for one check of `step`, adding its measurements.
func run(check: String, step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	if AcceptanceStep.REPLAY_CHECKS.has(check):
		return AcceptanceStateChecks.run(check, step, runner.main.get("session"), runner.flown(), measurements)
	var judge: Callable = _judges().get(check, Callable())
	if not judge.is_valid():
		return [AcceptanceReport.RESULT_FAIL, UNKNOWN_CHECK]
	return judge.call(step, runner, measurements)


func _judges() -> Dictionary[String, Callable]:
	return {
		AcceptanceStep.CHECK_COMFORT_MOTION: _comfort_motion,
		AcceptanceStep.CHECK_XR_SESSION: _xr_session,
		AcceptanceStep.CHECK_NO_SCRIPT_ERRORS: _no_script_errors,
		AcceptanceStep.CHECK_CONTROLLERS_BOUND: _controllers_bound,
		AcceptanceStep.CHECK_REFRESH_RATE: _refresh_rate,
		AcceptanceStep.CHECK_ESCAPE_SCREEN: _escape_screen,
		AcceptanceStep.CHECK_FRAME_BUDGET: _frame_budget,
		AcceptanceStep.CHECK_VIEW_NOT_FLAT: _view_not_flat,
		AcceptanceStep.CHECK_FLIGHT_TEST_RESULT: _flight_test_result,
	}


func _comfort_motion(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return comfort.run(measurements) if comfort != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _xr_session(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceXrSessionCheck.run(runner.xr_available(), runner.xr_begun, runner.xr_waited,
		AcceptanceRunner.XR_WAIT_FRAMES, step.required, measurements)


func _no_script_errors(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return runner.errors.judge(errors_at_start, measurements)


func _controllers_bound(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return runner.controllers.run(runner.xr_available(), step.required, measurements)


func _refresh_rate(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceRefreshCheck.run(runner.main, runner.xr_available(), step.required, measurements)


func _escape_screen(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceEscapeScreenCheck.run(runner.main, runner.flown(), measurements)


func _frame_budget(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceFrameBudgetCheck.run(runner.main, runner.xr_available(), runner.on_headset, step, frames,
		measurements)


func _view_not_flat(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceViewFlatCheck.run(runner.xr_available(), runner.on_headset, step, view, measurements)


func _flight_test_result(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return flight.run(measurements)
