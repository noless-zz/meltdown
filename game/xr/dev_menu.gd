class_name DevMenu
extends Node3D

## The in-headset development menu (#753, part 2 of #748): a small panel of
## text lines so the owner can choose the status panel's corner, the control
## scheme (#778), the hand and pitch settings (#790), what to fly, and restart, without adb, and the waiting update. `DevMenuWiring` (#763)
## opens it on a tap of the left menu button and acts on what it returns.
##
## It is hung under the rig origin at the head point like `DestroyedScreen`,
## straight ahead. It appears and goes without a fade, pauses nothing and
## moves no view (CMF-8). It draws over everything: no depth test, a render
## priority just under the fade quad's.
##
## Entries come from `DevMenuSpec` (ARC-4); what each press does is
## `DevMenuModel`. Neither ever touches the simulation (MP-2, ARC-3).

const NODE_NAME: String = "DevMenu"
const ENTRY_PREFIX: String = "Entry"
## A metre ahead and a little below the eye line: inside the comfortable
## reading zone, clear of the status panel below it.
const ORIGIN: Vector3 = Vector3(0.0, 0.05, -1.0)
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
		level_paths: Array[String] = DevMenuModel.level_files()) -> void:
	name = NODE_NAME
	model = DevMenuModel.new(spec, level_paths)
	for index: int in spec.entries.size():
		var line: Label3D = Label3D.new()
		line.name = "%s%d" % [ENTRY_PREFIX, index]
		line.position = ORIGIN + Vector3(0.0, -index * LINE_PITCH, 0.0)
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


## Shows the menu with `corner`, the level `source`, the control `scheme`
## and the hand and pitch settings in use selected.
func open(corner: String, source: String, scheme: String = "", left_handed: bool = false,
		invert_pitch: bool = false) -> void:
	model.open(corner, source, scheme, left_handed, invert_pitch)
	visible = true
	_refresh()


## Hides the menu; it keeps its choices for the next `open`.
func close() -> void:
	visible = false


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


## Shown lines close up, so a hidden update entry leaves no gap.
func _refresh() -> void:
	var row: int = 0
	for index: int in _lines.size():
		var line: Label3D = _lines[index]
		line.visible = model.is_shown(index)
		if not line.visible:
			continue
		line.position = ORIGIN + Vector3(0.0, -row * LINE_PITCH, 0.0)
		row += 1
		var entry: Dictionary = model.spec.entries[index]
		var text: String = str(entry["label"])
		match str(entry["kind"]):
			DevMenuSpec.KIND_CORNER:
				text += ": < %s >" % model.corner()
			DevMenuSpec.KIND_CONTROLS:
				text += ": < %s >" % model.scheme()
			DevMenuSpec.KIND_HANDS:
				text += ": < %s >" % model.hands_text()
			DevMenuSpec.KIND_PITCH:
				text += ": < %s >" % model.pitch_text()
			DevMenuSpec.KIND_LEVEL:
				text += ": < %s >" % model.level_text()
			DevMenuSpec.KIND_UPDATE:
				text = model.update_text(text)
		var chosen: bool = index == model.selected
		var shown: String = "> %s" % text if chosen else text
		if line.text != shown:
			line.text = shown  # Label3D rebuilds its glyphs on every assignment.
		line.modulate = SELECTED_COLOR if chosen else TEXT_COLOR
