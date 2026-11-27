class_name AimRay
extends Node3D

## A thin ray from the pointing controller's aim pose to what it points at,
## with a dot where it lands (#1451, CRW-2, RUN-1, PLT-5). It shows only where
## pointing selects (the home base's stations and the shaft choice, found by
## `AimTargets`) and never in flight. With nothing hit it reaches `length_m`
## and fades out to its tip.
##
## It starts at the same pose the selection reads (the right controller's,
## as `HubWiring` and `ShaftChoiceWiring` aim), so hand, ray and highlight
## agree. Its look is data (`AimRaySpec`, ARC-4). It is drawn on the hands
## layer so the home base's camera shows it, and above the fade so it shows at
## the shaft choice; it never moves the view, never flashes, and reads no comfort
## setting, so it is the same on every preset (ARC-3, CMF-8). It writes nothing
## but its own nodes (MP-2).

const NODE_NAME: String = "AimRay"
## The top, as the shaft panel's words: above the fade quad (one below it).
const RENDER_PRIORITY: int = Material.RENDER_PRIORITY_MAX

var spec: AimRaySpec = null
var targets: AimTargets = AimTargets.new()

var _ray: MeshInstance3D = null
var _dot: MeshInstance3D = null
var _solid: ArrayMesh = null
var _fading: ArrayMesh = null
var _length: float = 0.0


func _init(p_spec: AimRaySpec = null) -> void:
	name = NODE_NAME
	spec = p_spec if p_spec != null else AimRaySpec.load_file()
	if spec.error != "":
		push_warning("the aim ray uses built-in values: %s" % spec.error)
		spec = AimRaySpec.new()
	var material: StandardMaterial3D = _material(spec.color)
	material.vertex_color_use_as_albedo = true
	_solid = _beam(1.0)
	_fading = _beam(0.0)
	_ray = _part("Ray", _solid, material)
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 12
	sphere.rings = 6
	_dot = _part("Dot", sphere, _material(spec.dot_color))
	_dot.scale = Vector3.ONE * spec.dot_size_m
	visible = false


## Shows the ray for the aim pose `aim` (in the rig's space, the rig being this
## node's parent) when `tracked`, or hides it. Called once per frame by the rig.
func follow(rig: Node, aim: Transform3D, tracked: bool) -> void:
	var found: Dictionary = targets.find(rig, aim) if tracked else {"shown": false, "hit": null}
	if not bool(found["shown"]):
		hide_ray()
		return
	show_from(aim, found["hit"])


## Draws the ray from `aim`'s origin along its -Z to `hit` (a point in the
## parent's space) with the dot there, or, for null, at full length fading out.
func show_from(aim: Transform3D, hit: Variant) -> void:
	var direction: Vector3 = -aim.basis.z.normalized()
	var up: Vector3 = Vector3.UP if absf(direction.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	transform = Transform3D(Basis.looking_at(direction, up), aim.origin)
	var landed: bool = hit is Vector3
	_length = ((hit as Vector3) - aim.origin).length() if landed else spec.length_m
	_ray.mesh = _solid if landed else _fading
	_ray.scale = Vector3(spec.width_m, spec.width_m, maxf(_length, 0.001))
	_dot.position = Vector3(0.0, 0.0, -_length)
	_dot.visible = landed
	visible = true


func hide_ray() -> void:
	visible = false
	_dot.visible = false


## Where the ray ends now, in the parent's space.
func end_point() -> Vector3:
	return transform * Vector3(0.0, 0.0, -_length)


## True while the ray shows and lands on something.
func shows_dot() -> bool:
	return visible and _dot.visible


## A unit beam along -Z, `width` 1, whose far end has `tip_alpha` of the colour.
static func _beam(tip_alpha: float) -> ArrayMesh:
	var corners: Array[Vector2] = [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]
	var vertices: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	for side: int in 4:
		var a: Vector2 = corners[side]
		var b: Vector2 = corners[(side + 1) % 4]
		var near_a: Vector3 = Vector3(a.x, a.y, 0.0)
		var near_b: Vector3 = Vector3(b.x, b.y, 0.0)
		var far_a: Vector3 = Vector3(a.x, a.y, -1.0)
		var far_b: Vector3 = Vector3(b.x, b.y, -1.0)
		for corner: Vector3 in [near_a, far_a, far_b, near_a, far_b, near_b]:
			vertices.append(corner)
			colors.append(Color(1.0, 1.0, 1.0, 1.0 if corner.z == 0.0 else tip_alpha))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _part(part_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var node: MeshInstance3D = MeshInstance3D.new()
	node.name = part_name
	node.mesh = mesh
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.layers = 1 | HubRoom.HANDS_LAYER_BIT
	add_child(node)
	return node


static func _material(color: Color) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.render_priority = RENDER_PRIORITY
	material.albedo_color = color
	return material
