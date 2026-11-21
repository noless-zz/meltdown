extends RefCounted

## The control-label toggle in the main scene (#181, PLT-5, CMF-4, ARC-3): the
## stick click of the hand that does not turn flips `XRRig.show_labels`, and
## the press never reaches the ship. Since #914 a short click of that button
## toggles the map, so the labels flip on a hold of `MapHologram.HOLD_SECONDS`,
## once, on the frame the hold reaches it.

const FRAME: float = 1.0 / 90.0


## A clock the test moves by hand.
class StepClock:
	extends RefCounted
	var now: float = 0.0

	func read() -> float:
		return now


## The main scene with its label clock replaced by `clock`, so a hold is timed
## without waiting.
func _main(clock: StepClock) -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return null
	var main: Node = scene.instantiate()
	(main.get("comfort") as ComfortWiring).clock = clock.read
	return main


## Holds `button` past the threshold over two frames and releases it.
static func _hold(main: Node, clock: StepClock, button: String) -> void:
	main.call("apply_controls", _values({button: true}))
	clock.now += MapHologram.HOLD_SECONDS + 0.05
	main.call("apply_controls", _values({button: true}))
	main.call("apply_controls", _values())


static func _values(buttons: Dictionary = {}, right_stick: Vector2 = Vector2.ZERO) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	values["buttons"] = buttons
	return values


static func _labels_shown(main: Node) -> bool:
	return bool(main.get_node("XRRig").get("show_labels"))


func test_labels_start_shown() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	var shown: bool = _labels_shown(main)
	main.free()
	if not shown:
		return "labels start hidden"
	return ""


func test_a_hold_flips_once_when_it_reaches_the_threshold() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	var seen: Array[bool] = []
	for press: int in 2:
		for i: int in 5:
			main.call("apply_controls", _values({"left_stick_click": true}))
			seen.append(_labels_shown(main))
			clock.now += 0.15
		main.call("apply_controls", _values())
		seen.append(_labels_shown(main))
	main.free()
	# Frames at 0, 0.15, 0.30, 0.45 (flips), 0.60; release changes nothing.
	var expected: Array[bool] = [true, true, true, false, false, false,
		false, false, false, true, true, true]
	if seen != expected:
		return "two held presses gave %s, expected %s" % [str(seen), str(expected)]
	return ""


func test_a_click_leaves_the_labels() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	main.call("apply_controls", _values({"left_stick_click": true}))
	clock.now += MapHologram.HOLD_SECONDS * 0.5
	main.call("apply_controls", _values())
	var shown: bool = _labels_shown(main)
	main.free()
	if not shown:
		return "a short click hid the labels; it toggles the map since #914"
	return ""


func test_the_right_stick_click_does_nothing_right_handed() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	_hold(main, clock, "right_stick_click")
	var shown: bool = _labels_shown(main)
	main.free()
	if not shown:
		return "the right stick hold hid the labels in right-handed mode"
	return ""


func test_left_handed_uses_the_right_stick_click() -> String:
	var clock: StepClock = StepClock.new()
	var main: Node = _main(clock)
	(main.get("mapping") as ThumbstickMapping).left_handed = true
	_hold(main, clock, "left_stick_click")
	var after_left: bool = _labels_shown(main)
	_hold(main, clock, "right_stick_click")
	var after_right: bool = _labels_shown(main)
	main.free()
	if not after_left:
		return "left-handed: the left stick hold hid the labels"
	if after_right:
		return "left-handed: the right stick hold did not hide the labels"
	return ""


func test_the_button_follows_the_hand() -> String:
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var right_handed: String = wiring.label_button()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.left_handed = true
	var left_handed: String = ComfortWiring.new(LatestInputSource.new(), mapping).label_button()
	if right_handed != "left_stick_click" or left_handed != "right_stick_click":
		return "label buttons were %s and %s" % [right_handed, left_handed]
	return ""


## ARC-3: the same frames with and without the presses leave identical ships.
func test_the_click_never_reaches_the_ship() -> String:
	var clock: StepClock = StepClock.new()
	var with_click: Node = _main(clock)
	var still: StepClock = StepClock.new()
	var without: Node = _main(still)
	# Five holds of three frames 0.25 s apart, the last released on frame 31.
	for i: int in 32:
		var stick: Vector2 = Vector2(0.6, -0.4)
		var click: bool = i % 7 < 3
		clock.now += 0.25
		with_click.call("apply_controls", _values({"left_stick_click": click}, stick))
		with_click.call("advance_frame", FRAME)
		without.call("apply_controls", _values({}, stick))
		without.call("advance_frame", FRAME)
	var session_a: LocalSession = with_click.get("session")
	var session_b: LocalSession = without.get("session")
	var input_a: ShipInput = (with_click.get("input_source") as LatestInputSource).latest_input()
	var input_b: ShipInput = (without.get("input_source") as LatestInputSource).latest_input()
	var shown: bool = _labels_shown(with_click)
	var same_sim: bool = session_a.sim.state_hash() == session_b.sim.state_hash()
	var same_ship: bool = session_a.current_ship().state_hash() == session_b.current_ship().state_hash()
	var same_input: bool = var_to_str(inst_to_dict(input_a)) == var_to_str(inst_to_dict(input_b))
	var ticks: int = session_a.sim.tick
	with_click.free()
	without.free()
	if ticks == 0:
		return "no tick ran"
	if shown:
		return "five presses left the labels shown"
	if not same_input:
		return "the click changed the ship input"
	if not same_sim or not same_ship:
		return "the click changed the simulation"
	return ""


func test_a_click_for_the_map_never_flips_the_labels() -> String:
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var clock: StepClock = StepClock.new()
	wiring.clock = clock.read
	var flips: Array[bool] = []
	# A short click (the map's) does not flip.
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	clock.now += MapHologram.HOLD_SECONDS * 0.5
	flips.append(wiring.read_label_button({}))
	# A hold straight after flips once, when it reaches the threshold.
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	clock.now += MapHologram.HOLD_SECONDS + 0.05
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	clock.now += 1.0
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	flips.append(wiring.read_label_button({}))
	if flips != [false, false, false, true, false, false]:
		return "a short click then a long hold gave %s" % str(flips)
	return ""


func test_with_the_map_elsewhere_a_press_flips_at_once() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	mapping.layout["show_map"] = {"left_button_upper": 1.0}
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), mapping)
	var flips: Array[bool] = []
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	flips.append(wiring.read_label_button({}))
	if flips != [true, false, false]:
		return "with show_map on Y the label click gave %s" % str(flips)
	return ""
