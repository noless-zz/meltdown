class_name MapRoute
extends Node3D

## The suggested escape route and the blocked openings on the map hologram
## (MAP-2, #400): the route as a line through its points, and a cross at each
## blocked opening's centre. The points come already in the hologram's space;
## the owner fits them like the wireframe, so this node stays pure drawing.
##
## The route is drawn as thin square bars, not as a line primitive: a line
## primitive is one pixel wide whatever the look says, and one pixel of white
## next to the cyan wireframe is too faint on the headset. The bars of a
## segment are one mesh surface, so the whole route is one draw call (PRF-2).
##
## The look (colours, width, cross size) is handed in by the owner, which reads
## it from its look file (ARC-4); nothing here is tuned in code.

const LINE_NAME: String = "RouteLine"
const BLOCKED_PREFIX: String = "Blocked"
## Vertices of one bar: 6 faces, 2 triangles each, no shared vertices.
const VERTICES_PER_BAR: int = 36
## Segments shorter than this are dropped; a repeated point is not a segment.
const MIN_SEGMENT_M: float = 1e-6

var _line: MeshInstance3D = MeshInstance3D.new()
var _blocked: Array[MeshInstance3D] = []
var _ends: PackedVector3Array = PackedVector3Array()


func _init() -> void:
	name = "MapRoute"
	_line.name = LINE_NAME
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)


## Draws the route through `points` and a cross at each of `blocked`, both in
## this node's space, replacing what was drawn before. `width_m` is the bars'
## thickness and `cross_m` the length of each bar of a cross. Empty arrays
## draw nothing.
func draw(points: PackedVector3Array, blocked: PackedVector3Array, route_color: Color,
		blocked_color: Color, energy: float, width_m: float, cross_m: float) -> void:
	clear()
	for i: int in range(1, points.size()):
		if points[i - 1].distance_to(points[i]) >= MIN_SEGMENT_M:
			_ends.append(points[i - 1])
			_ends.append(points[i])
	if not _ends.is_empty():
		var vertices: PackedVector3Array = PackedVector3Array()
		for i: int in range(0, _ends.size(), 2):
			vertices.append_array(bar(_ends[i], _ends[i + 1], width_m))
		_line.mesh = _mesh(vertices, route_color, energy)
	if blocked.is_empty():
		return
	var cross: ArrayMesh = _mesh(cross_vertices(cross_m, width_m), blocked_color, energy)
	for i: int in blocked.size():
		var marker: MeshInstance3D = MeshInstance3D.new()
		marker.name = "%s%d" % [BLOCKED_PREFIX, i]
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		marker.mesh = cross
		marker.position = blocked[i]
		_blocked.append(marker)
		add_child(marker)


## `draw` with level-space `points_m` and `blocked_m` moved by `fit` into this
## node's space, and the look read from `look` (the map look's `route_color`,
## `blocked_color`, `line_energy`, `route_width_m` and `blocked_size_m`).
func draw_fitted(fit: Transform3D, points_m: PackedVector3Array, blocked_m: PackedVector3Array,
		look: Dictionary) -> void:
	draw(fit * points_m, fit * blocked_m, look["route_color"], look["blocked_color"],
			float(look["line_energy"]), float(look["route_width_m"]), float(look["blocked_size_m"]))


## Removes the route and every blocked marker.
func clear() -> void:
	_line.mesh = null
	_ends = PackedVector3Array()
	for marker: MeshInstance3D in _blocked:
		remove_child(marker)
		marker.free()
	_blocked.clear()


## Number of route segments drawn, counted from the mesh itself.
func segment_count() -> int:
	var mesh: ArrayMesh = _line.mesh as ArrayMesh
	if mesh == null or mesh.get_surface_count() == 0:
		return 0
	return mesh.surface_get_array_len(0) / VERTICES_PER_BAR


## The drawn segments' endpoints as pairs (from, to, from, to, ...).
func segment_ends() -> PackedVector3Array:
	return _ends.duplicate()


## The blocked markers' positions, in the order they were given.
func blocked_positions() -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	for marker: MeshInstance3D in _blocked:
		result.append(marker.position)
	return result


## Triangles of a square bar of thickness `width_m` from `from` to `to`.
static func bar(from: Vector3, to: Vector3, width_m: float) -> PackedVector3Array:
	var along: Vector3 = (to - from).normalized()
	# Any axis not parallel to the bar gives a valid side direction.
	var helper: Vector3 = Vector3.UP if absf(along.y) < 0.9 else Vector3.RIGHT
	var side: Vector3 = along.cross(helper).normalized() * width_m * 0.5
	var up: Vector3 = along.cross(side).normalized() * width_m * 0.5
	var corners: Array[Vector3] = []
	for end: Vector3 in [from, to]:
		corners.append(end - side - up)
		corners.append(end + side - up)
		corners.append(end + side + up)
		corners.append(end - side + up)
	# Quads as corner indices; the material draws both sides, so winding is moot.
	var quads: Array[Array] = [[0, 1, 2, 3], [4, 5, 6, 7], [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7]]
	var result: PackedVector3Array = PackedVector3Array()
	for quad: Array in quads:
		for index: int in [quad[0], quad[1], quad[2], quad[0], quad[2], quad[3]]:
			result.append(corners[index])
	return result


## A cross centred on the origin: four bars of length `size_m` along the
## diagonals of a cube, so it reads as an X from any side the hand turns it to.
static func cross_vertices(size_m: float, width_m: float) -> PackedVector3Array:
	var result: PackedVector3Array = PackedVector3Array()
	var half: float = size_m * 0.5
	for diagonal: Vector3 in [Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(1, -1, 1), Vector3(-1, 1, 1)]:
		var reach: Vector3 = diagonal.normalized() * half
		result.append_array(bar(-reach, reach, width_m))
	return result


static func _mesh(vertices: PackedVector3Array, color: Color, energy: float) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _glow(color, energy))
	return mesh


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
