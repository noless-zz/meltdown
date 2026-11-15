class_name ControllerModel
extends Node3D

## A simple, generic controller shape for one hand, built from primitive
## meshes, with a floating label beside each bound control (PLT-5, CMF-4).
##
## The shape is original and deliberately plain: a handle, a head with a
## stick, two face buttons and a trigger. It stands in until the runtime's own
## controller model can be shown (#93). Labels are billboarded so they face
## the player from any hand angle. Nothing here reads or writes input or ship
## state; the rig hands it the words to show (ARC-3).

## Hand-local positions, in metres, of each control's label on the right
## hand. -z points ahead along the controller, +y up, +x to the right; the
## left hand mirrors x. Labels sit a little away from their control so two
## labels on one stick do not overlap.
const LABEL_POSITIONS: Dictionary = {
	"stick_x": Vector3(-0.055, 0.045, -0.02),
	"stick_y": Vector3(0.0, 0.075, -0.035),
	"stick_click": Vector3(0.0, 0.055, 0.0),
	"button_upper": Vector3(0.05, 0.05, 0.0),
	"button_lower": Vector3(0.05, 0.03, 0.02),
	"trigger": Vector3(0.0, -0.03, -0.09),
	"grip": Vector3(-0.05, -0.04, 0.03),
}
## About 16 mm tall text: readable at arm's length (0.5-0.7 m) in the headset.
const LABEL_FONT_SIZE: int = 32
const LABEL_PIXEL_SIZE: float = 0.0005
const LABEL_OUTLINE_SIZE: int = 8
const LABEL_COLOR: Color = Color(1.0, 1.0, 1.0)

const HANDLE_RADIUS: float = 0.018
const HANDLE_LENGTH: float = 0.10
## The handle leans back from the head, as on most grips.
const HANDLE_TILT_DEGREES: float = 25.0
const HEAD_SIZE: Vector3 = Vector3(0.05, 0.025, 0.06)
const HEAD_OFFSET: Vector3 = Vector3(0.0, 0.015, -0.02)
const STICK_RADIUS: float = 0.009
const STICK_HEIGHT: float = 0.012
const STICK_OFFSET: Vector3 = Vector3(-0.01, 0.033, -0.03)
const BUTTON_RADIUS: float = 0.006
const BUTTON_HEIGHT: float = 0.004
const BUTTON_UPPER_OFFSET: Vector3 = Vector3(0.012, 0.029, -0.015)
const BUTTON_LOWER_OFFSET: Vector3 = Vector3(0.012, 0.029, 0.002)
const TRIGGER_SIZE: Vector3 = Vector3(0.012, 0.025, 0.012)
const TRIGGER_OFFSET: Vector3 = Vector3(0.0, -0.01, -0.05)
const DETAIL_COLOR: Color = Color(0.15, 0.15, 0.15)

## `"left"` or `"right"`; picks which way the shape and labels mirror.
var hand: String = "right"
var body_color: Color = Color(0.5, 0.5, 0.5)
var show_labels: bool = true:
	set(value):
		show_labels = value
		if _labels_root != null:
			_labels_root.visible = value

var _labels_root: Node3D = null


func _init(p_hand: String = "right", p_body_color: Color = Color(0.5, 0.5, 0.5)) -> void:
	hand = p_hand
	body_color = p_body_color


## Builds the shape and an empty label holder. Safe to call again.
func build() -> void:
	for child: Node in get_children():
		remove_child(child)
		child.free()
	var body: StandardMaterial3D = _material(body_color)
	var detail: StandardMaterial3D = _material(DETAIL_COLOR)
	var handle: CylinderMesh = CylinderMesh.new()
	handle.top_radius = HANDLE_RADIUS
	handle.bottom_radius = HANDLE_RADIUS
	handle.height = HANDLE_LENGTH
	var handle_node: MeshInstance3D = _part("Handle", handle, body, Vector3(0.0, -HANDLE_LENGTH * 0.4, 0.01))
	handle_node.rotation_degrees = Vector3(-HANDLE_TILT_DEGREES, 0.0, 0.0)
	var head: BoxMesh = BoxMesh.new()
	head.size = HEAD_SIZE
	_part("Head", head, body, HEAD_OFFSET)
	_part("Stick", _cylinder(STICK_RADIUS, STICK_HEIGHT), detail, _mirror(STICK_OFFSET))
	_part("ButtonUpper", _cylinder(BUTTON_RADIUS, BUTTON_HEIGHT), detail, _mirror(BUTTON_UPPER_OFFSET))
	_part("ButtonLower", _cylinder(BUTTON_RADIUS, BUTTON_HEIGHT), detail, _mirror(BUTTON_LOWER_OFFSET))
	var trigger: BoxMesh = BoxMesh.new()
	trigger.size = TRIGGER_SIZE
	_part("Trigger", trigger, detail, TRIGGER_OFFSET)
	_labels_root = Node3D.new()
	_labels_root.name = "Labels"
	_labels_root.visible = show_labels
	add_child(_labels_root)


## Replaces the labels with `labels` (control without hand prefix -> text,
## as `ControlLabels.for_hand` gives). Controls with no known position are
## skipped.
func set_labels(labels: Dictionary) -> void:
	if _labels_root == null:
		build()
	for child: Node in _labels_root.get_children():
		_labels_root.remove_child(child)
		child.free()
	var controls: Array = labels.keys()
	controls.sort()
	for control: Variant in controls:
		if not LABEL_POSITIONS.has(control):
			continue
		var label: Label3D = Label3D.new()
		label.name = str(control)
		label.text = str(labels[control])
		label.position = _mirror(LABEL_POSITIONS[control])
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = LABEL_FONT_SIZE
		label.pixel_size = LABEL_PIXEL_SIZE
		label.outline_size = LABEL_OUTLINE_SIZE
		label.modulate = LABEL_COLOR
		# Labels must stay readable when a hand or the cockpit is in front.
		label.no_depth_test = true
		_labels_root.add_child(label)


## Control (without hand prefix) -> the text of its label, as shown now.
func label_texts() -> Dictionary:
	var texts: Dictionary = {}
	if _labels_root == null:
		return texts
	for child: Node in _labels_root.get_children():
		var label: Label3D = child as Label3D
		if label != null:
			texts[str(label.name)] = label.text
	return texts


## True when the labels would be drawn (the model itself may still be hidden).
func labels_visible() -> bool:
	return _labels_root != null and _labels_root.visible


func _mirror(offset: Vector3) -> Vector3:
	return Vector3(-offset.x, offset.y, offset.z) if hand == "left" else offset


func _part(part_name: String, mesh: Mesh, material: Material, offset: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = material
	node.position = offset
	add_child(node)
	return node


static func _cylinder(radius: float, height: float) -> CylinderMesh:
	var mesh: CylinderMesh = CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	return material
