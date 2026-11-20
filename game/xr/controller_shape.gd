class_name ControllerShape
extends RefCounted

## Builds `ControllerModel`'s generic controller shape from primitive meshes:
## a handle, a head, a stick, two face buttons, a menu button and a trigger
## (PLT-5). Split out of `ControllerModel` to keep it under 300 lines (#652);
## the sizes and offsets stay there, beside the leader-line points that use
## them. Only builds nodes; reads no input and no ship state (ARC-3).


## Adds the shape's parts to `model` as children named as
## `ControllerModel.GENERIC_PARTS`, mirrored for the left `hand`.
static func add_generic(model: Node3D, hand: String, body_color: Color) -> void:
	var body: StandardMaterial3D = _material(body_color)
	var detail: StandardMaterial3D = _material(ControllerModel.DETAIL_COLOR)
	var handle: CylinderMesh = _cylinder(ControllerModel.HANDLE_RADIUS, ControllerModel.HANDLE_LENGTH)
	var handle_node: MeshInstance3D = _part(model, "Handle", handle, body,
			Vector3(0.0, -ControllerModel.HANDLE_LENGTH * 0.4, 0.01))
	handle_node.rotation_degrees = Vector3(-ControllerModel.HANDLE_TILT_DEGREES, 0.0, 0.0)
	var head: BoxMesh = BoxMesh.new()
	head.size = ControllerModel.HEAD_SIZE
	_part(model, "Head", head, body, ControllerModel.HEAD_OFFSET)
	_part(model, "Stick", _cylinder(ControllerModel.STICK_RADIUS, ControllerModel.STICK_HEIGHT),
			detail, _mirror(hand, ControllerModel.STICK_OFFSET))
	_part(model, "ButtonUpper", _cylinder(ControllerModel.BUTTON_RADIUS, ControllerModel.BUTTON_HEIGHT),
			detail, _mirror(hand, ControllerModel.BUTTON_UPPER_OFFSET))
	_part(model, "ButtonLower", _cylinder(ControllerModel.BUTTON_RADIUS, ControllerModel.BUTTON_HEIGHT),
			detail, _mirror(hand, ControllerModel.BUTTON_LOWER_OFFSET))
	_part(model, "Menu", _cylinder(ControllerModel.MENU_RADIUS, ControllerModel.BUTTON_HEIGHT),
			detail, _mirror(hand, ControllerModel.MENU_OFFSET))
	var trigger: BoxMesh = BoxMesh.new()
	trigger.size = ControllerModel.TRIGGER_SIZE
	_part(model, "Trigger", trigger, detail, ControllerModel.TRIGGER_OFFSET)


static func _mirror(hand: String, offset: Vector3) -> Vector3:
	return Vector3(-offset.x, offset.y, offset.z) if hand == "left" else offset


static func _part(model: Node3D, part_name: String, mesh: Mesh, material: Material,
		offset: Vector3) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = material
	node.position = offset
	model.add_child(node)
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
