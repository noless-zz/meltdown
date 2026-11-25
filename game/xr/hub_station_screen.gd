class_name HubStationScreen
extends Node3D

## The words on one station's screen in the home base room (#1299, CRW-2):
## only the station's title while it is not in use (marked while it is the one
## the pilot would choose), or the title, the hub text's window of its rows
## with the selected one marked and its note on one line under it, and a
## refused press's reason while it is in use. The hub text picks the window
## (`max_rows_visible` in the hub file, #1300); the screen only draws it. Hung
## on the room's `Screen` mesh, on its face towards the pilot, so it tilts and
## hides with the room. The colours and the mark are the hub panel's
## (`HubPanelLook`); the words are the hub text's and the room's labels.

const NODE_NAME: String = "Words"
## Lines made up front: five rows and a note; more are made if a window asks.
const LINES_MADE: int = 6
## Just in front of the screen box's face (`HubRoomParts.SCREEN_SIZE_M.z` / 2).
const FACE_M: float = 0.017
const TITLE_Y_M: float = 0.1
const STEP_M: float = 0.022
const TITLE_FONT_SIZE: int = 40
const ROW_FONT_SIZE: int = 30
const PIXEL_SIZE: float = 0.0005

var _look: Dictionary
var _title: Label3D
var _rows: Array[Label3D] = []
var _reason: Label3D
var _layers: int


func _init(look: Dictionary, layers: int) -> void:
	name = NODE_NAME
	_look = look
	_layers = layers
	position = Vector3(0.0, 0.0, FACE_M)
	_title = _label("Title", TITLE_FONT_SIZE, layers)
	_title.position = Vector3(0.0, TITLE_Y_M, 0.0)
	_reason = _label("Reason", ROW_FONT_SIZE, layers)
	_reason.modulate = look["reason_color"]
	_make_lines(LINES_MADE)


## The station not in use: its title alone, marked when `highlighted`.
func show_title(title: String, highlighted: bool) -> void:
	_put(_title, (_look["mark_text"] + title) if highlighted else title,
		_look["selected_color"] if highlighted else _look["title_color"])
	for row: Label3D in _rows:
		row.visible = false
	_reason.visible = false


## The station in use: `title`, the shown `rows` with row `selected` (-1 for
## none) marked, `note` on the line under it when it is not "", and `reason`
## when it is not "".
func show_rows(title: String, rows: Array[String], selected: int, note: String, reason: String) -> void:
	_put(_title, title, _look["title_color"])
	var lines: Array[String] = []
	var colors: Array[Color] = []
	for i: int in rows.size():
		var chosen: bool = i == selected
		lines.append((_look["mark_text"] + rows[i]) if chosen else rows[i])
		colors.append(_look["selected_color"] if chosen else _look["text_color"])
		if chosen and note != "":
			lines.append(note)
			colors.append(_look["text_color"])
	_make_lines(lines.size())
	for i: int in _rows.size():
		_rows[i].visible = i < lines.size()
		if _rows[i].visible:
			_put(_rows[i], lines[i], colors[i])
	_reason.text = reason
	_reason.visible = reason != ""
	_reason.position = Vector3(0.0, TITLE_Y_M - STEP_M * (lines.size() + 1), 0.0)


## The shown lines, top first.
func texts() -> Array[String]:
	var shown: Array[String] = []
	var labels: Array[Label3D] = [_title]
	labels.append_array(_rows)
	labels.append(_reason)
	for label: Label3D in labels:
		if label.visible:
			shown.append(label.text)
	return shown


func _make_lines(count: int) -> void:
	while _rows.size() < count:
		var line: Label3D = _label("Row%d" % _rows.size(), ROW_FONT_SIZE, _layers)
		line.position = Vector3(0.0, TITLE_Y_M - STEP_M * (_rows.size() + 1), 0.0)
		_rows.append(line)


func _put(label: Label3D, text: String, color: Color) -> void:
	label.visible = true
	if label.text != text:
		label.text = text  # Label3D rebuilds its glyphs on every assignment.
	label.modulate = color


func _label(label_name: String, font_size: int, layers: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.pixel_size = PIXEL_SIZE
	label.font_size = font_size
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.layers = layers
	label.visible = false
	add_child(label)
	return label
