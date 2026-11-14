extends XROrigin3D

## Player rig: tracked head camera and two tracked controllers.
##
## Without an XR session the camera keeps its authored height and works as an
## ordinary flat camera. Hands are plain boxes until real models exist; left
## is blue and right is orange so tracking mix-ups are obvious in the headset.

const HAND_SIZE: Vector3 = Vector3(0.06, 0.06, 0.12)
const LEFT_COLOR: Color = Color(0.2, 0.6, 1.0)
const RIGHT_COLOR: Color = Color(1.0, 0.5, 0.2)


func _ready() -> void:
	_add_hand_marker($LeftHand as Node3D, LEFT_COLOR)
	_add_hand_marker($RightHand as Node3D, RIGHT_COLOR)


func _add_hand_marker(hand: Node3D, color: Color) -> void:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = color
	var mesh: BoxMesh = BoxMesh.new()
	mesh.size = HAND_SIZE
	mesh.material = material
	var marker: MeshInstance3D = MeshInstance3D.new()
	marker.name = "Marker"
	marker.mesh = mesh
	hand.add_child(marker)
