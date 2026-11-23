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
## and at most `max_rows_visible` of its rows, each with its label and value
## only; the highlighted row adds its note (#1301, `DevMenuRows`). Neither ever touches the simulation (MP-2, ARC-3).

const NODE_NAME: String = "DevMenu"
const ENTRY_PREFIX: String = "Entry"
## The head pose `DevMenuWiring` uses without a rig camera: the rig origin.
const DEFAULT_HEAD: Transform3D = Transform3D.IDENTITY
const LINE_PITCH: float = 0.07
const PIXEL_SIZE: float = 0.0008
const FONT: int = 56
const TEXT_COLOR: Color = Color(0.7, 0.78, 0.85)
const SELECTED_COLOR: Color = Color(1.0, 0.85, 0.3)
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX - 2

var model: DevMenuModel
var _lines: Array[Label3D] = []


## A closed menu from `spec`, offering the level files at `level_paths`.
func _init(spec: DevMenuSpec = DevMenuSpec.load_file(),
		level_paths: Array[String] = DevMenuLevels.files()) -> void:
	name = NODE_NAME
	model = DevMenuModel.new(spec, level_paths)
	for index: int in spec.max_rows_visible:
		var line: Label3D = Label3D.new()
		line.name = "%s%d" % [ENTRY_PREFIX, index]
		line.position = Vector3(0.0, -index * LINE_PITCH, 0.0)
		line.pixel_size = PIXEL_SIZE
		line.font_size = FONT
		line.outline_size = 0
		line.shaded = false
		line.double_sided = false
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		line.no_depth_test = true
		line.render_priority = RENDER_PRIORITY
		add_child(line)
		_lines.append(line)
	visible = false


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


## The text of each shown line, top to bottom, for tests and logs.
func texts() -> Array[String]:
	var shown: Array[String] = []
	for line: Label3D in _lines:
		if line.visible:
			shown.append(line.text)
	return shown


## The rows on screen fill the lines from the top and sit centred on the
## menu's origin, so the middle row is where `place` aimed.
func _refresh() -> void:
	var rows: Array[int] = model.rows.visible_rows()
	var top: float = (rows.size() - 1) * LINE_PITCH * 0.5
	for index: int in _lines.size():
		var line: Label3D = _lines[index]
		line.visible = index < rows.size()
		if not line.visible:
			continue
		line.position = Vector3(0.0, top - index * LINE_PITCH, 0.0)
		var chosen: bool = rows[index] == model.selected
		var text: String = row_text(model, rows[index], chosen)
		var shown: String = "> %s" % text if chosen else text
		if line.text != shown:
			line.text = shown  # Label3D rebuilds its glyphs on every assignment.
		line.modulate = SELECTED_COLOR if chosen else TEXT_COLOR


## The words `row` shows: its label and value only, or, `chosen`, the value
## between `<` and `>` with any note after it (#1301).
static func row_text(model: DevMenuModel, row: int, chosen: bool) -> String:
	var spec: DevMenuSpec = model.spec
	if row == DevMenuRows.BACK:
		return spec.back_text
	if DevMenuRows.section_of(row) != -1:
		return str(spec.sections[DevMenuRows.section_of(row)]["label"])
	var text: String = str(spec.entries[row]["label"])
	match str(spec.entries[row]["kind"]):
		DevMenuSpec.KIND_UPDATE: return model.update_text(text)
		DevMenuSpec.KIND_RETURN: return model.return_text(text)
	var helper: DevMenuValue = model.value(str(spec.entries[row]["kind"]))
	if helper == null:
		return text
	if chosen:
		return "%s: < %s >" % [text, helper.value_text()]
	return "%s: %s" % [text, helper.plain_text()]
