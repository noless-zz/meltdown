class_name DevMenuInfo
extends Node3D

## The dev menu's read-only Info section (#1207): a heading and dim lines
## under the menu's entries with the development lines the status panel no
## longer draws in flight: speed and afterburner, comfort preset, which seed
## or level is flown, and the build. Each line is the text of the panel's own
## row, so it reads exactly as the panel showed it; the panel keeps taking its
## values while those rows do not draw (`StatusPanelRowList`).
##
## It hangs under the `DevMenu`, so it opens and goes with it and sits where
## the menu sits, and is refreshed every frame while the menu shows. Nothing
## here can be selected or chosen, and nothing writes simulation state (ARC-3).

const NODE_NAME: String = "DevMenuInfo"
const TITLE_NAME: String = "InfoTitle"
const LINE_PREFIX: String = "Info"
## Smaller and closer together than the entries' `DevMenu.FONT` and
## `DevMenu.LINE_PITCH`, and dim, so it reads as notes and not as choices.
const FONT: int = 40
const LINE_PITCH: float = 0.05
## Dim beside the entries, yet 7:1 on the menu's plate (#1458, #1359).
const TEXT_COLOR: Color = Color(0.6, 0.66, 0.7)
const TITLE_COLOR: Color = Color(0.7, 0.78, 0.85)
## The panel rows the section shows, top to bottom, by `StatusPanel` label name.
const ROWS: Array[String] = [StatusPanel.SPEED_NAME, StatusPanel.PRESET_NAME,
	StatusPanel.LEVEL_NAME, StatusPanel.BUILD_NAME]

## The node the status panel hangs under (the rig); null shows no lines.
var source: Node3D = null
var _title: Label3D
var _lines: Array[Label3D] = []


func _init(title: String = "Info") -> void:
	name = NODE_NAME
	_title = _label(TITLE_NAME, TITLE_COLOR)
	_title.text = title
	for index: int in ROWS.size():
		_lines.append(_label("%s%d" % [LINE_PREFIX, index], TEXT_COLOR))


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


## Reads the panel under `source` again and puts the section under the
## lowest entry the menu shows.
func refresh() -> void:
	var panel: StatusPanel = null
	if source != null:
		panel = source.get_node_or_null(StatusPanel.NODE_NAME) as StatusPanel
	var shown: Array[String] = lines_for(panel)
	# Centred under the rows; the entries' own lines start at the label column (#1458).
	var top: Vector3 = Vector3(0.0, _lowest_entry().y - DevMenu.LINE_PITCH, DevMenuLook.TEXT_Z_M)
	_title.position = top
	for index: int in _lines.size():
		var line: Label3D = _lines[index]
		line.visible = index < shown.size()
		line.position = top + Vector3(0.0, -(index + 1) * LINE_PITCH, 0.0)
		if line.visible and line.text != shown[index]:
			line.text = shown[index]  # Label3D rebuilds its glyphs on every assignment.


## The section's lines for `panel`, top to bottom: speed with the afterburner
## state after it, then the preset, level and build rows as the panel words
## them. Empty rows are left out; no panel gives none.
static func lines_for(panel: StatusPanel) -> Array[String]:
	var shown: Array[String] = []
	if panel == null:
		return shown
	var texts: Dictionary = panel.texts()
	for row: String in ROWS:
		var text: String = str(texts.get(row, ""))
		if row == StatusPanel.SPEED_NAME and str(texts.get(StatusPanel.BOOST_NAME, "")) != "":
			text = "%s %s" % [text, texts[StatusPanel.BOOST_NAME]]
		if text.strip_edges() != "":
			shown.append(text)
	return shown


## The heading and each shown line, top to bottom, for tests and logs.
func texts() -> Array[String]:
	var shown: Array[String] = [_title.text]
	for line: Label3D in _lines:
		if line.visible:
			shown.append(line.text)
	return shown


## Where the lowest entry line the parent menu shows sits, or the origin.
## The section takes its place from the entries, not from fixed numbers, so
## it follows the menu's own layout.
func _lowest_entry() -> Vector3:
	var lowest: Vector3 = Vector3(0.0, INF, 0.0)
	var parent: Node = get_parent()
	if parent != null:
		for child: Node in parent.get_children():
			if child is Label3D and String(child.name).begins_with(DevMenu.ENTRY_PREFIX) \
					and (child as Label3D).visible and (child as Label3D).position.y < lowest.y:
				lowest = (child as Label3D).position
	return Vector3.ZERO if lowest.y == INF else lowest


func _label(label_name: String, color: Color) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.pixel_size = DevMenu.PIXEL_SIZE
	label.font_size = FONT
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.modulate = color
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.no_depth_test = true
	label.render_priority = DevMenu.RENDER_PRIORITY
	label.layers = DevMenu.LAYERS
	add_child(label)
	return label
