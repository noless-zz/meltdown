class_name FlightTestWiring
extends RefCounted

## Runs the first-launch flight test in the test tunnel and keeps the preset
## it recommends (CMF-4, #715): `FlightTestSession` times the segments and
## picks the preset, `FlightTestPanel` shows it, `ComfortChoice` remembers the
## result and every later preset switch, so the choice survives a restart.
##
## It sits beside `main.gd`, like the other wirings, because it reads the
## session's pause and hands the comfort layer its input; it never writes
## `ShipState` or `Sim` (ARC-3, MP-2). Presets change only through the
## caller's `set_comfort_preset`, the same path as an X press, so nothing but
## the ship moves the view (CMF-6, CMF-8).

## How the run was started, which decides whether the test may run.
enum Start {
	## An acceptance run, `--comfort-preset=` or the custom-mode launch switch
	## (#806): no test, the saved choice is neither read nor written, so a run
	## never depends on the headset's history.
	OFF,
	## A level or seed start: the saved preset, never the test.
	SAVED,
	## The test tunnel: the test on first launch, otherwise the saved preset.
	TUNNEL,
}

## How long the recommended preset's name stays on the panel.
const RESULT_SECONDS: float = 5.0

## Where the choice is read and saved; tests point it at a scratch file.
var choice_path: String = ComfortChoice.DEFAULT_PATH
var plan_path: String = FlightTestPlan.DEFAULT_FILE
var answers_path: String = FlightTestAnswers.DEFAULT_FILE
var start: Start = Start.OFF
var choice: ComfortChoice = ComfortChoice.new()
var answers: FlightTestAnswers = null
## The running or just finished test; null when none ran this start.
var test: FlightTestSession = null
## Under the rig origin while a test runs or its result shows, null otherwise.
var panel: FlightTestPanel = null

var _comfort: ComfortWiring = null
var _apply_preset: Callable
## The preset last saved or applied from the choice, so an X press shows as a change.
var _known_preset: int = 0
var _buttons_before: Dictionary = {}
var _menu_held: bool = false
var _menu_held_s: float = 0.0
## True from an answer until its button is let go, so A or B, which also fly
## the afterburner and lift, do not fly on the frame that answers.
var _hold_until_release: bool = false
var _finish_handled: bool = false
var _result_left_s: float = 0.0


## How a run with user arguments `args`, acceptance suite `suite` and level
## source `level_source` ("" for the tunnel) was started; `launched_custom` when
## `ComfortSwitch` started it in the custom comfort mode.
static func start_for(args: PackedStringArray, suite: String, level_source: String,
		launched_custom: bool = false) -> Start:
	if suite != "" or launched_custom:
		return Start.OFF
	for arg: String in args:
		if arg.begins_with(ComfortPresetFiles.ARG):
			return Start.OFF
	return Start.SAVED if level_source != "" else Start.TUNNEL


## Called by `main.gd` once its rig and panels exist. A host outside the scene
## tree is a unit test calling `_ready` by hand, not a start of the game: it
## keeps the start preset, so those tests never find the test running.
func attach(host: Node, comfort: ComfortWiring, level_source: String, rig: Node3D) -> void:
	if not host.is_inside_tree():
		return
	var runtime: Object = InstallerProbe.android_runtime()
	var intent: String = InstallerProbe.intent_extra(runtime, AcceptanceRunner.INTENT_EXTRA) if runtime != null else ""
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	var suite: String = AcceptanceRunner.requested_suite(user_args, intent)
	# Only the launch switch can have chosen the custom mode before this runs.
	var launched_custom: bool = comfort.number == ComfortPresetFiles.CUSTOM_NUMBER
	begin(start_for(OS.get_cmdline_args() + user_args, suite, level_source, launched_custom), comfort,
		Callable(host, "set_comfort_preset"), rig)


## Starts as `p_start` says. `apply_preset(number)` makes a preset active; the
## panel goes under `rig` when a test runs and a rig is given.
func begin(p_start: Start, comfort: ComfortWiring, apply_preset: Callable, rig: Node3D = null) -> void:
	start = p_start
	_comfort = comfort
	_apply_preset = apply_preset
	if start == Start.OFF:
		return
	choice.load_from(choice_path)
	if start == Start.TUNNEL and choice.first_launch():
		_begin_test(rig)
		return
	var number: int = choice.preset()
	if number == ComfortPresetFiles.CUSTOM_NUMBER and not comfort.custom_available():
		number = choice.custom_base()  # The custom file is gone or now rejected (#806).
	_apply(number)
	_known_preset = number


## True while the test is being flown or answered.
func running() -> bool:
	return test != null and not test.finished()


## Reads this frame's `buttons` and whether the menu button (or Backspace) is
## down. Takes an answer on the frame its button goes down while one is due.
## Returns the buttons the rest of the frame should read: during the test
## without the preset button, since the test chooses the preset then.
func read_buttons(buttons: Dictionary, menu_held: bool) -> Dictionary:
	var before: Dictionary = _buttons_before
	_buttons_before = buttons.duplicate()
	_menu_held = menu_held
	if not running():
		_hold_until_release = false
		return buttons
	if test.awaiting_answer():
		var given: String = answers.pressed_answer(buttons, before)
		if given != "" and test.answer(given) == "":
			_hold_until_release = true
	if _hold_until_release and not answers.any_held(buttons):
		_hold_until_release = false
	var rest: Dictionary = buttons.duplicate()
	rest.erase(_comfort.preset_button())
	return rest


## True while the menu hold skips the test rather than resetting the ship.
func takes_menu_hold() -> bool:
	return running()


## `input` as this frame should fly it: still (no thrust, turn or afterburner)
## while an answer is due or the answering button is still down.
func held(input: ShipInput) -> ShipInput:
	if not running() or not (test.awaiting_answer() or _hold_until_release):
		return input
	var still: ShipInput = ComfortInputFilter.copy_input(input)
	still.thrust_q = Vector3i.ZERO
	still.turn_q = Vector3i.ZERO
	still.afterburner = false
	return still


## Once per frame, after the ticks: times the test (not while `paused`) and
## the skip hold, applies the segment's or the recommended preset, saves a
## preset switch, and shows the panel above the status panel.
func update(delta_seconds: float, paused: bool) -> void:
	if start == Start.OFF:
		return
	if running():
		_menu_held_s = _menu_held_s + delta_seconds if _menu_held else 0.0
		if _menu_held_s >= ResetHold.RESET_HOLD_SECONDS:
			test.skip()
		else:
			test.advance(0.0 if paused else delta_seconds)
	if running():
		if test.preset_now() != _comfort.number:
			_apply(test.preset_now())
	elif test != null and not _finish_handled:
		_finish()
	elif _comfort.number != _known_preset:
		_save(_comfort.number)
	_show(delta_seconds)


func _begin_test(rig: Node3D) -> void:
	answers = FlightTestAnswers.load_file(answers_path)
	test = FlightTestSession.new(FlightTestPlan.load_file(plan_path))
	if test.finished():
		# A rejected plan cannot be flown; the next start tries again.
		push_warning("Meltdown: flight test not run, its plan was rejected")
		test = null
		_apply(FlightTestSession.SKIP_PRESET)
		_known_preset = choice.preset()
		return
	print("Meltdown: flight test started")
	_apply(test.preset_now())
	panel = FlightTestPanel.new()
	if rig != null:
		rig.add_child(panel)


func _finish() -> void:
	_finish_handled = true
	var number: int = test.recommended()
	_apply(number)
	choice.finish_test(number)
	choice.save_to(choice_path)
	_known_preset = number
	_result_left_s = RESULT_SECONDS
	print("Meltdown: flight test %s, preset %d" % ["skipped" if test.skipped() else "done", number])


## A preset switch after the test (CMF-4 "changeable any time"); the custom
## mode is saved with its file's base preset (#806).
func _save(number: int) -> void:
	var taken: bool = choice.set_custom(_comfort.custom().base) \
		if number == ComfortPresetFiles.CUSTOM_NUMBER else choice.set_preset(number)
	if taken:
		choice.save_to(choice_path)
	_known_preset = number


func _apply(number: int) -> void:
	if _comfort.number != number:
		_apply_preset.call(number)


## The panel sits where the status panel does, at the cockpit frame's head
## point, so it moves only with a recentre (CMF-8).
func _show(delta_seconds: float) -> void:
	if panel == null:
		return
	if _finish_handled:
		_result_left_s -= delta_seconds
		if _result_left_s <= 0.0:
			if panel.is_inside_tree():
				panel.queue_free()
			else:
				panel.free()
			panel = null
			return
	var frame: CockpitFrame = _comfort.cockpit_frame
	panel.transform = panel.rig_transform(frame.transform if frame != null else Transform3D.IDENTITY)
	panel.show_session(test)
