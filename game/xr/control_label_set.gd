class_name ControlLabelSet
extends Node3D

## The floating labels of one controller (PLT-5, CMF-4): one `Label3D` per
## bound control with a short leader line to the control on the model.
##
## The labels ran into each other and into the other hand's (#147), then sat
## far from their buttons (#1212), then, placed in the hand's own frame, fell
## on top of each other and inside the controller once the hand was tilted in a
## resting grip (#1316). Now they stand in one column in a plane that faces the
## eye, square to its view as the text is, beside the outline of the sphere
## round the controller (`ControlLabelLayout`, a data file), on the hand's
## outer side so two hands held close never share space. The column turns
## with the eye every frame (`face`), so it reads the same
## however the hand is held; each leader runs from its row's inner edge to its
## part, which still moves with the hand.
##
## Nothing here reads or writes input or ship state (ARC-3).

const COLUMN: String = "column"
## Every labelled control. All sit in the column; the value is kept for the
## callers that ask whether a control can be labelled.
const LABEL_POSITIONS: Dictionary = {
	"stick": COLUMN,
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

## Font size in pixels of the label texture; the layout's `text_deg` sets the
## size in the world. 32 px keeps the glyphs sharp after filtering.
const LABEL_FONT_SIZE: int = 32
## A thin dark outline keeps the white text readable over a bright tunnel.
const LABEL_OUTLINE_SIZE: int = 4
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0)
const LABEL_OUTLINE_COLOR: Color = Color(0.0, 0.0, 0.0)
const LEADER_COLOR: Color = Color(1.0, 1.0, 1.0, 0.8)
## The leader stops this short of the text so it never runs into a letter.
const LEADER_GAP: float = 0.003
const LEADER_PREFIX: String = ControlLabelLeader.PREFIX
## Where the eye is assumed before `face` is first called: straight behind the
## hand, upright, as in a neutral pose.
const DEFAULT_EYE_LOCAL: Transform3D = Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.5))

## `"left"` or `"right"`; picks which way the column mirrors.
var hand: String = "right"
## Where the labels go (`ControlLabelLayout`); public so tests can swap it.
var layout: Dictionary = ControlLabelLayout.load_file()

## Control -> its part, hand-local (mirrored for the left hand).
var _points: Dictionary = {}
## Control -> its text's size in metres.
var _sizes: Dictionary = {}
## The eye in this node's frame, looking along its -z.
var _eye_local: Transform3D = DEFAULT_EYE_LOCAL
var _alpha: float = 1.0
var _leader_material: StandardMaterial3D = null


func _init(p_hand: String = "right") -> void:
	hand = p_hand
	name = "Labels"


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera != null and is_visible_in_tree() and _alpha > 0.0:
		face_global(camera.global_transform)


## Replaces the labels with `labels` (control without hand prefix -> text).
## `control_points` gives each control's hand-local point on the right-hand
## model, where its leader line ends. Unknown controls are skipped.
func set_labels(labels: Dictionary, control_points: Dictionary) -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	_points.clear()
	_sizes.clear()
	_leader_material = _make_leader_material()
	var pixel: float = pixel_size()
	var controls: Array = labels.keys()
	controls.sort()
	for control: Variant in controls:
		if not LABEL_POSITIONS.has(control):
			continue
		var label: Label3D = Label3D.new()
		label.name = str(control)
		label.text = str(labels[control])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = LABEL_FONT_SIZE
		label.pixel_size = pixel
		label.outline_size = LABEL_OUTLINE_SIZE
		label.outline_modulate = LABEL_OUTLINE_COLOR
		label.modulate = LABEL_COLOR
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if CENTRED.has(str(control)) \
			else text_alignment()
		# Labels must stay readable when a hand or the cockpit is in front.
		label.no_depth_test = true
		add_child(label)
		_sizes[control] = text_size(label.text, pixel)
		var point_name: String = str(POINT_OF.get(control, control))
		if control_points.has(point_name):
			_points[control] = mirror(control_points[point_name])
			add_child(ControlLabelLeader.new(str(control), _leader_material))
	_arrange()
	set_alpha(_alpha)


## Squares the column to an eye at `eye_local` (this node's frame, looking
## along its -z). Public so tests and checks can pose it without a tree.
func face(eye_local: Transform3D) -> void:
	eye_local = eye_local.orthonormalized()
	if eye_local.is_equal_approx(_eye_local):
		return
	_eye_local = eye_local
	_arrange()


## `face` for an eye given in the world, as the camera reports it.
func face_global(eye: Transform3D) -> void:
	face(global_transform.affine_inverse() * eye)


## The plane the column lies in, hand-local: x to the eye's right, y up in the
## eye's view, z back towards the eye, as the billboarded text faces.
func view_basis() -> Basis:
	return _eye_local.basis


## The centre of the sphere round the controller, hand-local.
func controller_centre() -> Vector3:
	return mirror(layout["controller_centre_m"])


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


## The leader of `control`, or null.
func leader_for(control: String) -> ControlLabelLeader:
	return get_node_or_null(NodePath(LEADER_PREFIX + control)) as ControlLabelLeader


## Control -> [label end, control end] of its leader, hand-local.
func leaders() -> Dictionary:
	var result: Dictionary = {}
	for control: Variant in _points:
		var leader: ControlLabelLeader = leader_for(str(control))
		if leader != null:
			result[control] = [leader.start, leader.end]
	return result


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


## Text runs away from the controller, outward from the column's inner edge.
func text_alignment() -> HorizontalAlignment:
	return HORIZONTAL_ALIGNMENT_LEFT if ControlLabelLayout.side_sign(layout, hand) > 0.0 \
		else HORIZONTAL_ALIGNMENT_RIGHT


## Metres per texture pixel of this set's labels, from the layout.
func pixel_size() -> float:
	return ControlLabelLayout.pixel_size(layout, LABEL_FONT_SIZE)


## Width and height, in metres, of `text` as a label draws it at `pixel`
## metres per pixel, outline included. Lines are split at "\n"; the widest
## sets the width.
static func text_size(text: String, pixel: float) -> Vector2:
	var font: Font = ThemeDB.fallback_font
	var pixels: Vector2 = font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE)
	pixels += Vector2.ONE * 2.0 * LABEL_OUTLINE_SIZE
	return pixels * pixel


## The hand-local point where `control`'s leader ends, on the right hand,
## from the model's `control_points`; zero for an unknown control.
static func control_point(control: String, control_points: Dictionary) -> Vector3:
	return control_points.get(POINT_OF.get(control, control), Vector3.ZERO)


func mirror(offset: Vector3) -> Vector3:
	return Vector3(-offset.x, offset.y, offset.z) if hand == "left" else offset


## Puts every row in the column square to the eye and redraws the leaders.
func _arrange() -> void:
	var basis: Basis = view_basis()
	var centre: Vector3 = controller_centre()
	var side: float = ControlLabelLayout.side_sign(layout, hand)
	var extent: float = ControlLabelLayout.outline_extent(_eye_local.affine_inverse() * centre,
		float(layout["controller_radius_m"]), side)
	var spots: Dictionary = ControlLabelLayout.place(layout, _sizes, side, extent)
	for control: Variant in spots:
		var spot: Vector2 = spots[control]
		var inner: Vector3 = centre + basis.x * spot.x + basis.y * spot.y
		var label: Label3D = label_for(str(control))
		label.position = inner
		if CENTRED.has(str(control)):
			label.position += basis.x * side * 0.5 * (_sizes[control] as Vector2).x
		var leader: ControlLabelLeader = leader_for(str(control))
		if leader != null:
			leader.draw(inner - basis.x * side * LEADER_GAP, _points[control],
				float(layout["leader_width_m"]), basis.z)


static func _make_leader_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = true
	material.albedo_color = LEADER_COLOR
	return material
