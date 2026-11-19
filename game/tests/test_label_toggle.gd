extends RefCounted

## The control-label toggle in the main scene (#181, PLT-5, CMF-4, ARC-3): the
## stick click of the hand that does not turn flips `XRRig.show_labels` once
## per click, and the click never reaches the ship. The same click held for
## `MapHologram.HOLD_SECONDS` shows the map instead (#314), so a click flips
## the labels on release, and only when it was shorter than that.

const FRAME: float = 1.0 / 90.0


## The main scene with its label clock stopped, so every click counts as short
## however slow the test machine is.
func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	if scene == null:
		return null
	var main: Node = scene.instantiate()
	(main.get("comfort") as ComfortWiring).clock = func() -> float: return 0.0
	return main


static func _values(buttons: Dictionary = {}, right_stick: Vector2 = Vector2.ZERO) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["right_stick"] = right_stick
	values["buttons"] = buttons
	return values


static func _labels_shown(main: Node) -> bool:
	return bool(main.get_node("XRRig").get("show_labels"))


func test_labels_start_shown() -> String:
	var main: Node = _main()
	var shown: bool = _labels_shown(main)
	main.free()
	if not shown:
		return "labels start hidden"
	return ""


func test_a_click_flips_once_on_release() -> String:
	var main: Node = _main()
	var seen: Array[bool] = []
	for press: int in 2:
		for i: int in 5:
			main.call("apply_controls", _values({"left_stick_click": true}))
			seen.append(_labels_shown(main))
		main.call("apply_controls", _values())
		seen.append(_labels_shown(main))
	main.free()
	var expected: Array[bool] = [true, true, true, true, true, false,
		false, false, false, false, false, true]
	if seen != expected:
		return "two held presses gave %s, expected %s" % [str(seen), str(expected)]
	return ""


func test_the_right_stick_click_does_nothing_right_handed() -> String:
	var main: Node = _main()
	main.call("apply_controls", _values({"right_stick_click": true}))
	var shown: bool = _labels_shown(main)
	main.free()
	if not shown:
		return "the right stick click hid the labels in right-handed mode"
	return ""


func test_left_handed_uses_the_right_stick_click() -> String:
	var main: Node = _main()
	(main.get("mapping") as ThumbstickMapping).left_handed = true
	main.call("apply_controls", _values({"left_stick_click": true}))
	var after_left: bool = _labels_shown(main)
	main.call("apply_controls", _values())
	main.call("apply_controls", _values({"right_stick_click": true}))
	main.call("apply_controls", _values())
	var after_right: bool = _labels_shown(main)
	main.free()
	if not after_left:
		return "left-handed: the left stick click hid the labels"
	if after_right:
		return "left-handed: the right stick click did not hide the labels"
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


## ARC-3: the same frames with and without the click leave identical ships.
func test_the_click_never_reaches_the_ship() -> String:
	var with_click: Node = _main()
	var without: Node = _main()
	# Five clicks of three frames, the last released on frame 31.
	for i: int in 32:
		var stick: Vector2 = Vector2(0.6, -0.4)
		var click: bool = i % 7 < 3
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


## A wiring whose clock the test moves by hand.
class StepClock:
	var now: float = 0.0

	func read() -> float:
		return now


func test_a_hold_for_the_map_never_flips_the_labels() -> String:
	var wiring: ComfortWiring = ComfortWiring.new(LatestInputSource.new(), ThumbstickMapping.new())
	var clock: StepClock = StepClock.new()
	wiring.clock = clock.read
	var flips: Array[bool] = []
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	clock.now = MapHologram.HOLD_SECONDS + 0.05
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	flips.append(wiring.read_label_button({}))
	# A short click straight after still flips.
	flips.append(wiring.read_label_button({"left_stick_click": true}))
	clock.now += MapHologram.HOLD_SECONDS * 0.5
	flips.append(wiring.read_label_button({}))
	if flips != [false, false, false, false, true]:
		return "a long hold then a short click gave %s" % str(flips)
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
