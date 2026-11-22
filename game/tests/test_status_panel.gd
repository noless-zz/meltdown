extends RefCounted

## The cockpit status panel (#146): what it shows for given values, the large
## preset label on a change, and the main scene feeding it the ship's speed,
## energy and afterburner state and the active preset (ARC-3, MP-2).

const FRAME: float = 1.0 / 90.0


static func _values(buttons: Dictionary = {}) -> Dictionary:
	var values: Dictionary = ControllerSampler.idle_values()
	values["buttons"] = buttons
	return values


func _main() -> Node:
	var scene: PackedScene = load("res://main.tscn") as PackedScene
	var main: Node = scene.instantiate() if scene != null else null
	if main != null:
		main.call("attach_status_panel")
	return main


func test_the_panel_shows_the_values_it_is_given() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(3, "Pilot", 19.6, StatusPanel.BOOST_ON, "1a2b3c4, built 2026-11-16 10:00 UTC")
	panel.show_gauges(ShipGauges.of(1.0, 1.0, 0.25))
	var shown: Dictionary = panel.texts()
	var bar: float = panel.energy_bar_scale()
	panel.free()
	if shown[StatusPanel.PRESET_NAME] != "Preset 3 Pilot":
		return "preset reads %s" % shown[StatusPanel.PRESET_NAME]
	if shown[StatusPanel.SPEED_NAME] != "Speed 20 m/s":
		return "speed reads %s (19.6 should round to 20)" % shown[StatusPanel.SPEED_NAME]
	if shown[StatusPanel.BOOST_NAME] != "BOOST":
		return "boost reads %s" % shown[StatusPanel.BOOST_NAME]
	if shown[StatusPanel.BUILD_NAME] != "1a2b3c4, built 2026-11-16 10:00 UTC":
		return "build reads %s" % shown[StatusPanel.BUILD_NAME]
	if not is_equal_approx(bar, 0.25):
		return "the energy bar is %.3f long for a quarter pool" % bar
	return ""


func test_boost_recharging_and_nothing() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var seen: Array[String] = []
	for boost: String in [StatusPanel.BOOST_ON, StatusPanel.BOOST_RECHARGING, ""]:
		panel.show_values(2, "Guided", 0.0, boost, "")
		seen.append(String(panel.texts()[StatusPanel.BOOST_NAME]))
	panel.free()
	if seen != ["BOOST", "recharging", ""]:
		return "boost texts were %s" % str(seen)
	return ""


func test_the_energy_bar_follows_the_fraction_and_stays_in_range() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var cases: Dictionary = {0.0: 0.0, 0.5: 0.5, 1.0: 1.0, -0.2: 0.0, 1.5: 1.0}
	for fraction: float in cases:
		panel.show_gauges(ShipGauges.of(1.0, 1.0, fraction))
		if not is_equal_approx(panel.energy_bar_scale(), cases[fraction]):
			var got: float = panel.energy_bar_scale()
			panel.free()
			return "fraction %.2f drew a bar of %.3f" % [fraction, got]
	panel.free()
	return ""


func test_a_preset_change_shows_large_for_two_seconds() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Guided", 0.0, "", "")
	panel.advance(StatusPanel.PRESET_LARGE_SECONDS + 0.1)
	panel.show_values(2, "Guided", 0.0, "", "")
	var large_without_change: bool = panel.large_preset_visible()
	panel.show_values(3, "Pilot", 0.0, "", "")
	var large_on_change: bool = panel.large_preset_visible()
	var large_text: String = panel.texts()[StatusPanel.PRESET_LARGE_NAME]
	panel.advance(1.9)
	panel.show_values(3, "Pilot", 0.0, "", "")
	var large_before_two: bool = panel.large_preset_visible()
	panel.advance(0.2)
	panel.show_values(3, "Pilot", 0.0, "", "")
	var large_after_two: bool = panel.large_preset_visible()
	var small_after: bool = (panel.get_node(StatusPanel.PRESET_NAME) as Label3D).visible
	panel.free()
	if large_without_change:
		return "the large preset showed without a change"
	if not large_on_change or large_text != "Preset 3 Pilot":
		return "a change to preset 3 did not show it large: %s" % large_text
	if not large_before_two:
		return "the large preset went before two seconds"
	if large_after_two or not small_after:
		return "after two seconds the preset was not small again"
	return ""


func test_the_panel_sits_low_and_ahead_in_the_cockpit() -> String:
	var at: Transform3D = StatusPanel.rig_transform(Transform3D.IDENTITY)
	var facing: Vector3 = at.basis.z
	var to_eye: Vector3 = -at.origin.normalized()
	if at.origin.y >= 0.0 or at.origin.z >= 0.0:
		return "the panel is not below and ahead: %s" % at.origin
	if at.origin.length() >= 1.0:
		return "the panel is outside the ship's collision sphere"
	if facing.dot(to_eye) < 0.9:
		return "the panel's face does not point at the eyes: %s" % facing
	# Moving the cockpit moves the panel with it.
	var moved: Transform3D = StatusPanel.rig_transform(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.2, 0.0)))
	if not moved.origin.is_equal_approx(at.origin + Vector3(0.0, 1.2, 0.0)):
		return "the panel did not follow the cockpit point"
	return ""


func test_main_attaches_the_panel_to_the_rig_not_the_camera() -> String:
	var main: Node = _main()
	main.call("attach_status_panel")
	var panel: StatusPanel = main.get("status_panel")
	var parent: String = String(panel.get_parent().name) if panel != null else ""
	var count: int = 0
	for child: Node in main.get_node("XRRig").get_children():
		if child is StatusPanel:
			count += 1
	main.free()
	if parent != "XRRig":
		return "the panel's parent is '%s', not the rig origin" % parent
	if count != 1:
		return "attaching twice left %d panels" % count
	return ""


func test_holding_boost_shows_boost_and_speed_in_the_main_scene() -> String:
	var main: Node = _main()
	for i: int in 30:
		main.call("apply_controls", _values({"right_button_lower": true}))
		main.call("advance_frame", FRAME)
	var panel: StatusPanel = main.get("status_panel")
	var shown: Dictionary = panel.texts()
	var bar: float = panel.energy_bar_scale()
	var ship: ShipState = (main.get("session") as LocalSession).current_ship()
	var energy: float = ship.energy / ship.max_energy
	main.free()
	if shown[StatusPanel.BOOST_NAME] != "BOOST":
		return "with the afterburner held the panel shows '%s'" % shown[StatusPanel.BOOST_NAME]
	if shown[StatusPanel.SPEED_NAME] == "Speed 0 m/s":
		return "the panel shows no speed while boosting"
	if not is_equal_approx(bar, energy) or bar >= 1.0:
		return "the bar shows %.3f, the ship has %.3f" % [bar, energy]
	return ""


func test_a_preset_change_reaches_the_panel() -> String:
	var main: Node = _main()
	main.call("advance_frame", StatusPanel.PRESET_LARGE_SECONDS + 0.1)
	var panel: StatusPanel = main.get("status_panel")
	var large_settled: bool = panel.large_preset_visible()
	main.call("set_comfort_preset", 3)  # The menu's path; X no longer steps it (#1260).
	main.call("advance_frame", FRAME)
	var shown: String = panel.texts()[StatusPanel.PRESET_NAME]
	var large: bool = panel.large_preset_visible()
	main.free()
	if large_settled:
		return "the start preset was still large after two seconds"
	if not shown.begins_with("Preset 3 "):
		return "after the change to 3 the panel shows '%s'" % shown
	if not large:
		return "the new preset was not shown large"
	return ""


func test_the_panel_leaves_the_simulation_alone() -> String:
	var with_panel: Node = _main()
	var without: Node = (load("res://main.tscn") as PackedScene).instantiate()
	for i: int in 45:
		var values: Dictionary = _values({"right_button_lower": i < 20})
		values["right_stick"] = Vector2(0.4, 0.2)
		for main: Node in [with_panel, without]:
			main.call("apply_controls", values)
			main.call("advance_frame", FRAME)
	var hash_with: int = (with_panel.get("session") as LocalSession).sim.state_hash()
	var hash_without: int = (without.get("session") as LocalSession).sim.state_hash()
	with_panel.free()
	without.free()
	if hash_with != hash_without:
		return "showing the panel changed the simulation"
	return ""
