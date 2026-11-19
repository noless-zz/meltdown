extends RefCounted

## The warnings before the ship is lost (#616, CMB-2, PLT-6): the low-hull and
## shield-break pulses fire once per crossing on both hands, from data, and
## the hull bar turns red at the same mark (ARC-4).


static func _warnings() -> Array:
	var spec: HapticsSpec = HapticsSpec.load_file()
	var haptics: DefenceHaptics = DefenceHaptics.new(spec, 0.25)
	var requests: Array[String] = []
	haptics.request_hook = func(hand: String, _pulse: Dictionary) -> void: requests.append(hand)
	return [haptics, requests]


func test_the_shipped_file_has_both_warning_pulses() -> String:
	var spec: HapticsSpec = HapticsSpec.load_file()
	if spec.error != "":
		return spec.error
	var low: Dictionary = spec.pulse_for(HapticsSpec.LOW_HULL)
	var shield: Dictionary = spec.pulse_for(HapticsSpec.SHIELD_BREAK)
	if low.is_empty() or shield.is_empty():
		return "a warning pulse is missing"
	if low == shield:
		return "the shield-break pulse is not distinct from the low-hull pulse"
	if shield["duration_s"] >= low["duration_s"]:
		return "the shield-break pulse is not the short one"
	return ""


func test_low_hull_fires_once_per_crossing_on_both_hands() -> String:
	var pair: Array = _warnings()
	var haptics: DefenceHaptics = pair[0]
	var requests: Array[String] = pair[1]
	haptics.update(1.0, 1.0, false)
	if not haptics.update(1.0, 0.3, false).is_empty():
		return "a pulse above the mark"
	if haptics.update(1.0, 0.25, false) != ([HapticsSpec.LOW_HULL] as Array[String]):
		return "no low-hull pulse at the mark"
	if requests != (["left", "right"] as Array[String]):
		return "the pulse went to %s, not both hands" % [requests]
	for hull: float in [0.2, 0.1, 0.0]:
		if not haptics.update(1.0, hull, false).is_empty():
			return "the low-hull pulse fired again at %.2f" % hull
	haptics.update(1.0, 0.6, false)
	if haptics.update(1.0, 0.2, false) != ([HapticsSpec.LOW_HULL] as Array[String]):
		return "a second crossing after recovering did not pulse"
	return ""


func test_shield_break_fires_once_when_it_reaches_zero() -> String:
	var pair: Array = _warnings()
	var haptics: DefenceHaptics = pair[0]
	haptics.update(0.5, 1.0, false)
	if haptics.update(0.0, 1.0, false) != ([HapticsSpec.SHIELD_BREAK] as Array[String]):
		return "no pulse when the shield broke"
	if not haptics.update(0.0, 1.0, false).is_empty():
		return "the shield pulse repeats while it stays at zero"
	haptics.update(0.1, 1.0, false)
	if haptics.update(0.0, 1.0, false) != ([HapticsSpec.SHIELD_BREAK] as Array[String]):
		return "a recharged shield breaking again did not pulse"
	return ""


func test_the_first_values_and_a_reset_never_pulse() -> String:
	var pair: Array = _warnings()
	var haptics: DefenceHaptics = pair[0]
	if not haptics.update(0.0, 0.1, false).is_empty():
		return "a ship starting low pulsed on its first frame"
	haptics.reset()
	if not haptics.update(0.0, 0.0, false).is_empty():
		return "the first frame after a reset pulsed"
	return ""


func test_no_spec_sends_nothing() -> String:
	var haptics: DefenceHaptics = DefenceHaptics.new(null)
	var asked: Array[int] = [0]
	haptics.request_hook = func(_hand: String, _pulse: Dictionary) -> void: asked[0] += 1
	haptics.update(1.0, 1.0, true)
	var fired: Array[String] = haptics.update(0.0, 0.0, true)
	if fired.size() != 2 or asked[0] != 0:
		return "without a spec: fired %s, asked %d" % [fired, asked[0]]
	return ""


func test_the_mark_is_the_status_panel_look_value() -> String:
	var look: Dictionary = StatusPanelLook.load_file()
	if not is_equal_approx(look["low_hull_fraction"], 0.25):
		return "the shipped mark is %s, not 0.25" % look["low_hull_fraction"]
	if DefenceHaptics.load_shipped().low_hull_fraction != look["low_hull_fraction"]:
		return "the pulses use a different mark from the panel"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE))
	data["low_hull_fraction"] = 2
	var bad: Dictionary = StatusPanelLook.parse(JSON.stringify(data))
	if not bad.has("error") or not String(bad["error"]).contains("low_hull_fraction"):
		return "an out-of-range mark was accepted: %s" % bad
	return ""


func test_the_hull_bar_turns_red_at_the_mark() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var fill: MeshInstance3D = panel.get_node(StatusPanel.HULL_BAR_NAME)
	panel.show_defence(1.0, 0.5)
	var above: Color = (fill.material_override as StandardMaterial3D).albedo_color
	panel.show_defence(1.0, 0.25)
	var at: Color = (fill.material_override as StandardMaterial3D).albedo_color
	panel.show_defence(1.0, 0.9)
	var back: Color = (fill.material_override as StandardMaterial3D).albedo_color
	panel.free()
	if above != StatusPanel.HULL_COLOR or back != StatusPanel.HULL_COLOR:
		return "above the mark the bar is %s / %s" % [above, back]
	if at != StatusPanel.HULL_WARNING_COLOR:
		return "at the mark the bar is %s, not red" % at
	return ""
