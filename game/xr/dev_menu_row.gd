class_name DevMenuRow
extends Node3D

## What one development menu line draws besides its label (#1458): the row's
## icon from the base's set at the left, its value drawing in the column after
## the labels, and the value's words after that. The words show on the
## highlighted row only, and beside a bar, whose number is the value. The
## label itself stays the menu's `Entry` line (`DevMenu`). Presentation only
## (ARC-3, MP-2).

const NODE_NAME_PREFIX: String = "Row"
const ICON_NAME: String = "Icon"
const WORDS_NAME: String = "Words"

var drawing: DevMenuValueDrawing
var words: Label3D
## The icon drawn, or null; `icon_name` is its `<group>/<id>`.
var icon: HubIcon = null
var icon_name: String = ""
var _layers: int = 1
var _icon_x: float = 0.0


## A row whose icon is centred at `icon_x`, value drawing starts at `draw_x`
## and words at `words_x`, all on the node's line.
func _init(index: int, icon_x: float, draw_x: float, words_x: float, layers: int) -> void:
	name = "%s%d" % [NODE_NAME_PREFIX, index]
	_layers = layers
	_icon_x = icon_x
	drawing = DevMenuValueDrawing.new(layers)
	drawing.position = Vector3(draw_x, 0.0, 0.0)
	add_child(drawing)
	words = DevMenu.make_label(WORDS_NAME)
	words.position = Vector3(words_x, 0.0, DevMenuLook.TEXT_Z_M)
	add_child(words)


## Shows `named` from `icons` ("" for none), `helper`'s drawing (null for none)
## and `text` as the words ("" for none), in `color`.
func show_row(icons: HubIcons, named: String, helper: DevMenuValue, text: String, color: Color) -> void:
	if named != icon_name:
		_set_icon(icons, named)
	drawing.show_value(helper)
	words.visible = text != ""
	if words.text != text:
		words.text = text  # Label3D rebuilds its glyphs on every assignment.
	words.modulate = color


## The right edge of what the row draws past `from_x`, in the menu's space.
func right_edge(from_x: float) -> float:
	var edge: float = from_x
	if drawing.part_count() > 0:
		edge = maxf(edge, drawing.position.x + DevMenuLook.DRAW_W_M)
	if words.visible:
		edge = maxf(edge, words.position.x + DevMenuLook.text_width_m(words.text, words.font_size, words.pixel_size))
	return edge


func _set_icon(icons: HubIcons, named: String) -> void:
	if icon != null:
		remove_child(icon)
		icon.free()
		icon = null
	icon_name = named
	if named == "" or icons == null:
		return
	var parts: PackedStringArray = named.split("/")
	icon = HubIcon.new(icons.icon(parts[0], parts[1] if parts.size() > 1 else ""), DevMenuLook.ICON_M, _layers)
	icon.name = ICON_NAME
	icon.position = Vector3(_icon_x, 0.0, 0.0)
	var layer: int = 0
	for part: Node in icon.get_children():
		var mesh: MeshInstance3D = part as MeshInstance3D
		if mesh != null:
			# The base's own materials are depth tested; the menu draws over everything.
			var color: Color = (mesh.material_override as StandardMaterial3D).albedo_color
			mesh.material_override = DevMenuLook.material(color, DevMenuLook.shape_priority(layer))
			layer += 1
	add_child(icon)
