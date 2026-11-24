class_name HubStationScreen
extends Node3D

## The words on one station's screen in the home base room (#1299, CRW-2):
## only the station's title while it is not in use (marked while it is the one
## the pilot would choose), or the title, a window of its rows with the
## selected one marked, and a refused press's reason while it is in use. Hung
## on the room's `Screen` mesh, on its face towards the pilot, so it tilts and
## hides with the room. The colours and the mark are the hub panel's
## (`HubPanelLook`); the words are the hub text's and the room's labels.

const NODE_NAME: String = "Words"
## Rows shown at once; the window follows the selection.
const ROWS_SHOWN: int = 8
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


func _init(look: Dictionary, layers: int) -> void:
	name = NODE_NAME
	_look = look
	position = Vector3(0.0, 0.0, FACE_M)
	_title = _label("Title", TITLE_FONT_SIZE, layers)
	_title.position = Vector3(0.0, TITLE_Y_M, 0.0)
	for i: int in ROWS_SHOWN:
		_rows.append(_label("Row%d" % i, ROW_FONT_SIZE, layers))
		_rows[i].position = Vector3(0.0, TITLE_Y_M - STEP_M * (i + 1), 0.0)
	_reason = _label("Reason", ROW_FONT_SIZE, layers)
	_reason.position = Vector3(0.0, TITLE_Y_M - STEP_M * (ROWS_SHOWN + 1), 0.0)
	_reason.modulate = look["reason_color"]


## The station not in use: its title alone, marked when `highlighted`.
func show_title(title: String, highlighted: bool) -> void:
	_put(_title, (_look["mark_text"] + title) if highlighted else title,
		_look["selected_color"] if highlighted else _look["title_color"])
	for row: Label3D in _rows:
		row.visible = false
	_reason.visible = false


## The station in use: `title`, the window of `rows` around `selected` (an index
## into `rows`, -1 for none) and `reason` when it is not "".
func show_rows(title: String, rows: Array[String], selected: int, reason: String) -> void:
	_put(_title, title, _look["title_color"])
	var start: int = window_start(rows.size(), selected, ROWS_SHOWN)
	for i: int in ROWS_SHOWN:
		var index: int = start + i
		_rows[i].visible = index < rows.size()
		if not _rows[i].visible:
			continue
		var chosen: bool = index == selected
		_put(_rows[i], (_look["mark_text"] + rows[index]) if chosen else rows[index],
			_look["selected_color"] if chosen else _look["text_color"])
	_reason.text = reason
	_reason.visible = reason != ""


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


## The first row index shown so that `selected` sits in a window of `shown`
## rows out of `count`, as near the window's middle as the ends allow.
static func window_start(count: int, selected: int, shown: int) -> int:
	if count <= shown or selected < 0:
		return 0
	return clampi(selected - shown / 2, 0, count - shown)


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
