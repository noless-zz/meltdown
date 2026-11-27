class_name UpdateSign
extends Node3D

## The "Update available" sign at the home base (#1450, DEV-8, CRW-2): when the
## start-up check finds a newer build, two lines by the seat name it and say how
## to take it, so the owner sees it without opening anything. It goes when no
## build waits. A sign of its own, not drawn into a station screen.
##
## Where it stands and what it says are data (`UpdateSignLook`). It is hung
## under the home base room, whose origin is the seat's eye point, and turns its
## face to that point; it is drawn on the room's layer, which the camera shows
## alone at the base. Text only, unshaded and still (CMF-3); it reads no
## simulation state and writes none (MP-2, ARC-3).

const NODE_NAME: String = "UpdateSign"
const TEXT_COLOR: Color = Color(1.0, 0.85, 0.3)

var look: UpdateSignLook
## The build the sign names; "" while hidden.
var version: String = ""
var _lines: Array[Label3D] = []


func _init(p_look: UpdateSignLook = UpdateSignLook.load_file()) -> void:
	name = NODE_NAME
	look = p_look
	transform = facing(look.position_m)
	for index: int in 2:
		var label: Label3D = Label3D.new()
		label.name = "Line%d" % index
		label.position = Vector3(0.0, -index * look.line_pitch_m, 0.0)
		label.pixel_size = look.pixel_size_m
		label.font_size = int(look.font_size)
		label.outline_size = 0
		label.shaded = false
		label.double_sided = false
		label.modulate = TEXT_COLOR
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		label.layers = DevMenu.LAYERS
		add_child(label)
		_lines.append(label)
	visible = false


## A pose at `position` whose face (+z, where a label reads from) turns to the
## origin, upright.
static func facing(position: Vector3) -> Transform3D:
	var away: Vector3 = position.normalized()
	var flat: Vector3 = Vector3(away.x, 0.0, away.z)
	return Transform3D(Basis.looking_at(flat if flat.length() > 0.001 else Vector3.FORWARD), position)


## Shows the sign naming `p_version`, or hides it for "".
func show_version(p_version: String) -> void:
	if p_version == version:
		return
	version = p_version
	var shown: Array[String] = look.lines(version)
	for index: int in _lines.size():
		var text: String = shown[index] if index < shown.size() else ""
		if _lines[index].text != text:
			_lines[index].text = text  # Label3D rebuilds its glyphs on every assignment.
	visible = not shown.is_empty()


func texts() -> Array[String]:
	var shown: Array[String] = []
	for label: Label3D in _lines:
		if visible and label.text != "":
			shown.append(label.text)
	return shown
