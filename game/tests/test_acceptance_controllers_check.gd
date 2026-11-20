extends RefCounted

## The `controllers_bound` acceptance check (#717, #153, PLT-5): passes when
## both hands track and every flight control is bound in the runtime's
## profile, fails naming the hand or the action otherwise, and is skipped
## without an OpenXR runtime. The hands are faked; the bindings come from the
## shipped action map.

const FakeXr := preload("res://tests/fake_initialized_xr.gd")
const TOUCH: String = "/interaction_profiles/oculus/touch_controller"
const SIMPLE: String = "/interaction_profiles/khr/simple_controller"
const FRAME_LIMIT: int = 2000

var _quit_codes: Array[int] = []


static func _check(left_tracked: bool, right_tracked: bool, profile_path: String,
		bindings: Dictionary = {}) -> AcceptanceControllersCheck:
	var tracked: Callable = func(hand: String) -> bool:
		return left_tracked if hand == "left" else right_tracked
	var profile: Callable = func(_hand: String) -> String:
		return profile_path
	var map: Dictionary = bindings if not bindings.is_empty() \
		else AcceptanceControllersCheck.map_bindings(load(AcceptanceControllersCheck.DEFAULT_ACTION_MAP) as OpenXRActionMap)
	return AcceptanceControllersCheck.new(tracked, profile, map)


## The shipped Touch bindings without one "action path" pair.
static func _touch_without(pair: String) -> Dictionary:
	var all: Dictionary = AcceptanceControllersCheck.map_bindings(
		load(AcceptanceControllersCheck.DEFAULT_ACTION_MAP) as OpenXRActionMap)
	var pairs: Array = (all[TOUCH] as Array).duplicate()
	pairs.erase(pair)
	return {TOUCH: pairs}


func test_passes_when_both_hands_track_and_every_control_is_bound() -> String:
	var measurements: Dictionary = {}
	var result: Array = _check(true, true, TOUCH).run(true, false, measurements)
	if result[0] != AcceptanceReport.RESULT_PASS:
		return "Touch with both hands: %s" % [result]
	if not str(result[1]).contains(TOUCH):
		return "the message does not name the profile: %s" % result[1]
	if measurements.get("controllers_profile", {}) != {"left": TOUCH, "right": TOUCH}:
		return "profiles measured %s" % [measurements.get("controllers_profile")]
	if measurements.get("controllers_unbound", null) != []:
		return "unbound measured %s" % [measurements.get("controllers_unbound")]
	return ""


func test_fails_naming_the_hand_that_is_not_tracked() -> String:
	var result: Array = _check(true, false, TOUCH).run(true, false, {})
	if result[0] != AcceptanceReport.RESULT_FAIL:
		return "an untracked right hand gave %s" % [result]
	if not str(result[1]).contains("right controller is not tracked") or str(result[1]).contains("left"):
		return "the message does not name only the right hand: %s" % result[1]
	return ""


func test_fails_naming_the_action_that_is_unbound() -> String:
	var bindings: Dictionary = _touch_without("trigger /user/hand/right/input/trigger/value")
	var measurements: Dictionary = {}
	var result: Array = _check(true, true, TOUCH, bindings).run(true, false, measurements)
	if result[0] != AcceptanceReport.RESULT_FAIL:
		return "a missing right trigger gave %s" % [result]
	if measurements.get("controllers_unbound", []) != ["fire_primary (right_trigger)"]:
		return "unbound measured %s" % [measurements.get("controllers_unbound")]
	if not str(result[1]).contains("fire_primary (right_trigger)") or not str(result[1]).contains(TOUCH):
		return "the message does not name the action and profile: %s" % result[1]
	return ""


## A binding on the other hand does not count: the left trigger is bound,
## yet fire_primary needs the right one.
func test_a_binding_on_the_other_hand_does_not_count() -> String:
	var bindings: Dictionary = _touch_without("trigger /user/hand/right/input/trigger/value")
	if not (bindings[TOUCH] as Array).has("trigger /user/hand/left/input/trigger/value"):
		return "setup: the left trigger is not bound"
	var result: Array = _check(true, true, TOUCH, bindings).judge({})
	return "" if result[0] == AcceptanceReport.RESULT_FAIL else "passed with only the left trigger bound"


## The CI smoke profile binds poses only, so every flight control is unbound there.
func test_a_pose_only_profile_fails() -> String:
	var measurements: Dictionary = {}
	var result: Array = _check(true, true, SIMPLE).judge(measurements)
	if result[0] != AcceptanceReport.RESULT_FAIL:
		return "the simple controller passed: %s" % [result]
	if not (measurements["controllers_unbound"] as Array).has("strafe (left_stick_x)"):
		return "strafe is not named unbound: %s" % [measurements["controllers_unbound"]]
	return ""


func test_skipped_without_a_runtime_and_failed_when_required() -> String:
	var check: AcceptanceControllersCheck = _check(true, true, TOUCH)
	if check.run(false, false, {})[0] != AcceptanceReport.RESULT_SKIPPED:
		return "not skipped without a runtime"
	if check.run(false, true, {})[0] != AcceptanceReport.RESULT_FAIL:
		return "a required step passed without a runtime"
	return ""


func test_the_flight_layout_needs_every_action_on_its_hand() -> String:
	var needed: Array[Array] = AcceptanceControllersCheck.needed(
		ThumbstickMapping.from_file(ThumbstickMapping.DEFAULT_LAYOUT_FILE).layout)
	for expected: Array in [
		["strafe", "left_stick_x", "left", "primary"],
		["fire_primary", "right_trigger", "right", "trigger"],
		["roll", "left_grip", "left", "grip"],
		["lift", "left_button_upper", "left", "by_button"],
		["afterburner", "right_button_lower", "right", "ax_button"],
		["slot_part", "right_stick_click", "right", "primary_click"],
		["show_map", "left_stick_click", "left", "primary_click"],
	]:
		if not needed.has(expected):
			return "missing %s in %s" % [expected, needed]
	for entry: Array in needed:
		if entry[3] == "":
			return "no OpenXR action for %s" % [entry]
	return ""


func test_settled_only_with_both_hands_tracked_and_a_profile() -> String:
	if not _check(true, true, TOUCH).settled():
		return "not settled with both hands on Touch"
	if _check(true, false, TOUCH).settled():
		return "settled with the right hand untracked"
	if _check(true, true, "").settled():
		return "settled before the runtime named a profile"
	return ""


func test_m0_checks_the_controllers_after_the_session() -> String:
	var suite: AcceptanceSuite = AcceptanceSuite.load_named("m0")[0]
	if suite.error != "":
		return suite.error
	if suite.steps.size() != 2 or suite.steps[0].checks != [AcceptanceStep.CHECK_XR_SESSION]:
		return "m0 steps changed: %d" % suite.steps.size()
	if suite.steps[1].checks != [AcceptanceStep.CHECK_CONTROLLERS_BOUND]:
		return "m0's second step checks %s" % [suite.steps[1].checks]
	return ""


func _on_quit(code: int) -> void:
	_quit_codes.append(code)


## Runs a one-step controllers_bound suite on a fake initialized headset whose
## hands the check reads from `check`. Returns [result, note, frames].
func _run_step(check: AcceptanceControllersCheck) -> Array:
	var runner: AcceptanceRunner = AcceptanceRunner.new()
	runner.quit_callback = _on_quit
	runner.controllers = check
	var main: Node = Node.new()
	var suite: AcceptanceSuite = AcceptanceSuite.parse_json(
		"{\"name\": \"t717\", \"steps\": [{\"id\": \"hands\", \"checks\": [\"controllers_bound\"]}]}")
	var suites: Array[AcceptanceSuite] = [suite]
	runner.setup(main, suites, FakeXr.new())
	var frames: int = 0
	while not runner.finished and frames < FRAME_LIMIT:
		runner.process_frame()
		frames += 1
	var out: Array = ["unfinished", "", frames]
	if runner.finished and not runner.reports.is_empty():
		out = [runner.reports[0].steps[0]["result"], runner.reports[0].steps[0]["message"], frames]
	for path: String in runner.report_paths:
		DirAccess.remove_absolute(path)
	main.free()
	runner.free()
	return out


func test_runner_passes_the_step_on_a_headset_with_touch() -> String:
	var out: Array = _run_step(_check(true, true, TOUCH))
	if out[0] != AcceptanceReport.RESULT_PASS:
		return "step %s: %s" % [out[0], out[1]]
	if int(out[2]) > 10:
		return "the runner waited %d frames with both hands settled" % out[2]
	return ""


## Hands that never settle are waited for, then reported, not passed.
func test_runner_waits_for_the_hands_then_fails() -> String:
	var out: Array = _run_step(_check(false, true, TOUCH))
	if out[0] != AcceptanceReport.RESULT_FAIL:
		return "step %s: %s" % [out[0], out[1]]
	if int(out[2]) < AcceptanceRunner.XR_WAIT_FRAMES:
		return "the runner gave up after %d frames" % out[2]
	if not str(out[1]).contains("left controller is not tracked"):
		return "the note does not name the left hand: %s" % out[1]
	return ""
