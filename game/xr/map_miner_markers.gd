class_name MapMinerMarkers
extends Node3D

## Trapped miners on the map hologram while the mine scanner is fitted (#1072,
## CRF-5, SLV-3, MAP-1). `MapWiring` picks the miners within the scanner's
## radius; this node only draws them.
##
## Each miner is a square pyramid standing on its point, like a map pin, a
## shape no other map marker uses: the exit is a cube, the ship a dart, the
## reactor a ball, blocked openings crosses and fires double cones. All markers
## share one mesh surface, so they are one draw call however many (PRF-2). A
## marker keeps the look's `miner_size_m` whatever the map's scale, so a miner
## on a large mine still shows.
##
## Positions arrive in level space with the fit that moves them into this
## node's space, and the colour and size come from the map look file (ARC-4).
## It holds no simulation object (MP-2).

const NODE_NAME: String = "MapMinerMarkers"
const MESH_NAME: String = "MinerMarkers"
## Vertices of one marker: four sides and a two-triangle top, no shared vertices.
const VERTICES_PER_MARKER: int = 18

## The miners to mark, level space; `draw_fitted` draws them.
var at_m: PackedVector3Array = PackedVector3Array()

var _mesh_node: MeshInstance3D = MeshInstance3D.new()
var _centres: PackedVector3Array = PackedVector3Array()


func _init() -> void:
	name = NODE_NAME
	_mesh_node.name = MESH_NAME
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)


## Draws one marker at each of `at_m` moved by `fit`, with `miner_color`,
## `miner_size_m` and `line_energy` from `look`. Empty `at_m` draws nothing;
## replaces what was drawn.
func draw_fitted(fit: Transform3D, look: Dictionary) -> void:
	_mesh_node.mesh = null
	_centres = PackedVector3Array()
	if at_m.is_empty():
		return
	var size: float = float(look["miner_size_m"])
	var vertices: PackedVector3Array = PackedVector3Array()
	for at: Vector3 in at_m:
		var centre: Vector3 = fit * at
		_centres.append(centre)
		vertices.append_array(pin(centre, size))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material: StandardMaterial3D = MapShapes.glow(look["miner_color"], float(look["line_energy"]))
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_set_material(0, material)
	_mesh_node.mesh = mesh


## Number of markers drawn, counted from the mesh itself.
func marker_count() -> int:
	var mesh: ArrayMesh = _mesh_node.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / VERTICES_PER_MARKER


## The markers' positions in this node's space, in the order they were given.
func marker_positions() -> PackedVector3Array:
	return _centres.duplicate()


## The node holding the single mesh, for reading its surface and material.
func mesh_node() -> MeshInstance3D:
	return _mesh_node


## Triangles of a square pyramid `size` tall and wide, its point at `centre`'s
## bottom and its square top at `centre`'s top, so `centre` is its middle.
static func pin(centre: Vector3, size: float) -> PackedVector3Array:
	var half: float = size * 0.5
	var tip: Vector3 = centre + Vector3.DOWN * half
	var corners: Array[Vector3] = [Vector3(half, half, half), Vector3(half, half, -half),
			Vector3(-half, half, -half), Vector3(-half, half, half)]
	var result: PackedVector3Array = PackedVector3Array()
	for i: int in corners.size():
		result.append(tip)
		result.append(centre + corners[i])
		result.append(centre + corners[(i + 1) % corners.size()])
	for triangle: Array in [[0, 1, 2], [0, 2, 3]]:
		for corner: int in triangle:
			result.append(centre + corners[corner])
	return result
