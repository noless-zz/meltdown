class_name HubStationScreen
extends Node3D

## One station's screen in the home base room (#1299, #1359, CRW-2): a dark
## face with light words on it, only the station's title while it is not in
## use, or the title, a window of its rows with the selected one marked, and a
## refused press's reason while it is in use. A frame goes round it while it
## is the one the pilot would choose and while it is in use, so the choice is
## marked by a shape and not only by colour. Hung on the room's `Screen` mesh,
## on its face towards the pilot, so it tilts and hides with the room.
##
## The station in use comes towards the eye and grows (`focus_scale`,
## `focus_forward_m`) over `focus_seconds`, so its rows read at the size the
## look file asks for; leaving it sends it back. Only this node moves, never
## the camera (CMF-8). Sizes and colours are `HubScreenLook`'s, the mark is
## the hub panel's (`HubPanelLook`); the words are the hub text's and the
## room's labels.

const NODE_NAME: String = "Words"
## Just in front of the screen box's face (`HubRoomParts.SCREEN_SIZE_M.z` / 2).
const FACE_M: float = 0.017
## The words sit this far in front of the face, the frame half as far.
const TEXT_LIFT_M: float = 0.002
## Lines made up front: five rows and a note; more are made if a window asks.
const LINES_MADE: int = 6
## Words keep this far inside the face's edge.
const MARGIN_M: float = 0.012

var _look: Dictionary
var _screen: Dictionary
var _layers: int
var _title: Label3D
var _rows: Array[Label3D] = []
var _reason: Label3D
var _frame: Node3D
var _rest: Vector3 = Vector3(0.0, 0.0, FACE_M)
var _towards_eye: Vector3 = Vector3.BACK
## 0 at rest, 1 fully forward; `_focus_target` is where it is heading.
var _focus: float = 0.0
var _focus_target: float = 0.0
## Each row line shown: {"row": index into the rows last given, "y": its first line's middle}.
var _shown: Array[Dictionary] = []


func _init(look: Dictionary, layers: int, screen: Dictionary = HubScreenLook.load_file()) -> void:
	name = NODE_NAME
	_look = look
	_screen = screen
	_layers = layers
	position = _rest
	add_child(_face(layers))
	_frame = _make_frame(layers)
	add_child(_frame)
	_title = _label("Title", int(screen["title_font_size"]), layers)
	_make_lines(LINES_MADE)
	_reason = _wrapping(_label("Reason", int(screen["row_font_size"]), layers))
	_reason.modulate = screen["reason_color"]


## Where the eye is in the parent's space (the screen mesh's), so the station
## in use comes straight towards it.
func set_eye(eye_in_parent: Vector3) -> void:
	var to_eye: Vector3 = eye_in_parent - _rest
	if to_eye.length() > 0.001:
		_towards_eye = to_eye.normalized()


## The station not in use: its title alone, framed when `highlighted`.
func show_title(title: String, highlighted: bool) -> void:
	_put(_title, (_look["mark_text"] + title) if highlighted else title,
		_screen["selected_color"] if highlighted else _screen["title_color"])
	_title.font_size = int(_screen["title_font_size"])
	_title.position = Vector3(0.0, 0.0, TEXT_LIFT_M)
	for row: Label3D in _rows:
		row.visible = false
	_reason.visible = false
	_shown.clear()
	_frame.visible = highlighted
	_focus_target = 0.0


## The station in use: `title`, the hub text's window of `rows` (#1300) with
## row `selected` (-1 for none) marked, `note` on the line under it when it is
## not "", and `reason` when it is not "". A line too wide for the face wraps
## onto a second line rather than run off it; if the lines then overflow the
## face, the ones furthest from the selected row are left off (#1359: fewer
## rows, not smaller words), so the selected row and its note always show.
func show_rows(title: String, rows: Array[String], selected: int, note: String, reason: String) -> void:
	_put(_title, title, _screen["title_color"])
	_title.font_size = int(_screen["open_title_font_size"])
	_title.position = Vector3(0.0, float(_screen["title_y_m"]), TEXT_LIFT_M)
	_reason.text = reason
	_reason.visible = reason != ""
	var bottom: float = -face_size().y * 0.5 + MARGIN_M
	if _reason.visible:
		bottom += _height(_reason) + float(_screen["row_step_m"]) - _line_m()
	var texts: Array[String] = []
	var colors: Array[Color] = []
	var origin: Array[int] = []  # Each text's row, -1 for the note.
	var keep: int = -1  # The last line that must show: the selected row or its note.
	for i: int in rows.size():
		var chosen: bool = i == selected
		texts.append((_look["mark_text"] + rows[i]) if chosen else rows[i])
		colors.append(_screen["selected_color"] if chosen else _screen["text_color"])
		origin.append(i)
		if chosen:
			keep = texts.size() - 1
			if note != "":
				texts.append(note)
				origin.append(-1)
				colors.append(_screen["text_color"])
				keep += 1
	_make_lines(texts.size())
	var start: int = 0
	while keep > start and _fits(texts, start, keep + 1, bottom) <= keep - start:
		start += 1  # Wrapped lines above push the selected one off the face.
	var count: int = _fits(texts, start, texts.size(), bottom)
	var top: float = _first_top()
	_shown.clear()
	for i: int in _rows.size():
		var index: int = start + i
		_rows[i].visible = i < count
		if not _rows[i].visible:
			continue
		_put(_rows[i], texts[index], colors[index])
		_rows[i].position = Vector3(0.0, top, TEXT_LIFT_M)
		if origin[index] >= 0:
			_shown.append({"row": origin[index], "y": top - _line_m() * 0.5})
		top -= _height(_rows[i]) + float(_screen["row_step_m"]) - _line_m()
	_reason.position = Vector3(0.0, top, TEXT_LIFT_M)
	_frame.visible = true
	_focus_target = 1.0


## How many of `texts` from `start` (up to `end`) fit on the face above `bottom`.
func _fits(texts: Array[String], start: int, end: int, bottom: float) -> int:
	var top: float = _first_top()
	var count: int = 0
	for index: int in range(start, end):
		var height: float = _lines(texts[index], _rows[0]) * _line_m()
		if top - height < bottom and count > 0:
			break
		top -= height + float(_screen["row_step_m"]) - _line_m()
		count += 1
	return count


## Moves the screen `seconds` on towards where it is heading.
func advance(seconds: float) -> void:
	if _focus == _focus_target:
		return
	_focus = move_toward(_focus, _focus_target, seconds / float(_screen["focus_seconds"]))
	var eased: float = smoothstep(0.0, 1.0, _focus)
	position = _rest + _towards_eye * float(_screen["focus_forward_m"]) * eased
	scale = Vector3.ONE * lerpf(1.0, float(_screen["focus_scale"]), eased)


## Where each row line sits on the face, top first: {"row", "y"} (notes left out).
func shown_rows() -> Array[Dictionary]:
	return _shown.duplicate()


## 0 at rest to 1 fully forward.
func focus() -> float:
	return _focus


func framed() -> bool:
	return _frame.visible


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


## The face's size: the screen box's front, less the inset on each side.
func face_size() -> Vector2:
	var box: Vector3 = HubRoomParts.SCREEN_SIZE_M
	var inset: float = float(_screen["face_inset_m"]) * 2.0
	return Vector2(box.x - inset, box.y - inset)


func _make_lines(count: int) -> void:
	while _rows.size() < count:
		_rows.append(_wrapping(_label("Row%d" % _rows.size(), int(_screen["row_font_size"]), _layers)))


## The top of the first row: `first_row_y_m` is its first line's middle.
func _first_top() -> float:
	return float(_screen["first_row_y_m"]) + _line_m() * 0.5


## One line of a row's font, in metres.
func _line_m() -> float:
	return _font().get_height(int(_screen["row_font_size"])) * float(_screen["pixel_size"])


## The lines `text` takes in `label`'s wrap width.
func _lines(text: String, label: Label3D) -> int:
	var size: Vector2 = _font().get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, label.width,
		label.font_size, -1, TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND)
	return maxi(1, roundi(size.y / _font().get_height(label.font_size)))


func _height(label: Label3D) -> float:
	return _lines(label.text, label) * _line_m()


## Label3D draws with the theme's fallback font when it is given none.
func _font() -> Font:
	return ThemeDB.fallback_font


## A row label that wraps at the face's width and hangs from its top.
func _wrapping(label: Label3D) -> Label3D:
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.width = (face_size().x - MARGIN_M * 2.0) / float(_screen["pixel_size"])
	label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return label


func _face(layers: int) -> MeshInstance3D:
	var quad: QuadMesh = QuadMesh.new()
	quad.size = face_size()
	return _flat("Face", quad, _screen["screen_color"], layers)


## Four bars round the screen box, just outside its edge.
func _make_frame(layers: int) -> Node3D:
	var frame: Node3D = Node3D.new()
	frame.name = "Frame"
	frame.visible = false
	var box: Vector3 = HubRoomParts.SCREEN_SIZE_M
	var width: float = float(_screen["frame_width_m"])
	var half: Vector2 = Vector2(box.x + width, box.y + width) * 0.5
	var bars: Array[Array] = [
		[Vector2(box.x + width * 2.0, width), Vector2(0.0, half.y)],
		[Vector2(box.x + width * 2.0, width), Vector2(0.0, -half.y)],
		[Vector2(width, box.y), Vector2(-half.x, 0.0)],
		[Vector2(width, box.y), Vector2(half.x, 0.0)],
	]
	for i: int in bars.size():
		var quad: QuadMesh = QuadMesh.new()
		quad.size = bars[i][0]
		var bar: MeshInstance3D = _flat("Bar%d" % i, quad, _screen["frame_color"], layers)
		var at: Vector2 = bars[i][1]
		bar.position = Vector3(at.x, at.y, TEXT_LIFT_M * 0.5)
		frame.add_child(bar)
	return frame


## Unshaded, so the colour the pilot sees is the colour in the look file.
func _flat(part_name: String, mesh: Mesh, color: Color, layers: int) -> MeshInstance3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	made.albedo_color = color
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh
	instance.material_override = made
	instance.layers = layers
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _put(label: Label3D, text: String, color: Color) -> void:
	label.visible = true
	if label.text != text:
		label.text = text  # Label3D rebuilds its glyphs on every assignment.
	label.modulate = color


func _label(label_name: String, font_size: int, layers: int) -> Label3D:
	var label: Label3D = Label3D.new()
	label.name = label_name
	label.pixel_size = float(_screen["pixel_size"])
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
