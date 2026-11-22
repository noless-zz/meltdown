class_name MapShapes
extends RefCounted

## The map hologram's shared geometry: the fit from level space into the
## hologram, the glow-only material, the exit cube and the reactor marker.
## Split out of `MapHologram` (#519) so the node stays under the size limit as it gains
## marker kinds.


## Level space -> hologram space: the uniform scale and centring that
## `MapWireframe.fit_to_cube(points, edge_m)` applies to `points`.
static func fit_transform(points: PackedVector3Array, edge_m: float) -> Transform3D:
	if points.is_empty():
		return Transform3D.IDENTITY
	var low: Vector3 = points[0]
	var high: Vector3 = points[0]
	for point: Vector3 in points:
		low = low.min(point)
		high = high.max(point)
	var centre: Vector3 = (low + high) * 0.5
	var longest: float = (high - low)[(high - low).max_axis_index()]
	var scale: float = edge_m / longest if longest > MapWireframe.EPSILON_M else 1.0
	return Transform3D(Basis.from_scale(Vector3.ONE * scale), -centre * scale)


## A black, non-reflective material that only glows, so the map reads the same
## in a lit room or a dark tunnel.
static func glow(color: Color, energy: float) -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.BLACK
	material.metallic_specular = 0.0
	material.roughness = 1.0
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	return material


## Render priority of the reactor marker: above the see-through exit cube's 0, so
## where the two overlap the reactor is drawn last, over the cube (#913).
const REACTOR_PRIORITY: int = 1


## The exit marker: a cube of edge `2 * exit_radius_m`, as before #913, but
## see-through with opacity `exit_alpha` and unshaded, so the lines and the
## tunnel beside it show through and it never writes depth over them.
static func exit_cube(look: Dictionary) -> BoxMesh:
	var cube: BoxMesh = BoxMesh.new()
	cube.size = Vector3.ONE * float(look["exit_radius_m"]) * 2.0
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	var color: Color = look["exit_color"]
	material.albedo_color = Color(color.r, color.g, color.b, float(look["exit_alpha"]))
	cube.material = material
	return cube


## Height of the reactor marker as a multiple of the look's `reactor_radius_m`:
## the diamond is half as wide as it is tall, so at three radii it is about as
## wide as the old ball and taller, which shows its points (#1219).
const REACTOR_HEIGHT_PER_RADIUS: float = 3.0


## The reactor marker in the look's `reactor_shape`: `reactor_color`, or
## `reactor_dead_color` once it is destroyed. It ignores depth and draws after
## the exit cube, so the exit never hides it however close the two sit (#913).
static func reactor_marker(look: Dictionary, destroyed: bool, energy: float) -> ArrayMesh:
	var color: Color = look["reactor_dead_color"] if destroyed else look["reactor_color"]
	var material: StandardMaterial3D = glow(color, energy)
	material.no_depth_test = true
	material.render_priority = REACTOR_PRIORITY
	var height: float = float(look["reactor_radius_m"]) * REACTOR_HEIGHT_PER_RADIUS
	return MapMarkerShapes.mesh(look["reactor_shape"], height, material)


## The explored outline `points` (segment pairs, level space) fitted into a cube
## of `edge_m` as one glowing line mesh in the look's line colour; null when there
## is nothing explored (moved here from `MapHologram.build`, #1120).
static func outline(points: PackedVector3Array, edge_m: float, look: Dictionary) -> ArrayMesh:
	if points.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = MapWireframe.fit_to_cube(points, edge_m)
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	mesh.surface_set_material(0, glow(look["line_color"], float(look["line_energy"])))
	return mesh
