class_name DevMenu
extends Node3D

## The in-headset development menu (#753, part 2 of #748): a small panel of
## text lines so the owner can choose the status panel's corner, the control
## scheme (#778), the hand and pitch settings (#790), the comfort preset (#805),
## the break reminder (#821), the 120 Hz option (#852), the swivel chair (#853),
## what to fly, and restart, without adb, and the waiting update. `DevMenuWiring` (#763)
## opens it on a tap of the left menu button and acts on what it returns.
##
## It is hung under the rig origin and `place` puts it where the head looks
## as it opens (#1206): its centre `distance_m` along the head's forward
## direction, moved by `offset_m` (both from `dev_menu.json`), its rows
## centred on that point and its face turned to the head, upright. It then
## stays there in the cockpit while the head moves, until the next open.
## It appears and goes without a fade, pauses nothing and moves no view
## (CMF-8). It draws over everything: no depth test, a render priority just
## under the fade quad's.
##
## Entries come from `DevMenuSpec` (ARC-4); what each press does is
## `DevMenuModel`. It shows one list at a time, the top list or a section,
## and at most `max_rows_visible` of its rows (#1301, `DevMenuRows`). Each row
## has its icon from the base's set and its value drawn, not written: a
## switch, marks or a bar (#1458, `DevMenuRow`); only the highlighted row adds
## the value's words and note. The rows stand on a plate in the base screens'
## colour (`DevMenuLook`). Neither ever touches the simulation (MP-2, ARC-3).

const NODE_NAME: String = "DevMenu"
const ENTRY_PREFIX: String = "Entry"
const PLATE_NAME: String = "Plate"
## The head pose `DevMenuWiring` uses without a rig camera: the rig origin.
const DEFAULT_HEAD: Transform3D = Transform3D.IDENTITY
const LINE_PITCH: float = 0.07
const PIXEL_SIZE: float = 0.0008
const FONT: int = 56
const TEXT_COLOR: Color = Color(0.7, 0.78, 0.85)
const SELECTED_COLOR: Color = Color(1.0, 0.85, 0.3)
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX - 2
## The default layer and the home base room's, which its camera draws alone (#1450).
const LAYERS: int = 1 | HubRoom.LAYER_BIT

var model: DevMenuModel
var icons: HubIcons
var _lines: Array[Label3D] = []
var _rows: Array[DevMenuRow] = []
var _plate: MeshInstance3D
## Where each row's icon, label, value drawing and words start (#1458).
var _icon_x: float = 0.0
var _text_x: float = 0.0
var _draw_x: float = 0.0
var _words_x: float = 0.0


## A closed menu from `spec`, offering the level files at `level_paths`.
func _init(spec: DevMenuSpec = DevMenuSpec.load_file(),
		level_paths: Array[String] = DevMenuLevels.files()) -> void:
	name = NODE_NAME
	model = DevMenuModel.new(spec, level_paths)
	icons = HubIcons.load_file()
	_lay_out(spec)
	_plate = DevMenuLook.rect(Vector2.ONE, Vector3(0.0, 0.0, DevMenuLook.PLATE_Z_M),
		DevMenuLook.PLATE_COLOR, 0, LAYERS)
	_plate.name = PLATE_NAME
	_plate.material_override = DevMenuLook.material(DevMenuLook.PLATE_COLOR, DevMenuLook.PLATE_PRIORITY)
	add_child(_plate)
	for index: int in spec.max_rows_visible:
		var line: Label3D = make_label("%s%d" % [ENTRY_PREFIX, index])
		line.position = Vector3(_text_x, -index * LINE_PITCH, DevMenuLook.TEXT_Z_M)
		add_child(line)
		_lines.append(line)
		var row: DevMenuRow = DevMenuRow.new(index, _icon_x, _draw_x, _words_x, LAYERS)
		add_child(row)
		_rows.append(row)
	visible = false


## A left-aligned line of the menu's words, drawn over everything at the base too (#1450).
static func make_label(label_name: String) -> Label3D:
	var line: Label3D = Label3D.new()
	line.name = label_name
	line.pixel_size = PIXEL_SIZE
	line.font_size = FONT
	line.outline_size = 0
	line.shaded = false
	line.double_sided = false
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	line.no_depth_test = true
	line.render_priority = RENDER_PRIORITY
	line.layers = LAYERS
	return line


## The columns: icon, label, value drawing, words. The drawings line up after
## the widest label a value row shows highlighted, and the icons, labels and
## drawings together are centred on the menu's origin, where `place` aimed.
func _lay_out(spec: DevMenuSpec) -> void:
	var widest: float = 0.0
	for index: int in spec.entries.size():
		if model.value(str(spec.entries[index]["kind"])) != null:
			widest = maxf(widest, DevMenuLook.text_width_m("> %s:" % spec.entries[index]["label"], FONT, PIXEL_SIZE))
	for section: Dictionary in spec.sections:
		widest = maxf(widest, DevMenuLook.text_width_m("> %s" % section["label"], FONT, PIXEL_SIZE))
	var gap: float = DevMenuLook.GAP_M
	var body: float = DevMenuLook.ICON_M + gap + widest + gap + DevMenuLook.DRAW_W_M
	var left: float = -body * 0.5
	_icon_x = left + DevMenuLook.ICON_M * 0.5
	_text_x = left + DevMenuLook.ICON_M + gap
	_draw_x = _text_x + widest + gap
	_words_x = _draw_x + DevMenuLook.DRAW_W_M + gap


## Shows the menu with `corner`, the level `source`, the control `scheme`,
## the hand and pitch settings, the comfort preset and the break reminder's
## on/off in use selected; `custom_base` > 0 offers the custom comfort mode (#837).
func open(corner: String, source: String, scheme: String = "", left_handed: bool = false,
		invert_pitch: bool = false, comfort_number: int = ComfortPresetFiles.START_NUMBER,
		break_on: bool = true, custom_base: int = 0) -> void:
	model.open(corner, source, scheme, left_handed, invert_pitch, comfort_number, break_on,
		custom_base)
	visible = true
	_refresh()


## Puts the menu in front of `head`, a pose in the parent's (the rig's) space.
func place(head: Transform3D) -> void:
	transform = placement(head, model.spec.distance_m, model.spec.offset_m)


## The menu's transform for `head`: centred `distance_m` along the head's
## forward direction, then `offset_m` to the right and up across the view;
## facing the head with the room's up kept up, so a tilted head does not
## tilt the text.
static func placement(head: Transform3D, distance_m: float, offset_m: Vector2) -> Transform3D:
	var forward: Vector3 = -head.basis.z.normalized()
	var up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else head.basis.y.normalized()
	var facing: Basis = Basis.looking_at(forward, up)
	var centre: Vector3 = head.origin + forward * distance_m \
		+ facing.x * offset_m.x + facing.y * offset_m.y
	return Transform3D(facing, centre)


## Hides the menu; it keeps its choices for the next `open`.
func close() -> void:
	visible = false
	model.close()  # Back to the top list; cancels the Return to base confirm step (#1246).


## One frame of named actions while open (see `DevMenuModel.press`).
## Returns what was confirmed, or ""; closed, it ignores input and returns "".
func update(held: Dictionary) -> String:
	if not visible:
		return ""
	var result: String = model.press(held)
	_refresh()
	return result


## Names the waiting build on the update entry, or hides it with "" (#763).
func set_update(version: String, busy: bool) -> void:
	model.set_update(version, busy)
	if visible:
		_refresh()


## The text of each shown line, top to bottom, its label and any words after
## its drawing, for tests and logs.
func texts() -> Array[String]:
	var shown: Array[String] = []
	for index: int in _lines.size():
		if _lines[index].visible:
			var words: Label3D = _rows[index].words
			shown.append("%s: %s" % [_lines[index].text, words.text] if words.visible else _lines[index].text)
	return shown


## The row drawings on screen, top to bottom, for tests and the acceptance step.
func shown_rows() -> Array[DevMenuRow]:
	var shown: Array[DevMenuRow] = []
	for index: int in _rows.size():
		if _rows[index].visible:
			shown.append(_rows[index])
	return shown


## The rows on screen fill the lines from the top and sit centred on the
## menu's origin, so the middle row is where `place` aimed.
func _refresh() -> void:
	var rows: Array[int] = model.rows.visible_rows()
	var top: float = (rows.size() - 1) * LINE_PITCH * 0.5
	var right: float = _draw_x + DevMenuLook.DRAW_W_M
	for index: int in _lines.size():
		var line: Label3D = _lines[index]
		line.visible = index < rows.size()
		_rows[index].visible = line.visible
		if not line.visible:
			continue
		var y: float = top - index * LINE_PITCH
		line.position = Vector3(_text_x, y, DevMenuLook.TEXT_Z_M)
		_rows[index].position = Vector3(0.0, y, 0.0)
		var chosen: bool = rows[index] == model.selected
		var parts: Array[String] = row_parts(model, rows[index], chosen)
		var shown: String = "> %s" % parts[0] if chosen else parts[0]
		if line.text != shown:
			line.text = shown  # Label3D rebuilds its glyphs on every assignment.
		var color: Color = SELECTED_COLOR if chosen else TEXT_COLOR
		line.modulate = color
		_rows[index].show_row(icons, DevMenuIcons.name_for(model.spec, rows[index]),
			_value_of(rows[index]), parts[1], color)
		right = maxf(right, _rows[index].right_edge(_text_x + DevMenuLook.text_width_m(shown, FONT, PIXEL_SIZE)))
	_fit_plate(rows.size(), right)


## The plate behind the rows shown and any Info lines under them.
func _fit_plate(count: int, right: float) -> void:
	var info: DevMenuInfo = get_node_or_null(DevMenuInfo.NODE_NAME) as DevMenuInfo
	var below: float = 0.0
	if info != null and info.visible:
		below = LINE_PITCH + DevMenuInfo.LINE_PITCH * (DevMenuInfo.ROWS.size() + 0.5)
	var pad: float = DevMenuLook.PAD_M
	var top: float = (count - 1) * LINE_PITCH * 0.5 + LINE_PITCH * 0.5 + pad
	var bottom: float = -(count - 1) * LINE_PITCH * 0.5 - LINE_PITCH * 0.5 - below - pad
	var left: float = _icon_x - DevMenuLook.ICON_M * 0.5 - pad
	_plate.visible = count > 0
	_plate.scale = Vector3(right + pad - left, top - bottom, 1.0)
	_plate.position = Vector3((left + right + pad) * 0.5, (top + bottom) * 0.5, DevMenuLook.PLATE_Z_M)


## The value helper `row` draws, or null for a section, Back or action row.
func _value_of(row: int) -> DevMenuValue:
	if row < 0:
		return null
	return model.value(str(model.spec.entries[row]["kind"]))


## The words `row` shows: its label, then its value's words after the drawing
## only when `chosen`, between `<` and `>` with any note after it (#1301), or
## beside a bar, whose number is the value (#1458).
static func row_text(model: DevMenuModel, row: int, chosen: bool) -> String:
	var parts: Array[String] = row_parts(model, row, chosen)
	return "%s: %s" % parts if parts[1] != "" else parts[0]


## `row_text` as [label, words after the drawing]; the words are "" for none.
static func row_parts(model: DevMenuModel, row: int, chosen: bool) -> Array[String]:
	var spec: DevMenuSpec = model.spec
	if row == DevMenuRows.BACK:
		return [spec.back_text, ""]
	if DevMenuRows.section_of(row) != -1:
		return [str(spec.sections[DevMenuRows.section_of(row)]["label"]), ""]
	var text: String = str(spec.entries[row]["label"])
	match str(spec.entries[row]["kind"]):
		DevMenuSpec.KIND_UPDATE: return [model.update_text(text), ""]
		DevMenuSpec.KIND_RETURN: return [model.return_text(text), ""]
	var helper: DevMenuValue = model.value(str(spec.entries[row]["kind"]))
	if helper == null:
		return [text, ""]
	if chosen:
		return [text, "< %s >" % helper.value_text()]
	return [text, helper.plain_text() if helper.drawing() == DevMenuValue.DRAW_BAR else ""]
