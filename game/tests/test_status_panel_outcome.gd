extends RefCounted

## The outcome row on the cockpit status panel (#361): hidden while the level
## runs, "ESCAPED" in the look's colour or "SHIP LOST" in the hull-warning red,
## large, centred and clear of every other row, and rebuilt only when the
## outcome changes (RUN-3, RUN-7, CMF-3). Unwired: a later issue feeds it.

const RUNNING: int = ExitRule.Outcome.RUNNING
const ESCAPED: int = ExitRule.Outcome.ESCAPED
const LOST: int = ExitRule.Outcome.LOST


static func _outcome(panel: StatusPanel) -> Label3D:
	return panel.get_node(StatusPanel.OUTCOME_NAME) as Label3D


## Half a label's glyph height, in metres: Label3D centres text on its position.
static func _half_height(label: Label3D) -> float:
	return label.font_size * label.pixel_size * 0.5


func test_the_row_is_hidden_by_default_and_while_running() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var at_start: bool = panel.outcome_visible()
	panel.show_outcome(RUNNING)
	var running: bool = panel.outcome_visible()
	panel.free()
	if at_start:
		return "the outcome row shows before any outcome"
	if running:
		return "RUNNING shows the outcome row"
	return ""


func test_each_outcome_shows_its_text_and_colour() -> String:
	var escaped_color: Color = StatusPanelLook.load_file()["escaped_color"]
	var expected: Dictionary = {
		ESCAPED: [StatusPanel.ESCAPED_TEXT, escaped_color],
		LOST: [StatusPanel.LOST_TEXT, StatusPanel.HULL_WARNING_COLOR],
	}
	for outcome: int in expected:
		var panel: StatusPanel = StatusPanel.new()
		panel.show_outcome(outcome)
		var label: Label3D = _outcome(panel)
		var shown: Array = [label.text, label.modulate, panel.outcome_visible()]
		var listed: String = String(panel.texts().get(StatusPanel.OUTCOME_NAME, ""))
		panel.free()
		if shown[0] != expected[outcome][0] or listed != shown[0]:
			return "outcome %d reads %s, not %s" % [outcome, shown[0], expected[outcome][0]]
		if shown[1] != expected[outcome][1]:
			return "outcome %d is drawn in %s, not %s" % [outcome, shown[1], expected[outcome][1]]
		if not shown[2]:
			return "outcome %d does not show the row" % outcome
	if StatusPanel.ESCAPED_TEXT != "ESCAPED" or StatusPanel.LOST_TEXT != "SHIP LOST":
		return "the outcome texts are %s and %s" % [StatusPanel.ESCAPED_TEXT, StatusPanel.LOST_TEXT]
	if escaped_color.is_equal_approx(StatusPanel.HULL_WARNING_COLOR) or escaped_color.is_equal_approx(StatusPanel.TEXT_COLOR):
		return "ESCAPED is drawn in the warning red or the plain text colour"
	return ""


func test_switching_back_to_running_hides_the_row() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_outcome(LOST)
	panel.show_outcome(RUNNING)
	var hidden: bool = not panel.outcome_visible()
	panel.show_outcome(ESCAPED)
	var shown_again: bool = panel.outcome_visible()
	var text: String = _outcome(panel).text
	panel.free()
	if not hidden:
		return "RUNNING after LOST leaves the row showing"
	if not shown_again or text != StatusPanel.ESCAPED_TEXT:
		return "ESCAPED after RUNNING shows %s (visible %s)" % [text, shown_again]
	return ""


func test_the_same_outcome_every_frame_rebuilds_once() -> String:
	var panel: StatusPanel = StatusPanel.new()
	for frame: int in 90:
		panel.show_outcome(RUNNING)
	var while_running: int = panel.outcome_text_changes
	for frame: int in 90:
		panel.show_outcome(ESCAPED)
	var escaped: int = panel.outcome_text_changes
	for frame: int in 90:
		panel.show_outcome(LOST)
	var lost: int = panel.outcome_text_changes
	panel.free()
	if while_running != 0:
		return "RUNNING rebuilt the label %d times" % while_running
	if escaped != 1:
		return "a second of ESCAPED rebuilt the label %d times" % escaped
	if lost != 2:
		return "a second of LOST after ESCAPED rebuilt the label %d times in all" % lost
	return ""


func test_the_row_is_large_centred_and_still() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var label: Label3D = _outcome(panel)
	var before: Transform3D = label.transform
	panel.show_outcome(ESCAPED)
	for frame: int in 30:
		panel.advance(1.0 / 72.0)
		panel.show_outcome(ESCAPED)
	var after: Transform3D = label.transform
	var looks_right: bool = label.font_size == StatusPanel.LARGE_FONT \
		and label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER \
		and is_zero_approx(label.position.x) \
		and label.no_depth_test and label.render_priority == StatusPanel.RENDER_PRIORITY_TOP \
		and not label.shaded and label.billboard == BaseMaterial3D.BILLBOARD_DISABLED
	var children: int = label.get_child_count()
	panel.free()
	if not looks_right:
		return "the outcome label is not a large, centred, flat panel label"
	if not before.is_equal_approx(after):
		return "the outcome row moved from %s to %s" % [before, after]
	if children != 0:
		return "the outcome row carries %d child nodes (no animation is expected)" % children
	return ""


func test_the_row_does_not_overlap_the_others() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var label: Label3D = _outcome(panel)
	var bottom: float = label.position.y - _half_height(label)
	var clashes: Array[String] = []
	for child: Node in panel.get_children():
		if child == label or not child is Node3D:
			continue
		var top: float = (child as Node3D).position.y
		if child is Label3D:
			top += _half_height(child as Label3D)
		else:
			top += PanelBar.HEIGHT * 0.5
		if top >= bottom:
			clashes.append("%s reaches %.3f" % [child.name, top])
	panel.free()
	if not clashes.is_empty():
		return "the outcome row from %.3f down meets %s" % [bottom, ", ".join(clashes)]
	return ""


func test_show_outcome_leaves_the_other_rows_alone() -> String:
	var panel: StatusPanel = StatusPanel.new()
	panel.show_values(2, "Guided", 12.0, 0.5, "", "abc")
	panel.show_defence(0.6, 0.3)
	panel.show_hold("Twin Laser")
	panel.show_meltdown(12.0)
	var before: Dictionary = panel.texts()
	var visible_before: Array[bool] = [panel.meltdown_visible(), panel.large_preset_visible()]
	for outcome: int in [ESCAPED, LOST, RUNNING]:
		panel.show_outcome(outcome)
	var after: Dictionary = panel.texts()
	var visible_after: Array[bool] = [panel.meltdown_visible(), panel.large_preset_visible()]
	var bars: Vector3 = Vector3(panel.energy_bar_scale(), panel.shield_bar_scale(), panel.hull_bar_scale())
	var warnings: Array[bool] = [panel.hull_warning_shown(), panel.meltdown_warning_shown()]
	panel.free()
	for key: String in before:
		if key != StatusPanel.OUTCOME_NAME and before[key] != after[key]:
			return "show_outcome changed %s from %s to %s" % [key, before[key], after[key]]
	if visible_before != visible_after:
		return "show_outcome changed which rows show: %s to %s" % [visible_before, visible_after]
	if not bars.is_equal_approx(Vector3(0.5, 0.6, 0.3)):
		return "show_outcome moved the bars to %s" % bars
	if warnings != [false, true]:
		return "show_outcome changed the warnings to %s" % [warnings]
	return ""


func test_the_look_file_sets_the_escaped_colour() -> String:
	var parsed: Dictionary = StatusPanelLook.parse('{"escaped_color": [0.1, 0.2, 0.3]}')
	if parsed.has("error") or not (parsed["escaped_color"] as Color).is_equal_approx(Color(0.1, 0.2, 0.3)):
		return "a valid look parses to %s" % parsed
	var bad: Dictionary = {
		'{"escaped_color": [0.1, 0.2]}': "escaped_color",
		'{"escaped_color": [0.1, 0.2, 1.5]}': "escaped_color",
		'{"escaped_color": [true, 0.2, 0.3]}': "escaped_color",
		'{}': "escaped_color",
		'{"escaped_color": [0.1, 0.2, 0.3], "colour": 1}': "colour",
		'[1]': "object",
	}
	for text: String in bad:
		var result: Dictionary = StatusPanelLook.parse(text)
		if not result.has("error") or not String(result["error"]).contains(bad[text]):
			return "%s gives %s, not an error naming %s" % [text, result, bad[text]]
	var shipped: Dictionary = StatusPanelLook.parse(FileAccess.get_file_as_string(StatusPanelLook.DEFAULT_FILE))
	if shipped.has("error"):
		return "the shipped look is rejected: %s" % shipped["error"]
	return ""
