extends RefCounted

## The hold line on the cockpit status panel (#290): it names the part in the
## hold, says when the hold is empty, does not rebuild its glyphs when called
## every frame with the same part, and sits in its own row clear of the shield
## and hull rows (SLV-1, CMB-1). A separate file so `test_status_panel.gd`
## stays well under 300 lines.

## Rows are 3 cm apart and the small font is about 1.3 cm tall, so two rows
## closer than this would put glyphs on top of each other.
const MIN_ROW_GAP: float = 0.025


static func _hold_text(panel: StatusPanel) -> String:
	return (panel.get_node(StatusPanel.HOLD_NAME) as Label3D).text


static func _y(panel: StatusPanel, node_name: String) -> float:
	return (panel.get_node(node_name) as Node3D).position.y


func test_the_hold_shows_the_part_name() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_hold("Twin Laser")
	var shown: String = _hold_text(panel)
	var listed: String = String(panel.texts().get(StatusPanel.HOLD_NAME, ""))
	panel.free()
	if not shown.contains("Twin Laser"):
		return "the hold reads %s, not the part name" % shown
	if shown == StatusPanel.HOLD_EMPTY:
		return "a held part reads as an empty hold"
	if listed != shown:
		return "texts() lists the hold as %s" % listed
	return ""


func test_an_empty_name_shows_the_hold_is_empty() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var unwired: String = _hold_text(panel)
	panel.show_hold("Twin Laser")
	panel.show_hold("")
	var emptied: String = _hold_text(panel)
	panel.free()
	if unwired != StatusPanel.HOLD_EMPTY:
		return "an unwired panel's hold reads %s" % unwired
	if emptied != StatusPanel.HOLD_EMPTY:
		return "emptying the hold reads %s" % emptied
	if StatusPanel.HOLD_EMPTY.is_empty():
		return "the empty text is blank"
	return ""


func test_the_same_part_every_frame_does_not_rebuild_the_label() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_hold("Twin Laser")
	var after_first: int = panel.hold_text_changes
	for i: int in 90:
		panel.show_hold("Twin Laser")
	var after_frames: int = panel.hold_text_changes
	panel.show_hold("Mass Driver")
	var after_swap: int = panel.hold_text_changes
	for i: int in 90:
		panel.show_hold("")
	var after_empty: int = panel.hold_text_changes
	panel.free()
	if after_first != 1:
		return "the first part changed the label %d times" % after_first
	if after_frames != after_first:
		return "90 frames of the same part changed the label %d more times" % (after_frames - after_first)
	if after_swap != after_first + 1:
		return "a new part did not change the label once"
	if after_empty != after_swap + 1:
		return "90 frames of an empty hold changed the label %d times" % (after_empty - after_swap)
	return ""


func test_the_hold_row_sits_clear_of_the_shield_and_hull_rows() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var hold: Label3D = panel.get_node(StatusPanel.HOLD_NAME) as Label3D
	var hold_y: float = hold.position.y
	var others: Dictionary = {
		StatusPanel.SHIELD_LABEL_NAME: _y(panel, StatusPanel.SHIELD_LABEL_NAME),
		StatusPanel.SHIELD_BAR_NAME: _y(panel, StatusPanel.SHIELD_BAR_NAME),
		StatusPanel.HULL_LABEL_NAME: _y(panel, StatusPanel.HULL_LABEL_NAME),
		StatusPanel.HULL_BAR_NAME: _y(panel, StatusPanel.HULL_BAR_NAME),
		StatusPanel.WEAPON_NAME: _y(panel, StatusPanel.WEAPON_NAME),
		StatusPanel.SPEED_NAME: _y(panel, StatusPanel.SPEED_NAME),
	}
	var weapon_y: float = others[StatusPanel.WEAPON_NAME]
	var speed_y: float = others[StatusPanel.SPEED_NAME]
	var looks_like_others: bool = hold.font_size == StatusPanel.SMALL_FONT \
		and hold.no_depth_test and hold.render_priority == StatusPanel.RENDER_PRIORITY_TOP \
		and is_equal_approx(hold.position.x, StatusPanel.LABEL_X)
	panel.free()
	for node_name: String in others:
		if absf(hold_y - float(others[node_name])) < MIN_ROW_GAP:
			return "the hold row at %.3f is within %.3f of %s" % [hold_y, MIN_ROW_GAP, node_name]
	# The weapon, then the hold, then the rest (#605).
	if not (weapon_y > hold_y and hold_y > speed_y):
		return "the hold row at %.3f is not between weapon %.3f and speed %.3f" % [hold_y, weapon_y, speed_y]
	if not looks_like_others:
		return "the hold label is not drawn like the other small labels"
	return ""


func test_show_hold_leaves_the_other_rows_alone() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Guided", 12.0, "", "abc")
	panel.show_gauges(ShipGauges.of(0.3, 0.6, 0.5))
	var before: Dictionary = panel.texts()
	panel.show_hold("Twin Laser")
	var after: Dictionary = panel.texts()
	var bars: Vector3 = Vector3(panel.energy_bar_scale(), panel.shield_bar_scale(), panel.hull_bar_scale())
	panel.free()
	for key: String in before:
		if key != StatusPanel.HOLD_NAME and before[key] != after[key]:
			return "show_hold changed %s from %s to %s" % [key, before[key], after[key]]
	if not bars.is_equal_approx(Vector3(0.5, 0.6, 0.3)):
		return "show_hold moved the bars to %s" % bars
	return ""
