class_name AcceptanceFlightTestCheck
extends RefCounted

## The `flight_test_result` acceptance check (#762, CMF-4, CMF-1, DEV-6, gate
## G1): the real first-launch flight test (`FlightTestWiring`, the shipped
## plan and answer buttons) runs from answers the suite names, and must end on
## the preset the suite expects. Kept out of `AcceptanceRunner` so that file
## stays short.
##
## The scene's own wiring is swapped for one begun as a first launch in the
## test tunnel, so the scene times the segments (paused time does not count),
## holds the ship while an answer is due and applies the presets exactly as it
## does for a pilot. Each answer is pressed through `read_buttons` with the
## button `answers.json` names for it, on the frame after its question is due.
## The pilot's saved choice is never read or written: the wiring keeps its
## choice in STORE_PATH, which is removed before and after the step.

const STEP_KEYS: Array[String] = ["flight_test_answers", "expected_preset"]
## The throw-away store; never `ComfortChoice.DEFAULT_PATH`.
const STORE_PATH: String = "user://acceptance/flight_test_choice.json"
## The ship may drift this far while held, metres; more means it was flown.
const MAX_HELD_TRAVEL_M: float = 0.01
## Added to the plan's length before the step gives up waiting for the end.
const TIMEOUT_MARGIN_S: float = 30.0

var wiring: FlightTestWiring = FlightTestWiring.new()
var answers: Array[String] = []
var expected_preset: int = AcceptanceStep.NO_PRESET
## Seconds from the step's start at which each answer was pressed.
var answer_times: Array[float] = []
## Metres the ship moved while an answer was due.
var held_travel_m: float = 0.0
var applied_preset: int = AcceptanceStep.NO_PRESET
var timed_out: bool = false

var _main: Node = null
var _scene_wiring: FlightTestWiring = null
var _preset_before: int = AcceptanceStep.NO_PRESET
var _elapsed_s: float = 0.0
var _limit_s: float = 0.0
var _held_from: Vector3 = Vector3.ZERO
var _was_held: bool = false
var _ended: bool = false
var _seen_finished: bool = false
var _settled: bool = false


## A check for `step` begun in `main`, or null when the step does not list it.
static func for_step(step: AcceptanceStep, main: Node) -> AcceptanceFlightTestCheck:
	if not step.has_check(AcceptanceStep.CHECK_FLIGHT_TEST_RESULT):
		return null
	var check: AcceptanceFlightTestCheck = AcceptanceFlightTestCheck.new()
	check.answers = step.flight_test_answers.duplicate()
	check.expected_preset = step.expected_preset
	check.begin(main)
	return check


## Swaps `main`'s wiring for the check's and starts the test.
func begin(main: Node) -> void:
	_main = main
	_scene_wiring = main.get("flight_test")
	var comfort: ComfortWiring = main.get("comfort")
	_preset_before = comfort.number
	_remove_store()
	DirAccess.make_dir_recursive_absolute(STORE_PATH.get_base_dir())
	wiring.choice_path = STORE_PATH
	var plan: FlightTestPlan = FlightTestPlan.load_file(wiring.plan_path)
	for segment: FlightTestSegment in plan.segments:
		_limit_s += segment.duration_s
	_limit_s += TIMEOUT_MARGIN_S
	main.set("flight_test", wiring)
	wiring.begin(FlightTestWiring.Start.TUNNEL, comfort, Callable(main, "set_comfort_preset"),
		main.get_node_or_null("XRRig") as Node3D)


## Once per frame after the scene's: measures the hold and presses a due
## answer. The applied preset is read a frame after the last answer, once the
## scene's `update` has applied the recommendation.
func add_frame(frame_seconds: float) -> void:
	if done():
		return
	_elapsed_s += maxf(frame_seconds, 0.0)
	if wiring.test != null and not wiring.running():
		if _seen_finished:
			applied_preset = (_main.get("comfort") as ComfortWiring).number
			_settled = true
		_seen_finished = true
		return
	var position: Vector3 = _ship_position()
	var held: bool = wiring.running() and wiring.test.awaiting_answer()
	if held and _was_held:
		held_travel_m += _held_from.distance_to(position)
	_held_from = position
	_was_held = held
	if held:
		_press(wiring.test.segment_index())
	if _elapsed_s > _limit_s:
		timed_out = true


## Whether the test is over (or gave up), so the step may be judged.
func done() -> bool:
	return timed_out or _settled


## [result, message] for the check, adding its measurements. Puts the scene's
## own wiring and preset back.
func run(measurements: Dictionary) -> Array:
	_end()
	var test: FlightTestSession = wiring.test
	measurements["answers_given"] = test.answers() if test != null else []
	measurements["answer_seconds"] = answer_times.duplicate()
	measurements["applied_preset"] = applied_preset
	measurements["ship_travel_while_held_m"] = held_travel_m
	if test == null:
		return [AcceptanceReport.RESULT_FAIL, "the flight test did not start"]
	if timed_out:
		return [AcceptanceReport.RESULT_FAIL, "the flight test did not finish within %.0f s" % _limit_s]
	if test.skipped():
		return [AcceptanceReport.RESULT_FAIL, "the flight test was skipped"]
	if applied_preset != expected_preset:
		return [AcceptanceReport.RESULT_FAIL, "applied preset %d, expected preset %d"
			% [applied_preset, expected_preset]]
	if held_travel_m > MAX_HELD_TRAVEL_M:
		return [AcceptanceReport.RESULT_FAIL, "the ship moved %.3f m while an answer was due" % held_travel_m]
	return [AcceptanceReport.RESULT_PASS, "preset %d after %d answers" % [applied_preset, test.answers().size()]]


## Reads the flight test keys of one suite step. Returns the problem, or "".
static func parse_step(data: Dictionary, field: String, step: AcceptanceStep) -> String:
	var wanted: bool = step.has_check(AcceptanceStep.CHECK_FLIGHT_TEST_RESULT)
	for key: String in STEP_KEYS:
		if data.has(key) and not wanted:
			return "%s.%s: only used by the flight_test_result check, which the step does not list" % [field, key]
		if not data.has(key) and wanted:
			return "%s.%s: needed by the flight_test_result check" % [field, key]
	if not wanted:
		return ""
	if step.replay_path != "":
		return "%s.replay: the flight_test_result check flies no replay" % field
	var raw: Variant = data["flight_test_answers"]
	var segments: int = FlightTestPlan.load_file(FlightTestPlan.DEFAULT_FILE).segments.size()
	if typeof(raw) != TYPE_ARRAY or (raw as Array).size() != segments:
		return "%s.flight_test_answers: must list one answer for each of the plan's %d segments" % [field, segments]
	for index: int in (raw as Array).size():
		var answer: Variant = raw[index]
		if typeof(answer) != TYPE_STRING or not PresetRecommender.ANSWERS.has(answer):
			return "%s.flight_test_answers[%d]: must be one of %s" % [field, index,
				", ".join(PackedStringArray(PresetRecommender.ANSWERS))]
		step.flight_test_answers.append(answer)
	var preset: Variant = data["expected_preset"]
	if typeof(preset) not in [TYPE_INT, TYPE_FLOAT] or float(preset) != floorf(float(preset)) \
			or int(preset) < AcceptanceStep.MIN_PRESET or int(preset) > AcceptanceStep.MAX_PRESET:
		return "%s.expected_preset: must be a whole number from %d to %d" % [field,
			AcceptanceStep.MIN_PRESET, AcceptanceStep.MAX_PRESET]
	step.expected_preset = int(preset)
	return ""


## Presses the answer for segment `index` on one frame; `read_buttons` takes
## it only while the question is due, and the scene's next frame lets it go.
func _press(index: int) -> void:
	if index >= answers.size():
		return
	var button: String = wiring.answers.buttons[answers[index]]
	wiring.read_buttons({button: true}, false)
	if wiring.test.segment_index() != index:
		answer_times.append(_elapsed_s)


func _end() -> void:
	if _ended or _main == null:
		return
	_ended = true
	if wiring.panel != null:
		if wiring.panel.is_inside_tree():
			wiring.panel.queue_free()
		else:
			wiring.panel.free()
		wiring.panel = null
	_main.set("flight_test", _scene_wiring)
	if (_main.get("comfort") as ComfortWiring).number != _preset_before:
		_main.call("set_comfort_preset", _preset_before)
	_remove_store()


func _ship_position() -> Vector3:
	var session: LocalSession = _main.get("session")
	return session.current_ship().position if session != null else Vector3.ZERO


static func _remove_store() -> void:
	if FileAccess.file_exists(STORE_PATH):
		DirAccess.remove_absolute(STORE_PATH)
