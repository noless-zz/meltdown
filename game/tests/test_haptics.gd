extends RefCounted

## Haptic pulses on the boosting hand as data (#170; PLT-6, ARC-3, ARC-4).

const FRAME: float = 1.0 / 90.0
const VALID: String = """{
	"boost_start": {"amplitude": 0.6, "duration_s": 0.08, "frequency_hz": 0},
	"boost_stop": {"amplitude": 0.3, "duration_s": 0.05, "frequency_hz": 160},
	"low_hull": {"amplitude": 0.9, "duration_s": 0.3, "frequency_hz": 0},
	"shield_break": {"amplitude": 0.7, "duration_s": 0.06, "frequency_hz": 0},
	"ship_hit": {"amplitude": 0.8, "duration_s": 0.1, "frequency_hz": 0},
	"salvage_pickup": {"amplitude": 0.35, "duration_s": 0.04, "frequency_hz": 250}
}"""


static func _with(kind: String, key: String, value: Variant) -> String:
	var data: Dictionary = JSON.parse_string(VALID)
	if value == null:
		(data[kind] as Dictionary).erase(key)
	else:
		data[kind][key] = value
	return JSON.stringify(data)


static func _expect_error(text: String, field: String) -> String:
	var spec: HapticsSpec = HapticsSpec.parse_json(text)
	if spec.error == "":
		return "text naming %s was accepted: %s" % [field, text]
	if not spec.error.contains("\"%s\"" % field):
		return "error '%s' does not name %s" % [spec.error, field]
	if not spec.pulse_for(HapticsSpec.BOOST_START).is_empty():
		return "a rejected spec still has pulses"
	return ""


func test_the_shipped_file_parses() -> String:
	var spec: HapticsSpec = HapticsSpec.load_file()
	if spec.error != "":
		return "shipped file rejected: %s" % spec.error
	for kind: String in HapticsSpec.KINDS:
		var pulse: Dictionary = spec.pulse_for(kind)
		if pulse.keys().size() != HapticsSpec.PULSE_KEYS.size():
			return "%s has %s" % [kind, pulse]
		if not pulse["amplitude"] > 0.0:
			return "%s has no strength" % kind
	return ""


func test_pulse_for_returns_the_entries_and_nothing_else() -> String:
	var spec: HapticsSpec = HapticsSpec.parse_json(VALID)
	if spec.error != "":
		return spec.error
	var start: Dictionary = spec.pulse_for(HapticsSpec.BOOST_START)
	if start != {"amplitude": 0.6, "duration_s": 0.08, "frequency_hz": 0.0}:
		return "boost_start gave %s" % start
	var stop: Dictionary = spec.pulse_for(HapticsSpec.BOOST_STOP)
	if stop != {"amplitude": 0.3, "duration_s": 0.05, "frequency_hz": 160.0}:
		return "boost_stop gave %s" % stop
	for other: String in ["", "fire_primary", "wall_impact", "boost"]:
		if not spec.pulse_for(other).is_empty():
			return "'%s' gave %s" % [other, spec.pulse_for(other)]
	start["amplitude"] = 0.0
	if spec.pulse_for(HapticsSpec.BOOST_START)["amplitude"] != 0.6:
		return "editing the returned pulse changed the spec"
	return ""


func test_unknown_and_missing_kinds_are_rejected() -> String:
	var data: Dictionary = JSON.parse_string(VALID)
	data["boost_middle"] = data["boost_start"]
	var failure: String = _expect_error(JSON.stringify(data), "boost_middle")
	if failure != "":
		return failure
	data = JSON.parse_string(VALID)
	data.erase("boost_stop")
	failure = _expect_error(JSON.stringify(data), "boost_stop")
	if failure != "":
		return failure
	data = JSON.parse_string(VALID)
	data["boost_start"] = 0.5
	return _expect_error(JSON.stringify(data), "boost_start")


func test_each_entry_field_is_checked_and_named() -> String:
	for kind: String in HapticsSpec.KINDS:
		for key: String in HapticsSpec.PULSE_KEYS:
			var field: String = "%s.%s" % [kind, key]
			var low: float = HapticsSpec.RANGES[key][0]
			var high: float = HapticsSpec.RANGES[key][1]
			for bad: Variant in [null, low - 0.001, high + 0.001, true, "0.5"]:
				var failure: String = _expect_error(_with(kind, key, bad), field)
				if failure != "":
					return "%s with %s: %s" % [field, bad, failure]
		var failure: String = _expect_error(_with(kind, "delay_s", 0.1), "%s.delay_s" % kind)
		if failure != "":
			return failure
	return ""


func test_range_edges_are_accepted() -> String:
	for key: String in HapticsSpec.PULSE_KEYS:
		for edge: float in HapticsSpec.RANGES[key]:
			var spec: HapticsSpec = HapticsSpec.parse_json(_with(HapticsSpec.BOOST_STOP, key, edge))
			if spec.error != "":
				return "%s = %s rejected: %s" % [key, edge, spec.error]
	return ""


func test_bad_text_and_missing_file_are_rejected() -> String:
	if HapticsSpec.parse_json("{").error == "":
		return "broken JSON accepted"
	if HapticsSpec.parse_json("[]").error == "":
		return "a JSON array accepted"
	if HapticsSpec.load_file("res://xr/no_such_haptics.json").error == "":
		return "a missing file accepted"
	if BoostHaptics.load_spec("res://xr/no_such_haptics.json") != null:
		return "the wiring kept a rejected file"
	return ""


func test_the_boost_hand_follows_the_mapping() -> String:
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	if HapticsSpec.hand_for_action(mapping, "afterburner") != "right":
		return "default layout boosts on '%s'" % HapticsSpec.hand_for_action(mapping, "afterburner")
	mapping.left_handed = true
	if HapticsSpec.hand_for_action(mapping, "afterburner") != "left":
		return "left-handed mode boosts on '%s'" % HapticsSpec.hand_for_action(mapping, "afterburner")
	var layout: Dictionary = ThumbstickMapping.default_layout()
	layout["afterburner"] = {"left_stick_click": 1.0, "right_trigger": 0.4}
	if HapticsSpec.hand_for_action(ThumbstickMapping.new(layout), "afterburner") != "left":
		return "the strongest binding did not decide the hand"
	layout.erase("afterburner")
	if HapticsSpec.hand_for_action(ThumbstickMapping.new(layout), "afterburner") != "":
		return "an unbound action has a hand"
	return ""


func test_holding_and_releasing_boost_asks_for_one_start_and_one_stop() -> String:
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	var haptics: BoostHaptics = main.get("boost_haptics")
	var requests: Array[Array] = []
	haptics.request_hook = func(hand: String, pulse: Dictionary) -> void: requests.append([hand, pulse])
	var spec: HapticsSpec = haptics.spec
	for frame: int in 60:
		var values: Dictionary = ControllerSampler.idle_values()
		if frame >= 5 and frame < 35:
			values["buttons"] = {"right_button_lower": true}
		main.call("apply_controls", values)
		main.call("advance_frame", FRAME)
	main.free()
	if spec == null:
		return "the shipped haptics file was rejected"
	var expected: Array[Array] = [
		["right", spec.pulse_for(HapticsSpec.BOOST_START)],
		["right", spec.pulse_for(HapticsSpec.BOOST_STOP)],
	]
	if requests != expected:
		return "the flat scene asked for %s" % [requests]
	return ""


func test_no_pulse_is_sent_without_a_session_or_controller() -> String:
	var haptics: BoostHaptics = BoostHaptics.new()
	var mapping: ThumbstickMapping = ThumbstickMapping.new()
	# No XR session: nothing reaches the (real) controller and nothing fails.
	var hand: XRController3D = XRController3D.new()
	haptics.right_controller = hand
	if haptics.update(true, mapping, false) != HapticsSpec.BOOST_START:
		hand.free()
		return "the start was not noticed"
	if haptics.update(true, mapping, false) != "":
		hand.free()
		return "a held boost counted twice"
	hand.free()
	# A session but no controllers: still nothing fails.
	haptics.right_controller = null
	if haptics.update(false, mapping, true) != HapticsSpec.BOOST_STOP:
		return "the stop was not noticed"
	return ""


func test_haptics_leave_the_simulation_alone() -> String:
	var states: Array[String] = []
	for with_spec: bool in [true, false]:
		var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
		if not with_spec:
			(main.get("boost_haptics") as BoostHaptics).spec = null
		for frame: int in 40:
			var values: Dictionary = ControllerSampler.idle_values()
			values["buttons"] = {"right_button_lower": frame < 25}
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
		states.append(str((main.get("session") as LocalSession).current_ship().state_hash()))
		main.free()
	if states[0] != states[1]:
		return "the pulses changed the ship: %s" % [states]
	return ""
