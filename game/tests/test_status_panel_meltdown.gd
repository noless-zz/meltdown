extends RefCounted

## The meltdown row on the cockpit status panel (#315): hidden until a
## countdown is given, "Meltdown m:ss" at the top of the panel, the warning
## colour under 30 s, and no glyph rebuild while the shown second stays the
## same (RUN-2, CMF-6). Unwired: the session drives it in a later issue.

## Rows are 3 cm apart and the small font is about 1.3 cm tall.
const MIN_ROW_GAP: float = 0.025


static func _meltdown(panel: StatusPanel) -> Label3D:
	return panel.get_node(StatusPanel.MELTDOWN_NAME) as Label3D


static func _y(panel: StatusPanel, node_name: String) -> float:
	return (panel.get_node(node_name) as Node3D).position.y


func test_the_row_starts_hidden_and_hides_for_negative_values() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var at_start: bool = panel.meltdown_visible()
	panel.show_meltdown(90.0)
	var counting: bool = panel.meltdown_visible()
	panel.show_meltdown(-1.0)
	var after_negative: bool = panel.meltdown_visible()
	panel.show_meltdown(5.0)
	var again: bool = panel.meltdown_visible()
	panel.free()
	if at_start:
		return "the meltdown row shows before any countdown"
	if not counting:
		return "a countdown of 90 s does not show the row"
	if after_negative:
		return "a negative value leaves the row showing"
	if not again:
		return "a later countdown does not show the row again"
	return ""


func test_the_countdown_reads_minutes_and_seconds() -> String:
	var expected: Dictionary = {
		125.4: "Meltdown 2:05",
		59.9: "Meltdown 0:59",
		0.0: "Meltdown 0:00",
	}
	for seconds: float in expected:
		var panel: StatusPanel = StatusPanel.new()
		panel.show_meltdown(seconds)
		var shown: String = _meltdown(panel).text
		var listed: String = String(panel.texts().get(StatusPanel.MELTDOWN_NAME, ""))
		var visible: bool = panel.meltdown_visible()
		panel.free()
		if shown != expected[seconds]:
			return "%.1f s reads %s, not %s" % [seconds, shown, expected[seconds]]
		if listed != shown:
			return "texts() lists the meltdown row as %s" % listed
		if not visible:
			return "%.1f s does not show the row" % seconds
	return ""


func test_the_warning_colour_shows_under_the_threshold() -> String:
	var threshold: float = StatusPanel.MELTDOWN_WARNING_SECONDS
	var expected: Dictionary = {
		125.4: false,
		threshold: false,
		threshold - 0.1: true,
		5.0: true,
		0.0: true,
	}
	var panel: StatusPanel = StatusPanel.new()
	for seconds: float in expected:
		panel.show_meltdown(seconds)
		var label: Label3D = _meltdown(panel)
		var colour: Color = StatusPanel.HULL_WARNING_COLOR if expected[seconds] else StatusPanel.TEXT_COLOR
		if label.modulate != colour or panel.meltdown_warning_shown() != expected[seconds]:
			panel.free()
			return "%.1f s shows colour %s, expected %s" % [seconds, label.modulate, colour]
	panel.free()
	if threshold != 30.0:
		return "the warning threshold is %.1f s, not 30 s" % threshold
	return ""


func test_calls_within_one_second_do_not_rebuild_the_label() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_meltdown(45.95)
	var after_first: int = panel.meltdown_text_changes
	# A second of frames at 72 Hz, all inside 45.x.
	var seconds: float = 45.95
	while seconds > 45.0:
		panel.show_meltdown(seconds)
		seconds -= 1.0 / 72.0
	var within: int = panel.meltdown_text_changes
	panel.show_meltdown(44.99)
	var next_second: int = panel.meltdown_text_changes
	panel.show_meltdown(-1.0)
	panel.show_meltdown(44.5)
	var after_hide: int = panel.meltdown_text_changes
	panel.free()
	if after_first != 1:
		return "the first countdown changed the label %d times" % after_first
	if within != after_first:
		return "frames within one second changed the label %d more times" % (within - after_first)
	if next_second != within + 1:
		return "the next second did not change the label once"
	if after_hide != next_second:
		return "hiding and showing the same second rebuilt the label"
	return ""


func test_the_row_sits_at_the_top_above_energy() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var label: Label3D = _meltdown(panel)
	var meltdown_y: float = label.position.y
	var others: Array[String] = [
		StatusPanel.PRESET_NAME, StatusPanel.SPEED_NAME, StatusPanel.BOOST_NAME,
		StatusPanel.ENERGY_LABEL_NAME, StatusPanel.ENERGY_BAR_NAME,
		StatusPanel.SHIELD_LABEL_NAME, StatusPanel.HULL_LABEL_NAME,
		StatusPanel.HOLD_NAME, StatusPanel.WEAPON_NAME,
	]
	var lower: Dictionary = {}
	for node_name: String in others:
		lower[node_name] = _y(panel, node_name)
	var large: Label3D = panel.get_node(StatusPanel.PRESET_LARGE_NAME) as Label3D
	# The large preset label is centred on its position; half its height is
	# how far its glyphs reach down.
	var large_bottom: float = large.position.y - large.font_size * large.pixel_size * 0.5
	var small_top: float = meltdown_y + label.font_size * label.pixel_size * 0.5
	var looks_like_others: bool = label.font_size == StatusPanel.SMALL_FONT \
		and label.no_depth_test and label.render_priority == StatusPanel.RENDER_PRIORITY_TOP \
		and is_equal_approx(label.position.x, StatusPanel.LABEL_X)
	panel.free()
	for node_name: String in lower:
		if meltdown_y - float(lower[node_name]) < MIN_ROW_GAP:
			return "the meltdown row at %.3f is not clear above %s at %.3f" % [meltdown_y, node_name, lower[node_name]]
	if small_top >= large_bottom:
		return "the meltdown row reaches %.3f, into the large preset label from %.3f" % [small_top, large_bottom]
	if not looks_like_others:
		return "the meltdown label is not drawn like the other small labels"
	return ""


func test_show_meltdown_leaves_the_other_rows_alone() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Guided", 12.0, 0.5, "", "abc")
	panel.show_defence(0.6, 0.3)
	panel.show_hold("Twin Laser")
	var before: Dictionary = panel.texts()
	panel.show_meltdown(12.0)
	var after: Dictionary = panel.texts()
	var bars: Vector3 = Vector3(panel.energy_bar_scale(), panel.shield_bar_scale(), panel.hull_bar_scale())
	var hull_warning: bool = panel.hull_warning_shown()
	panel.free()
	for key: String in before:
		if key != StatusPanel.MELTDOWN_NAME and before[key] != after[key]:
			return "show_meltdown changed %s from %s to %s" % [key, before[key], after[key]]
	if not bars.is_equal_approx(Vector3(0.5, 0.6, 0.3)):
		return "show_meltdown moved the bars to %s" % bars
	if hull_warning:
		return "show_meltdown changed the hull warning"
	return ""
