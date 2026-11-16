class_name ControllerModel
extends Node3D

## A simple, generic controller shape for one hand, built from primitive
## meshes, with a floating label beside each bound control (PLT-5, CMF-4).
##
## The shape is original and deliberately plain: a handle, a head with a
## stick, two face buttons, a small menu button and a trigger. When the OpenXR runtime supplies its
## own model of the controller (XR_EXT_render_model, #93), that model is shown
## instead and the generic shape is hidden; it comes back if the runtime
## removes its model. The runtime's model is fetched at run time and never
## stored in the repository (NAM-3). Labels stay in both cases and are
## billboarded so they face the player from any hand angle. Nothing here reads
## or writes input or ship state; the rig hands it the words to show (ARC-3).

## Where each control's label sits; see `ControlLabelSet` (#147).
const LABEL_POSITIONS: Dictionary = ControlLabelSet.LABEL_POSITIONS

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
## Behind the stick, towards the grip. Only the left one is read (reset, #162);
## on the right hand the same place is the system button.
const MENU_RADIUS: float = 0.004
const MENU_OFFSET: Vector3 = Vector3(-0.01, 0.029, 0.012)
const TRIGGER_SIZE: Vector3 = Vector3(0.012, 0.025, 0.012)
const TRIGGER_OFFSET: Vector3 = Vector3(0.0, -0.01, -0.05)
const DETAIL_COLOR: Color = Color(0.15, 0.15, 0.15)
## Hand-local point of each control on the right hand, where its label's
## leader line ends: the top of the stick, the face of each button, the
## trigger, and the outer side of the handle for the grip.
const CONTROL_POINTS: Dictionary = {
	"stick_x": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"stick_y": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"stick_click": STICK_OFFSET + Vector3(0.0, STICK_HEIGHT * 0.5, 0.0),
	"button_upper": BUTTON_UPPER_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"button_lower": BUTTON_LOWER_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"menu": MENU_OFFSET + Vector3(0.0, BUTTON_HEIGHT * 0.5, 0.0),
	"trigger": TRIGGER_OFFSET,
	"grip": Vector3(HANDLE_RADIUS, -HANDLE_LENGTH * 0.4, 0.01),
}
## Child names of the generic shape, hidden while a runtime model is shown.
const GENERIC_PARTS: PackedStringArray = ["Handle", "Head", "Stick", "ButtonUpper", "ButtonLower", "Menu", "Trigger"]
## The node that asks the runtime for this hand's controller model.
const RUNTIME_MODELS_NAME: String = "RuntimeModels"

## `"left"` or `"right"`; picks which way the shape and labels mirror.
var hand: String = "right"
var body_color: Color = Color(0.5, 0.5, 0.5)
## The pose the parent XRController3D follows. Runtime models arrive in
## XROrigin3D space, so the manager must undo this pose to sit under the hand.
var pose_name: StringName = &"default"
var show_labels: bool = true:
	set(value):
		show_labels = value
		if _labels_root != null:
			_labels_root.visible = value

var _labels_root: ControlLabelSet = null
## Runtime models shown now; the generic shape is visible only at zero.
var _runtime_model_count: int = 0


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
	_part("Menu", _cylinder(MENU_RADIUS, BUTTON_HEIGHT), detail, _mirror(MENU_OFFSET))
	var trigger: BoxMesh = BoxMesh.new()
	trigger.size = TRIGGER_SIZE
	_part("Trigger", trigger, detail, TRIGGER_OFFSET)
	_labels_root = ControlLabelSet.new(hand)
	_labels_root.visible = show_labels
	add_child(_labels_root)
	_runtime_model_count = 0
	_add_runtime_models()


## True while the runtime supplies this hand's model and the generic shape is hidden.
func has_runtime_model() -> bool:
	return _runtime_model_count > 0


## True when the generic shape is drawn (every part visible).
func generic_shape_visible() -> bool:
	for part: String in GENERIC_PARTS:
		var node: Node3D = get_node_or_null(part) as Node3D
		if node == null or not node.visible:
			return false
	return true


## The runtime model manager for this hand, or null before `build`.
func runtime_models() -> OpenXRRenderModelManager:
	return get_node_or_null(RUNTIME_MODELS_NAME) as OpenXRRenderModelManager


## Replaces the labels with `labels` (control without hand prefix -> text,
## as `ControlLabels.for_hand` gives). Controls with no known position are
## skipped.
func set_labels(labels: Dictionary) -> void:
	if _labels_root == null:
		build()
	_labels_root.set_labels(labels, CONTROL_POINTS)


## Control (without hand prefix) -> the text of its label, as shown now.
func label_texts() -> Dictionary:
	if _labels_root == null:
		return {}
	return _labels_root.texts()


## The labels of this hand, or null before `build`.
func label_set() -> ControlLabelSet:
	return _labels_root


## Fades the labels and their leader lines; 0 is invisible, 1 fully shown.
func set_label_alpha(value: float) -> void:
	if _labels_root != null:
		_labels_root.set_alpha(value)


func label_alpha() -> float:
	return _labels_root.alpha() if _labels_root != null else 1.0


## True when the labels would be drawn (the model itself may still be hidden).
func labels_visible() -> bool:
	return _labels_root != null and _labels_root.visible


## Connected to the manager's `render_model_added`; public to the tests,
## which have no runtime to send it.
func on_runtime_model_added(_render_model: Node3D) -> void:
	_runtime_model_count += 1
	_show_generic(false)


## Connected to the manager's `render_model_removed`.
func on_runtime_model_removed(_render_model: Node3D) -> void:
	_runtime_model_count = maxi(_runtime_model_count - 1, 0)
	_show_generic(_runtime_model_count == 0)


func _add_runtime_models() -> void:
	# Without an OpenXR session (flat, headless, Monado) the manager stays
	# empty and the generic shape remains.
	var manager: OpenXRRenderModelManager = OpenXRRenderModelManager.new()
	manager.name = RUNTIME_MODELS_NAME
	manager.tracker = (
		OpenXRRenderModelManager.RENDER_MODEL_TRACKER_LEFT_HAND
		if hand == "left"
		else OpenXRRenderModelManager.RENDER_MODEL_TRACKER_RIGHT_HAND
	)
	manager.make_local_to_pose = String(pose_name)
	manager.render_model_added.connect(on_runtime_model_added)
	manager.render_model_removed.connect(on_runtime_model_removed)
	add_child(manager)


func _show_generic(shown: bool) -> void:
	for part: String in GENERIC_PARTS:
		var node: Node3D = get_node_or_null(part) as Node3D
		if node != null:
			node.visible = shown


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
