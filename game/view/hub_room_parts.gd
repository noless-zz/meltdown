class_name HubRoomParts
extends RefCounted

## The meshes, materials and lights of the home base room (#1298), built from
## `HubRoomSpec` values: primitives and physically based materials described
## in text, no image files (ARC-5, GFX-2, NAM-3). Every part is put on
## `layers`, so the camera can show the room and nothing of the mine.

const WALL_THICKNESS_M: float = 0.1
const SCREEN_SIZE_M: Vector3 = Vector3(0.36, 0.24, 0.03)
const PEDESTAL_SIZE_M: Vector2 = Vector2(0.3, 0.22)  # Width and depth.
## The pedestal stops this far under the screen's centre.
const PEDESTAL_GAP_M: float = 0.12
const LABEL_RISE_M: float = 0.18
const LABEL_PIXEL_SIZE: float = 0.0006
const LABEL_FONT_SIZE: int = 40
const LABEL_COLOR: Color = Color(0.85, 0.95, 1.0)


static func material(look: Dictionary) -> StandardMaterial3D:
	var made: StandardMaterial3D = StandardMaterial3D.new()
	made.albedo_color = look["color"]
	made.metallic = look["metallic"]
	made.roughness = look["roughness"]
	if float(look["emission_energy"]) > 0.0:
		made.emission_enabled = true
		made.emission = look["emission"]
		made.emission_energy_multiplier = look["emission_energy"]
	return made


## A primitive mesh of `shape` (one of `HubRoomSpec.SHAPES`) filling `size`.
static func mesh(shape: String, size: Vector3) -> PrimitiveMesh:
	match shape:
		"cylinder":
			var cylinder: CylinderMesh = CylinderMesh.new()
			cylinder.top_radius = size.x * 0.5
			cylinder.bottom_radius = size.x * 0.5
			cylinder.height = size.y
			return cylinder
		"sphere":
			var sphere: SphereMesh = SphereMesh.new()
			sphere.radius = size.x * 0.5
			sphere.height = size.y
			return sphere
		"capsule":
			var capsule: CapsuleMesh = CapsuleMesh.new()
			capsule.radius = size.x * 0.5
			capsule.height = maxf(size.y, size.x)
			return capsule
		"prism":
			var prism: PrismMesh = PrismMesh.new()
			prism.size = size
			return prism
	var box: BoxMesh = BoxMesh.new()
	box.size = size
	return box


static func part(part_name: String, shape: String, size: Vector3, at: Transform3D, look: Material,
		layers: int) -> MeshInstance3D:
	var instance: MeshInstance3D = MeshInstance3D.new()
	instance.name = part_name
	instance.mesh = mesh(shape, size)
	instance.material_override = look
	instance.transform = at
	instance.layers = layers
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # GFX-4: headlight shadows only.
	return instance


## The floor, ceiling and four walls as thin boxes around the room's inside.
static func shell(spec: HubRoomSpec, looks: Dictionary, layers: int) -> Array[MeshInstance3D]:
	var floor_y: float = -spec.eye_height
	var mid: Vector3 = Vector3(spec.centre.x, floor_y + spec.size.y * 0.5, spec.centre.y)
	var half: Vector3 = spec.size * 0.5 + Vector3.ONE * WALL_THICKNESS_M * 0.5
	var t: float = WALL_THICKNESS_M
	var w: Vector3 = spec.size + Vector3.ONE * t * 2.0
	var walls: Material = looks[spec.surfaces["walls"]]
	return [
		part("Floor", "box", Vector3(w.x, t, w.z), Transform3D(Basis(), mid - Vector3(0, half.y, 0)),
			looks[spec.surfaces["floor"]], layers),
		part("Ceiling", "box", Vector3(w.x, t, w.z), Transform3D(Basis(), mid + Vector3(0, half.y, 0)),
			looks[spec.surfaces["ceiling"]], layers),
		part("WallLeft", "box", Vector3(t, w.y, w.z), Transform3D(Basis(), mid - Vector3(half.x, 0, 0)), walls, layers),
		part("WallRight", "box", Vector3(t, w.y, w.z), Transform3D(Basis(), mid + Vector3(half.x, 0, 0)), walls, layers),
		part("WallFront", "box", Vector3(w.x, w.y, t), Transform3D(Basis(), mid - Vector3(0, 0, half.z)), walls, layers),
		part("WallBack", "box", Vector3(w.x, w.y, t), Transform3D(Basis(), mid + Vector3(0, 0, half.z)), walls, layers),
	]


static func light(index: int, data: Dictionary, layers: int) -> OmniLight3D:
	var made: OmniLight3D = OmniLight3D.new()
	made.name = "Light%d" % index
	made.position = data["position"]
	made.light_color = data["color"]
	made.light_energy = data["energy"]
	made.omni_range = data["range"]
	made.shadow_enabled = false  # GFX-4: shadows from the player's headlight only.
	made.light_cull_mask = layers  # The room's lights never light the mine.
	return made


## A station: a pedestal from the floor, a screen at the station's point
## turned to face the eye, and its name above. Named `Station_<id>`.
static func station(spec: HubRoomSpec, data: Dictionary, looks: Dictionary, layers: int) -> Node3D:
	var node: Node3D = Node3D.new()
	node.name = "Station_%s" % data["id"]
	var at: Vector3 = data["position"]
	node.position = at
	var to_eye: Vector3 = -at
	to_eye.y = 0.0
	if to_eye.length() > 0.001:
		node.basis = Basis.looking_at(-to_eye)  # Its back to the eye, so +z faces the pilot.
	var screen_basis: Basis = Basis(Vector3.RIGHT, deg_to_rad(-35.0))  # Tilted up towards a seated eye.
	node.add_child(part("Screen", "box", SCREEN_SIZE_M, Transform3D(screen_basis, Vector3.ZERO),
		looks[data["screen"]], layers))
	var pedestal_top: float = -PEDESTAL_GAP_M
	var pedestal_bottom: float = -spec.eye_height - at.y
	var height: float = maxf(pedestal_top - pedestal_bottom, 0.05)
	node.add_child(part("Pedestal", "box", Vector3(PEDESTAL_SIZE_M.x, height, PEDESTAL_SIZE_M.y),
		Transform3D(Basis(), Vector3(0.0, pedestal_bottom + height * 0.5, 0.0)), looks[data["console"]], layers))
	var label: Label3D = Label3D.new()
	label.name = "Label"
	label.text = data["label"]
	label.pixel_size = LABEL_PIXEL_SIZE
	label.font_size = LABEL_FONT_SIZE
	label.modulate = LABEL_COLOR
	label.shaded = false
	label.layers = layers
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	label.position = Vector3(0.0, LABEL_RISE_M, 0.0)  # Reads from +z, the pilot's side.
	node.add_child(label)
	return node
