class_name MapMinerMarkers
extends Node3D

## Trapped miners on the map hologram while the mine scanner is fitted (#1072,
## CRF-5, SLV-3, MAP-1). `MapWiring` picks the miners within the scanner's
## radius; this node only draws them.
##
## Each miner is drawn in the look's `miner_shape`, a square pyramid standing
## on its point like a map pin unless the file says otherwise (`MapMarkerShapes`).
## `MapLook` lets no other marker name the same shape (#1219): the exit is a
## cube, the ship a dart, the reactor a diamond, blocked openings crosses and
## fires flames. All markers share one mesh surface, so they are one draw call
## however many (PRF-2). A marker keeps the look's `miner_size_m` whatever the
## map's scale, so a miner on a large mine still shows.
##
## Positions arrive in level space with the fit that moves them into this
## node's space, and the colour and size come from the map look file (ARC-4).
## It holds no simulation object (MP-2).

const NODE_NAME: String = "MapMinerMarkers"
const MESH_NAME: String = "MinerMarkers"

## The miners to mark, level space; `draw_fitted` draws them.
var at_m: PackedVector3Array = PackedVector3Array()

var _mesh_node: MeshInstance3D = MeshInstance3D.new()
var _centres: PackedVector3Array = PackedVector3Array()
var _vertices_per_marker: int = 1


func _init() -> void:
	name = NODE_NAME
	_mesh_node.name = MESH_NAME
	_mesh_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mesh_node)


## Draws one marker at each of `at_m` moved by `fit`, with `miner_color`,
## `miner_size_m`, `miner_shape` (a pin when absent) and `line_energy` from
## `look`. Empty `at_m` draws nothing; replaces what was drawn.
func draw_fitted(fit: Transform3D, look: Dictionary) -> void:
	_mesh_node.mesh = null
	_centres = PackedVector3Array()
	if at_m.is_empty():
		return
	var size: float = float(look["miner_size_m"])
	var shape: String = str(look.get("miner_shape", MapMarkerShapes.PIN))
	if not MapMarkerShapes.NAMES.has(shape):
		shape = MapMarkerShapes.PIN
	_vertices_per_marker = MapMarkerShapes.VERTICES[shape]
	var vertices: PackedVector3Array = PackedVector3Array()
	for at: Vector3 in at_m:
		var centre: Vector3 = fit * at
		_centres.append(centre)
		vertices.append_array(MapMarkerShapes.triangles(shape, centre, size))
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
	return mesh.surface_get_array_len(0) / _vertices_per_marker


## The markers' positions in this node's space, in the order they were given.
func marker_positions() -> PackedVector3Array:
	return _centres.duplicate()


## The node holding the single mesh, for reading its surface and material.
func mesh_node() -> MeshInstance3D:
	return _mesh_node
