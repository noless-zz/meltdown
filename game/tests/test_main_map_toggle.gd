extends RefCounted

## The map toggle in the main scene (#914, MAP-1, PLT-5, CMF-8, ARC-3): a click
## of `show_map` opens the map and it stays open with the button released, the
## next click closes it, a hold flips the labels and leaves the map as it was,
## the stick's deflection reaches `ShipInput` the same with the map open, and a
## restart, a level switch and a destroyed ship close it. The shipped layouts
## and the gripped scheme all behave so.

const FRAME: float = 1.0 / 90.0
const NONE: PackedStringArray = []


## A clock the test moves by hand, for the label button's `ClickHold`.
class StepClock:
	extends RefCounted
	var now: float = 100.0

	func read() -> float:
		return now


## The main scene with its rig built and `_ready` run, its label clock `clock`,
## flying `layout_file` under `scheme` ("" for the thumbsticks).
func _main(clock: StepClock, layout_file: String = ThumbstickMapping.DEFAULT_LAYOUT_FILE,
		scheme: String = "") -> Node:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	main.get_node("XRRig").call("build")
	(main.get("mapping") as ThumbstickMapping).layout = ThumbstickMapping.from_file(layout_file).layout
	main.set("scheme", ControlSchemeSwitch.parse(NONE, scheme))
	main.call("_ready")
	(main.get("comfort") as ComfortWiring).clock = clock.read
	return main


## Controller values with `buttons` and the left stick at `left_stick`; under the
## gripped scheme both hands report a pose, as a headset does.
static func _values(buttons: Dictionary, left_stick: Vector2 = Vector2.ZERO,
		gripped: bool = false) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["left_stick"] = left_stick
	values["buttons"] = buttons
	if gripped:
		values[ControllerSampler.POSES] = {"left": Transform3D.IDENTITY, "right": Transform3D.IDENTITY}
	return values


## One frame of `pressed` on the left stick click, `seconds` after the last.
static func _frame(main: Node, clock: StepClock, pressed: bool, seconds: float = FRAME,
		left_stick: Vector2 = Vector2.ZERO, gripped: bool = false) -> void:
	clock.now += seconds
	main.call("apply_controls", _values({"left_stick_click": pressed} if pressed else {}, left_stick, gripped))
	main.call("advance_frame", FRAME)


static func _open(main: Node) -> bool:
	return (main.get("map") as MapWiring).hologram.visible


static func _labels(main: Node) -> bool:
	return bool(main.get_node("XRRig").get("show_labels"))


## A click, a hold and a second click under one layout and scheme: what the map
## and labels were after each; "" when all as #914 asks.
func _click_hold_click(layout_file: String, scheme: String) -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock, layout_file, scheme)
	var gripped: bool = scheme != ""
	var labels_before: bool = _labels(main)
	var seen: Array[String] = []
	_frame(main, clock, true, FRAME, Vector2.ZERO, gripped)
	_frame(main, clock, true, 0.1, Vector2.ZERO, gripped)
	_frame(main, clock, false, 0.1, Vector2.ZERO, gripped)
	for i: int in 30:  # Released for a third of a second: it stays open.
		_frame(main, clock, false, FRAME, Vector2.ZERO, gripped)
	seen.append("click: map %s, labels %s" % [_open(main), _labels(main) != labels_before])
	_frame(main, clock, true, FRAME, Vector2.ZERO, gripped)
	_frame(main, clock, true, 0.5, Vector2.ZERO, gripped)
	_frame(main, clock, true, 0.5, Vector2.ZERO, gripped)
	_frame(main, clock, false, 0.1, Vector2.ZERO, gripped)
	seen.append("hold: map %s, labels %s" % [_open(main), _labels(main) != labels_before])
	_frame(main, clock, true, 0.1, Vector2.ZERO, gripped)
	_frame(main, clock, false, 0.1, Vector2.ZERO, gripped)
	seen.append("click: map %s, labels %s" % [_open(main), _labels(main) != labels_before])
	main.free()
	var want: Array[String] = [
		"click: map true, labels false", "hold: map true, labels true", "click: map false, labels true",
	]
	if seen != want:
		return "%s %s: got %s, want %s" % [layout_file.get_file(), scheme, seen, want]
	return ""


func test_a_click_toggles_the_map_and_a_hold_the_labels_in_every_layout() -> String:
	for case: Array in [
		[ThumbstickMapping.DEFAULT_LAYOUT_FILE, ""],
		[ThumbstickMapping.PAIRED_LAYOUT_FILE, ""],
		[ThumbstickMapping.DEFAULT_LAYOUT_FILE, "gripped"],
	]:
		var problem: String = _click_hold_click(str(case[0]), str(case[1]))
		if problem != "":
			return problem
	return ""


func test_the_stick_reaches_the_ship_the_same_with_the_map_open() -> String:
	var clock_open: StepClock = StepClock.new()
	var clock_closed: StepClock = StepClock.new()
	var opened: Node = _main(clock_open)
	var closed: Node = _main(clock_closed)
	_frame(opened, clock_open, true)
	_frame(opened, clock_open, false, 0.1)
	_frame(closed, clock_closed, false)
	_frame(closed, clock_closed, false, 0.1)
	var inputs: Array[String] = []
	for main: Node in [opened, closed]:
		var clock: StepClock = clock_open if main == opened else clock_closed
		_frame(main, clock, false, FRAME, Vector2(0.7, -0.5))
		var input: ShipInput = (main.get("input_source") as LatestInputSource).latest_input()
		inputs.append(var_to_str(inst_to_dict(input)))
	var was_open: bool = _open(opened)
	var was_closed: bool = not _open(closed)
	opened.free()
	closed.free()
	if not was_open or not was_closed:
		return "the map was not open in one scene and closed in the other"
	if inputs[0] != inputs[1]:
		return "the stick gave %s with the map open, %s closed" % [inputs[0], inputs[1]]
	if inputs[1] == var_to_str(inst_to_dict(ShipInput.new())):
		return "the deflected stick reached the ship as no input at all"
	return ""


## Opens the map in `main` with a click; true if it opened.
static func _click_open(main: Node, clock: StepClock) -> bool:
	_frame(main, clock, true)
	_frame(main, clock, false, 0.1)
	return _open(main)


func test_a_restart_closes_the_map() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	var opened: bool = _click_open(main, clock)
	main.call("restart_level")
	_frame(main, clock, false)
	var after: bool = _open(main)
	main.free()
	if not opened:
		return "the click did not open the map"
	if after:
		return "the map was still open after a restart"
	return ""


func test_a_level_switch_closes_the_map() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	var opened: bool = _click_open(main, clock)
	var switched: bool = main.call("use_level", LevelSwitch.path_for("g2"))
	_frame(main, clock, false)
	var after: bool = _open(main)
	main.free()
	if not opened or not switched:
		return "the map did not open (%s) or the level did not switch (%s)" % [opened, switched]
	if after:
		return "the map was still open in the new level"
	return ""


func test_a_destroyed_ship_closes_the_map_and_keeps_it_closed() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	var opened: bool = _click_open(main, clock)
	(main.get("session") as LocalSession).sim.ships[0].hull = 0.0
	for i: int in 3:
		_frame(main, clock, false)
	var after: bool = _open(main)
	_click_open(main, clock)  # A click on the end screen does not open it.
	var clicked: bool = _open(main)
	main.free()
	if not opened:
		return "the click did not open the map"
	if after or clicked:
		return "the map was open with the ship destroyed (after %s, clicked %s)" % [after, clicked]
	return ""
