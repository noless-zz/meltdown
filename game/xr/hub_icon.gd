class_name HubIcon
extends Node3D

## One icon of the home base's set (#1365, CRW-2, GFX-2) drawn as flat shapes
## facing +Z, `size_m` across, centred on the node. It hangs on a station's
## screen like the screen's words, so it is unshaded: its colours are the ones
## the contrast check measured, whatever the room's lights do. The meshes are
## primitives built here and shared between icons, with no image files (ARC-5).
## Each part sits a hair in front of the one before, so a later part shows over
## an earlier one without flicker.

const NODE_NAME: String = "Icon"
## Depth of the flat meshes and the step between parts, in metres.
const THICK_M: float = 0.0004
const LAYER_STEP_M: float = 0.0006
const RING_INNER: float = 0.34
const SEGMENTS: int = 24

static var _meshes: Dictionary[String, Mesh] = {}
static var _materials: Dictionary[Color, StandardMaterial3D] = {}

var size_m: float = 0.0
var _parts: Array[MeshInstance3D] = []


func _init(icon: Dictionary, size: float, layers: int = 1) -> void:
	name = NODE_NAME
	size_m = size
	var parts: Array = icon.get("parts", [])
	for i: int in parts.size():
		var part: Dictionary = parts[i]
		var mesh: MeshInstance3D = MeshInstance3D.new()
		mesh.name = "Part%d" % i
		mesh.mesh = _mesh(part["shape"])
		mesh.material_override = _material(part["color"])
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mesh.layers = layers
		var spread: Vector2 = part["size"] * size
		# A torus's tube is as deep as it is wide; pressed flat to a sheet.
		var depth: float = THICK_M / (0.5 - RING_INNER) if part["shape"] == "ring" else 1.0
		var flat: Basis = Basis.from_scale(Vector3(spread.x, spread.y, depth))
		if part["shape"] in ["disc", "ring"]:
			# Cylinders and tori stand on Y; laid on Z they face the pilot.
			flat = flat * Basis(Vector3.RIGHT, PI * 0.5)
		var turn: Basis = Basis(Vector3.BACK, deg_to_rad(part["turn_deg"]))
		var at: Vector2 = part["at"] * size
		mesh.transform = Transform3D(turn * flat, Vector3(at.x, at.y, LAYER_STEP_M * i))
		add_child(mesh)
		_parts.append(mesh)


func part_count() -> int:
	return _parts.size()


## The colour each part is drawn in, in file order.
func part_colors() -> Array[Color]:
	var found: Array[Color] = []
	for part: MeshInstance3D in _parts:
		found.append((part.material_override as StandardMaterial3D).albedo_color)
	return found


static func _mesh(shape: String) -> Mesh:
	if _meshes.has(shape):
		return _meshes[shape]
	var mesh: Mesh
	match shape:
		"rect":
			var quad: QuadMesh = QuadMesh.new()
			quad.size = Vector2.ONE
			mesh = quad
		"disc":
			var disc: CylinderMesh = CylinderMesh.new()
			disc.top_radius = 0.5
			disc.bottom_radius = 0.5
			disc.height = THICK_M
			disc.radial_segments = SEGMENTS
			disc.rings = 1
			mesh = disc
		"ring":
			var ring: TorusMesh = TorusMesh.new()
			ring.inner_radius = RING_INNER
			ring.outer_radius = 0.5
			ring.rings = SEGMENTS
			ring.ring_segments = 4
			mesh = ring
		_:
			var tri: PrismMesh = PrismMesh.new()
			tri.size = Vector3(1.0, 1.0, THICK_M)
			mesh = tri
	_meshes[shape] = mesh
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	if _materials.has(color):
		return _materials[color]
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[color] = material
	return material
