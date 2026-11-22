class_name ControlLabelSet
extends Node3D

## The floating labels of one controller (PLT-5, CMF-4): one `Label3D` per
## bound control with a short leader line to the control on the model.
##
## The first labels sat around the controller head and ran into each other
## and into the other hand's labels (#147). Then every label of a hand sat in
## one fixed column on the outer side of that hand, which on the Quest 3 model
## put them far from their buttons, on long lines, and over the status panel
## (#1212). Now each label floats just beside the part it names: the stick's
## cross over the stick, every other label just outside the controller at its
## part's height, pushed down only as far as the row above needs
## (`ControlLabelLayout`, a data file). Text still runs outward, so two hands
## held side by side never share space.
##
## The labels are billboarded, so the line always meets the text's edge.
## Nothing here reads or writes input or ship state (ARC-3).

const OVER: String = "over"
const COLUMN: String = "column"
## Every labelled control and how its label is placed: `OVER` centred over
## its part, `COLUMN` just outside the controller. Where exactly comes from
## `ControlLabelLayout.place`.
const LABEL_POSITIONS: Dictionary = {
	"stick": OVER,
	"stick_click": COLUMN,
	"button_upper": COLUMN,
	"button_lower": COLUMN,
	"menu": COLUMN,
	"trigger": COLUMN,
	"grip": COLUMN,
}
## Labels whose leader ends at another control's point: the cross names the
## stick as a whole, whose top is where the stick click's leader ends too.
const POINT_OF: Dictionary = {"stick": "stick_click"}
## Labels whose lines are centred on each other, as a cross must be.
const CENTRED: Array[String] = ["stick"]

## Font size in pixels of the label texture; with `LABEL_PIXEL_SIZE` this sets
## the size in the world. 32 px keeps the glyphs sharp after filtering.
const LABEL_FONT_SIZE: int = 32
## 0.28 mm per pixel gives letters about 9 mm high (the em), down from 16 mm
## (#147). At 0.4-0.6 m that is about 1 degree, around 20 headset pixels on a
## Quest 3, still readable, while eight rows fit beside one controller
## without crowding the view ahead.
const LABEL_PIXEL_SIZE: float = 0.00028
## A thin dark outline keeps the white text readable over a bright tunnel.
const LABEL_OUTLINE_SIZE: int = 4
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0)
const LABEL_OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0)
const LEADER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)
## The leader stops this short of the text so it never runs into a letter.
const LEADER_GAP: float = 0.003
const LEADER_PREFIX: String = "Leader_"

## `"left"` or `"right"`; picks which way the column mirrors.
var hand: String = "right"
## Where the labels go (`ControlLabelLayout`); public so tests can swap it.
var layout: Dictionary = ControlLabelLayout.load_file()

## Control -> [label end, control end] of its leader line, hand-local.
var _leaders: Dictionary = {}
var _alpha: float = 1.0
var _leader_material: StandardMaterial3D = null


func _init(p_hand: String = "right") -> void:
	hand = p_hand
	name = "Labels"


## Replaces the labels with `labels` (control without hand prefix -> text).
## `control_points` gives each control's hand-local point on the right-hand
## model, where its leader line ends. Unknown controls are skipped.
func set_labels(labels: Dictionary, control_points: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_leaders.clear()
	_leader_material = _make_leader_material()
	var controls: Array = labels.keys()
	controls.sort()
	var heights: Dictionary = {}
	var points: Dictionary = {}
	for control: Variant in controls:
		if LABEL_POSITIONS.has(control):
			heights[control] = text_size(str(labels[control])).y
			points[control] = control_point(str(control), control_points)
	var spots: Dictionary = ControlLabelLayout.place(layout, heights, points, over_controls())
	for control: Variant in controls:
		if not LABEL_POSITIONS.has(control):
			continue
		var anchor: Vector3 = mirror(spots[control])
		var label: Label3D = Label3D.new()
		label.name = str(control)
		label.text = str(labels[control])
		label.position = anchor
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = LABEL_FONT_SIZE
		label.pixel_size = LABEL_PIXEL_SIZE
		label.outline_size = LABEL_OUTLINE_SIZE
		label.outline_modulate = LABEL_OUTLINE_COLOR
		label.modulate = LABEL_COLOR
		label.horizontal_alignment = text_alignment()
		if CENTRED.has(str(control)):
			# Centred on the part below it, so the cross sits over the stick.
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		# Labels must stay readable when a hand or the cockpit is in front.
		label.no_depth_test = true
		add_child(label)
		var point_name: String = str(POINT_OF.get(control, control))
		if control_points.has(point_name):
			var start: Vector3 = leader_start(str(control), anchor, float(heights[control]))
			_add_leader(str(control), start, mirror(control_points[point_name]))
	set_alpha(_alpha)


## Control -> the text of its label, as shown now.
func texts() -> Dictionary:
	var result: Dictionary = {}
	for child: Node in get_children():
		var label: Label3D = child as Label3D
		if label != null:
			result[str(label.name)] = label.text
	return result


## The label of `control`, or null.
func label_for(control: String) -> Label3D:
	return get_node_or_null(NodePath(control)) as Label3D


## Control -> [label end, control end] of its leader, hand-local.
func leaders() -> Dictionary:
	return _leaders.duplicate()


## Sets the opacity of every label, its outline and the leader lines.
func set_alpha(value: float) -> void:
	_alpha = clampf(value, 0.0, 1.0)
	for child: Node in get_children():
		var label: Label3D = child as Label3D
		if label != null:
			label.modulate.a = LABEL_COLOR.a * _alpha
			label.outline_modulate.a = LABEL_OUTLINE_COLOR.a * _alpha
	if _leader_material != null:
		_leader_material.albedo_color.a = LEADER_COLOR.a * _alpha


func alpha() -> float:
	return _alpha


## Text runs outward: to the right on the right hand, to the left on the left.
func text_alignment() -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_RIGHT if hand == "left" else HORIZONTAL_ALIGNMENT_LEFT


## Width and height, in metres, of `text` as a label draws it, outline
## included. Lines are split at "\n"; the widest sets the width.
static func text_size(text: String) -> Vector2:
	var font: Font = ThemeDB.fallback_font
	var pixels: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	pixels += Vector2.ONE * 2.0 * LABEL_OUTLINE_SIZE
	return pixels * LABEL_PIXEL_SIZE


## The hand-local point where `control`'s leader ends, on the right hand,
## from the model's `control_points`; zero for an unknown control.
static func control_point(control: String, control_points: Dictionary) -> Vector3:
	return control_points.get(POINT_OF.get(control, control), Vector3.ZERO)


## The controls whose label is centred over their part.
static func over_controls() -> Array[String]:
	var over: Array[String] = []
	for control: String in LABEL_POSITIONS:
		if LABEL_POSITIONS[control] == OVER:
			over.append(control)
	return over


## Where `control`'s leader leaves its label at `anchor` (hand-local) whose
## text is `height` metres tall: just under a label over its part, just
## inside the inner edge of a column label, so it never runs into a letter.
func leader_start(control: String, anchor: Vector3, height: float) -> Vector3:
	if LABEL_POSITIONS.get(control, COLUMN) == OVER:
		return anchor - Vector3(0.0, 0.5 * height + LEADER_GAP, 0.0)
	var inward: float = 1.0 if hand == "left" else -1.0
	return anchor + Vector3(inward * LEADER_GAP, 0.0, 0.0)


func mirror(offset: Vector3) -> Vector3:
	return Vector3(-offset.x, offset.y, offset.z) if hand == "left" else offset


func _add_leader(control: String, start: Vector3, point: Vector3) -> void:
	var line: ImmediateMesh = ImmediateMesh.new()
	line.surface_begin(Mesh.PRIMITIVE_LINES, _leader_material)
	line.surface_add_vertex(start)
	line.surface_add_vertex(point)
	line.surface_end()
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = LEADER_PREFIX + control
	node.mesh = line
	add_child(node)
	_leaders[control] = [start, point]


static func _make_leader_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.no_depth_test = true
	material.albedo_color = LEADER_COLOR
	return material
