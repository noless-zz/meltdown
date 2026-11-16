extends RefCounted

## The control-label toggle in the main scene (#181, PLT-5, CMF-4, ARC-3): the
## stick click of the hand that does not turn flips `XRRig.show_labels` once
## per press, and the press never reaches the ship.

const FRAME: float = 1.0 / 90.0


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	return scene.instantiate() if scene != null else null


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


func test_a_press_flips_once_and_holding_does_not_repeat() -> String:
	var main: Node = _main()
	var seen: Array[bool] = []
	for press: int in 2:
		for i: int in 5:
			main.call("apply_controls", _values({"left_stick_click": true}))
			seen.append(_labels_shown(main))
		main.call("apply_controls", _values())
		seen.append(_labels_shown(main))
	main.free()
	var expected: Array[bool] = [false, false, false, false, false, false,
		true, true, true, true, true, true]
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
	for i: int in 30:
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
