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
var pause: AcceptancePauseCheck = null  # The step's solo pause (#804), or null.
var hit_motion: AcceptanceHitMotionCheck = null  # The step's hit shake and spin (#849), or null.
var refresh_120: AcceptanceRefresh120 = null  # The choice a 120 Hz step replaced (#851), or null.
var map_route: AcceptanceMapRouteCheck = null  # The held map's escape route (#884), or null.
var escape_cue: AcceptanceEscapeCueCheck = null  # The cockpit's meltdown cue (#885), or null.
var map_markers: AcceptanceMapMarkersCheck = null  # The held map's exit and reactor (#913), or null.
var vignette: AcceptanceVignetteCheck = null  # The comfort vignette shown (#850), or null.
## Script errors logged before the step started, set by the runner once the
## samplers above exist; no_script_errors counts the rest.
var errors_at_start: int = 0
## True once a shaft step's `next_replay` has been started (#1065, `AcceptanceShaftStep.flies_on`).
var next_started: bool = false


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
	pause = AcceptancePauseCheck.for_step(step)
	hit_motion = AcceptanceHitMotionCheck.for_step(step)
	map_route = AcceptanceMapRouteCheck.for_step(step)
	escape_cue = AcceptanceEscapeCueCheck.for_step(step)
	map_markers = AcceptanceMapMarkersCheck.for_step(step)
	vignette = AcceptanceVignetteCheck.for_step(step)
	refresh_120 = AcceptanceRefresh120.apply(main, step)  # After the preset, so its rate is asked again.
	AcceptanceRunStep.begin(main, step)  # A run step's run, or none (#989).


## After the step's checks ran: the scene gets back what the step changed.
func end_step(main: Node) -> void:
	if refresh_120 != null:
		refresh_120.restore(main)
		refresh_120 = null


## One rendered frame. The frame the step starts on is not a frame budget sample.
func add_frame(frame_seconds: float, step_was_running: bool) -> void:
	if step_was_running and frames != null:
		frames.add(frame_seconds)
	if view != null:
		view.add(frame_seconds)
	if flight != null:
		flight.add_frame(frame_seconds)


## Before the frame that flies the replay's `tick`: a preset change or the
## pause, or its end, due then.
func before_tick(main: Node, tick: int) -> void:
	if changes != null:
		changes.apply(main, tick, comfort)
	if pause != null:
		pause.before_frame(main, tick)


## After a replay frame: the view's rotation for comfort_motion, its hit
## motion for hit_view_motion, the map's route for map_route and its markers
## for map_markers, the cockpit cue for escape_cue, the vignette for
## vignette, and what the pause held.
func after_tick(main: Node) -> void:
	if comfort != null:
		comfort.sample_main(main, ShipState.TICK_DT)
	if hit_motion != null:
		hit_motion.sample_main(main)
	if map_route != null:
		map_route.sample_main(main)
	if escape_cue != null:
		escape_cue.sample_main(main)
	if map_markers != null:
		map_markers.sample_main(main)
	if vignette != null:
		vignette.sample_main(main, ShipState.TICK_DT)
	if pause != null:
		pause.after_frame(main)


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
		AcceptanceStep.CHECK_HELD_WHILE_PAUSED: _held_while_paused,
		AcceptanceStep.CHECK_HIT_VIEW_MOTION: _hit_view_motion,
		AcceptanceStep.CHECK_MAP_ROUTE: _map_route,
		AcceptanceStep.CHECK_ESCAPE_CUE: _escape_cue,
		AcceptanceStep.CHECK_MAP_MARKERS: _map_markers,
		AcceptanceStep.CHECK_VIGNETTE: _vignette,
		AcceptanceStep.CHECK_RUN_ADVANCES: _run_advances,
		AcceptanceStep.CHECK_SHAFT_CHOICE: _shaft_choice,
		AcceptanceStep.CHECK_COMPONENTS_BANK: _components_bank,
		AcceptanceStep.CHECK_COLLECTED: _collected,
		AcceptanceStep.CHECK_CREW_JOINS: _crew_joins,
		AcceptanceStep.CHECK_CRAFT_AND_FIT: _craft_and_fit,
		AcceptanceStep.CHECK_SUSPEND_RESUME: _suspend_resume,
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
	return AcceptanceRefreshCheck.run(runner.main, runner.xr_available(), step.required, measurements,
		step.refresh_120)


func _escape_screen(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceEscapeScreenCheck.run(runner.main, runner.flown(), measurements)


func _frame_budget(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceFrameBudgetCheck.run(runner.main, runner.xr_available(), runner.on_headset, step, frames,
		measurements)


func _view_not_flat(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceViewFlatCheck.run(runner.xr_available(), runner.on_headset, step, view, measurements)


func _flight_test_result(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return flight.run(measurements)


func _held_while_paused(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return pause.judge(measurements) if pause != null else [AcceptanceReport.RESULT_FAIL, "no pause flown"]


func _hit_view_motion(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return hit_motion.run(measurements) if hit_motion != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _map_route(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return map_route.run(measurements) if map_route != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _escape_cue(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return escape_cue.run(measurements) if escape_cue != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _map_markers(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return map_markers.run(measurements) if map_markers != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _vignette(_step: AcceptanceStep, _runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return vignette.run(measurements) if vignette != null else [AcceptanceReport.RESULT_FAIL, "not sampled"]


func _run_advances(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceRunStep.run(step, runner.main, runner.flown(), measurements)


func _shaft_choice(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceShaftChoiceCheck.run(step, runner.main, runner.flown(), measurements)


func _components_bank(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceComponentsBankCheck.run(step, runner.main, runner.flown(), measurements)


func _collected(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceCollectedCheck.run(step, runner.main, runner.flown(), measurements)
func _crew_joins(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceCrewJoinsCheck.run(step, runner.main, runner.flown(), measurements)


func _craft_and_fit(_step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceCraftAndFitCheck.run(runner.main, runner.flown(), measurements)


func _suspend_resume(step: AcceptanceStep, runner: AcceptanceRunner, measurements: Dictionary) -> Array:
	return AcceptanceSuspendResumeCheck.run(step, runner.main, runner.flown(), measurements)
