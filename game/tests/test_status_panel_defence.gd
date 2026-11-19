extends RefCounted

## The shield and hull bars on the cockpit status panel (#227): fractions set
## the bars, out-of-range values clamp, the hull label warns at 25%, the bars
## start full, and they draw at the same priorities as the energy bar (#199)
## (CMB-2, CMF-1). A separate file because `test_status_panel.gd` would pass
## about 300 lines with these added.


static func _priority(panel: StatusPanel, node_name: String) -> int:
	return (panel.get_node(node_name) as MeshInstance3D).material_override.render_priority


func test_the_bars_start_full_before_show_defence() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Guided", 0.0, 0.5, "", "")
	var shield: float = panel.shield_bar_scale()
	var hull: float = panel.hull_bar_scale()
	var warning: bool = panel.hull_warning_shown()
	panel.free()
	if not is_equal_approx(shield, 1.0) or not is_equal_approx(hull, 1.0):
		return "unwired bars show shield %.3f and hull %.3f, not full" % [shield, hull]
	if warning:
		return "an unwired panel shows the hull warning"
	return ""


func test_fractions_set_the_bar_scales() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_defence(0.6, 0.3)
	var shield: float = panel.shield_bar_scale()
	var hull: float = panel.hull_bar_scale()
	var energy: float = panel.energy_bar_scale()
	panel.free()
	if not is_equal_approx(shield, 0.6):
		return "shield 0.6 drew a bar of %.3f" % shield
	if not is_equal_approx(hull, 0.3):
		return "hull 0.3 drew a bar of %.3f" % hull
	if not is_equal_approx(energy, 1.0):
		return "show_defence moved the energy bar to %.3f" % energy
	return ""


func test_out_of_range_values_clamp() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var cases: Array[Vector4] = [
		Vector4(-0.5, 2.0, 0.0, 1.0),
		Vector4(1.5, -1.0, 1.0, 0.0),
		Vector4(NAN, INF, 0.0, 0.0),
	]
	for c: Vector4 in cases:
		panel.show_defence(c.x, c.y)
		if not is_equal_approx(panel.shield_bar_scale(), c.z) or not is_equal_approx(panel.hull_bar_scale(), c.w):
			var got: Vector2 = Vector2(panel.shield_bar_scale(), panel.hull_bar_scale())
			panel.free()
			return "show_defence(%s, %s) drew %s, expected (%s, %s)" % [c.x, c.y, got, c.z, c.w]
	panel.free()
	return ""


func test_an_empty_bar_keeps_its_left_end() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var full: MeshInstance3D = panel.get_node(StatusPanel.HULL_BAR_NAME) as MeshInstance3D
	var left_full: float = full.position.x - PanelBar.WIDTH * full.scale.x * 0.5
	panel.show_defence(0.25, 0.25)
	var left_quarter: float = full.position.x - PanelBar.WIDTH * full.scale.x * 0.5
	panel.free()
	if not is_equal_approx(left_full, left_quarter):
		return "the hull bar's left end moved from %.4f to %.4f" % [left_full, left_quarter]
	return ""


func test_the_hull_warning_appears_at_25_percent_and_not_above() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var threshold: float = StatusPanel.HULL_WARNING_FRACTION
	var expected: Dictionary = {1.0: false, 0.26: false, threshold + 0.001: false,
		threshold: true, 0.1: true, 0.0: true, -1.0: true}
	for hull: float in expected:
		panel.show_defence(1.0, hull)
		var label: Label3D = panel.get_node(StatusPanel.HULL_LABEL_NAME) as Label3D
		var colour_ok: bool = label.modulate == (StatusPanel.HULL_WARNING_COLOR if expected[hull] else StatusPanel.TEXT_COLOR)
		if panel.hull_warning_shown() != expected[hull] or not colour_ok:
			panel.free()
			return "hull %.3f: warning %s, expected %s" % [hull, not expected[hull], expected[hull]]
	# The warning goes again once the hull is back above the threshold.
	panel.show_defence(1.0, 0.1)
	panel.show_defence(1.0, 0.8)
	var cleared: bool = not panel.hull_warning_shown()
	panel.free()
	if not cleared:
		return "the warning stayed after the hull rose to 80%"
	if StatusPanel.HULL_WARNING_FRACTION != 0.25:
		return "the warning threshold is %.2f, not 25%%" % StatusPanel.HULL_WARNING_FRACTION
	return ""


func test_the_bars_use_the_energy_bars_priorities() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var energy_fill: int = _priority(panel, StatusPanel.ENERGY_BAR_NAME)
	var energy_track: int = _priority(panel, StatusPanel.ENERGY_TRACK_NAME)
	var found: Dictionary = {
		StatusPanel.SHIELD_BAR_NAME: _priority(panel, StatusPanel.SHIELD_BAR_NAME),
		StatusPanel.SHIELD_TRACK_NAME: _priority(panel, StatusPanel.SHIELD_TRACK_NAME),
		StatusPanel.HULL_BAR_NAME: _priority(panel, StatusPanel.HULL_BAR_NAME),
		StatusPanel.HULL_TRACK_NAME: _priority(panel, StatusPanel.HULL_TRACK_NAME),
	}
	var labels: Array[int] = [
		(panel.get_node(StatusPanel.SHIELD_LABEL_NAME) as Label3D).render_priority,
		(panel.get_node(StatusPanel.HULL_LABEL_NAME) as Label3D).render_priority,
	]
	var no_depth: bool = true
	for node_name: String in found:
		var material: BaseMaterial3D = (panel.get_node(node_name) as MeshInstance3D).material_override as BaseMaterial3D
		no_depth = no_depth and material.no_depth_test
	panel.free()
	if energy_fill != StatusPanel.RENDER_PRIORITY_TOP or energy_track != StatusPanel.RENDER_PRIORITY:
		return "the energy bar moved to %d over %d" % [energy_fill, energy_track]
	for node_name: String in found:
		var want: int = energy_track if String(node_name).ends_with("Track") else energy_fill
		if found[node_name] != want:
			return "%s draws at %d, the energy bar's match at %d" % [node_name, found[node_name], want]
	if labels != [StatusPanel.RENDER_PRIORITY_TOP, StatusPanel.RENDER_PRIORITY_TOP]:
		return "the shield and hull labels draw at %s" % [labels]
	if not no_depth:
		return "a shield or hull bar still has its depth test"
	return ""


## Hull, shield and energy are the first rows under the meltdown row (#605).
func test_the_bars_sit_hull_shield_energy_above_the_weapon() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var energy_y: float = (panel.get_node(StatusPanel.ENERGY_BAR_NAME) as Node3D).position.y
	var shield_y: float = (panel.get_node(StatusPanel.SHIELD_BAR_NAME) as Node3D).position.y
	var hull_y: float = (panel.get_node(StatusPanel.HULL_BAR_NAME) as Node3D).position.y
	var weapon_y: float = (panel.get_node(StatusPanel.WEAPON_NAME) as Node3D).position.y
	var shield_colour: Color = ((panel.get_node(StatusPanel.SHIELD_BAR_NAME) as MeshInstance3D).material_override as BaseMaterial3D).albedo_color
	var hull_colour: Color = ((panel.get_node(StatusPanel.HULL_BAR_NAME) as MeshInstance3D).material_override as BaseMaterial3D).albedo_color
	panel.free()
	if not (hull_y > shield_y and shield_y > energy_y and energy_y > weapon_y):
		return "rows out of order: hull %.3f, shield %.3f, energy %.3f, weapon %.3f" % [hull_y, shield_y, energy_y, weapon_y]
	if shield_colour != StatusPanel.SHIELD_COLOR or hull_colour != StatusPanel.HULL_COLOR:
		return "the bars are not drawn in the named colours"
	# Cool shield: more blue than red. Warm hull: more red than blue.
	if shield_colour.b <= shield_colour.r or hull_colour.r <= hull_colour.b:
		return "shield %s is not cool or hull %s is not warm" % [shield_colour, hull_colour]
	return ""
