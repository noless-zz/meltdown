class_name MapFires
extends Node3D

## Burning fire entries on the map hologram (#519, MAP-2, RUN-4). Fire is
## passable, so the map neither blocks it nor routes round it; without a mark a
## pilot following the suggested route could fly into it unwarned.
##
## Each fire is a double cone (an octahedron), a shape no other map marker
## uses: the blocked openings are crosses, the exit a cube, the ship and
## reactor balls. All fires share one mesh surface, so they are one draw call
## however many burn (PRF-2).
##
## A marker spans the fire's own diameter at the map's scale, but never less
## than the look's `fire_size_m`: on a large mine the fit shrinks a fire to a
## dot the eye misses, and a large fire on a small map should still read large.
##
## The points arrive in level space with the fit that moves them into this
## node's space, and the look is handed in by the owner from its look file
## (ARC-4). This node only draws; it holds no simulation object (MP-2).
##
## `inside` keeps only the fires within given boxes, so the owner can hide
## fires in unexplored space when the look's `fires_explored_only` says so (#562).

const MESH_NAME: String = "FireMarkers"
## Vertices of one marker: 8 triangles, no shared vertices.
const VERTICES_PER_MARKER: int = 24

var _mesh_node: MeshInstance3D = MeshInstance3D.new()
var _centres: PackedVector3Array = PackedVector3Array()
var _sizes: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	name = "MapFires"
	_mesh_node.name = MESH_NAME
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)


## Draws one marker at each of `centres_m` (level space) moved by `fit`, sized
## from `radii_m` as the class comment says, with `fire_color`, `fire_size_m`
## and `line_energy` from `look`. A centre with no radius at its index counts
## as radius 0. Empty `centres_m` draws nothing; replaces what was drawn.
func draw_fitted(fit: Transform3D, centres_m: PackedVector3Array, radii_m: PackedFloat32Array,
		look: Dictionary) -> void:
	clear()
	if centres_m.is_empty():
		return
	var scale_fit: float = fit.basis.get_scale().x
	var least: float = float(look["fire_size_m"])
	var vertices: PackedVector3Array = PackedVector3Array()
	for i: int in centres_m.size():
		var radius: float = maxf(float(radii_m[i]), 0.0) if i < radii_m.size() else 0.0
		var size: float = maxf(least, radius * 2.0 * scale_fit)
		var centre: Vector3 = fit * centres_m[i]
		_centres.append(centre)
		_sizes.append(size)
		vertices.append_array(octahedron(centre, size))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _glow(look["fire_color"], float(look["line_energy"])))
	_mesh_node.mesh = mesh


## Removes every fire marker.
func clear() -> void:
	_mesh_node.mesh = null
	_centres = PackedVector3Array()
	_sizes = PackedFloat32Array()


## Number of markers drawn, counted from the mesh itself.
func marker_count() -> int:
	var mesh: ArrayMesh = _mesh_node.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / VERTICES_PER_MARKER


## The markers' centres in this node's space, in the order they were given.
func marker_positions() -> PackedVector3Array:
	return _centres.duplicate()


## Each marker's tip-to-tip span, in the order they were given.
func marker_sizes() -> PackedFloat32Array:
	return _sizes.duplicate()


## The node holding the single mesh, for reading its surfaces and material.
func mesh_node() -> MeshInstance3D:
	return _mesh_node


## The fires of `centres_m` (with their `radii_m`) whose centre lies in one of
## `boxes`, in the order given, as `[centres, radii]`. A missing radius stays 0.
static func inside(centres_m: PackedVector3Array, radii_m: PackedFloat32Array,
		boxes: Array[AABB]) -> Array:
	var centres: PackedVector3Array = PackedVector3Array()
	var radii: PackedFloat32Array = PackedFloat32Array()
	for i: int in centres_m.size():
		for box: AABB in boxes:
			if box.has_point(centres_m[i]):
				centres.append(centres_m[i])
				radii.append(radii_m[i] if i < radii_m.size() else 0.0)
				break
	return [centres, radii]


## Triangles of an octahedron centred on `centre`, `size` from tip to tip.
static func octahedron(centre: Vector3, size: float) -> PackedVector3Array:
	var half: float = size * 0.5
	var tips: Array[Vector3] = [Vector3.RIGHT * half, Vector3.BACK * half, Vector3.LEFT * half,
			Vector3.FORWARD * half]
	var result: PackedVector3Array = PackedVector3Array()
	for pole: Vector3 in [Vector3.UP * half, Vector3.DOWN * half]:
		for i: int in tips.size():
			result.append(centre + pole)
			result.append(centre + tips[i])
			result.append(centre + tips[(i + 1) % tips.size()])
	return result


## Glows only, like the rest of the map, so it reads the same lit or dark.
static func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.metallic_specular = 0.0
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	return material
