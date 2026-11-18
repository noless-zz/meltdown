class_name MapShapes
extends RefCounted

## The map hologram's shared geometry: the fit from level space into the
## hologram, the glow-only material and the small marker ball. Split out of
## `MapHologram` (#519) so the node stays under the size limit as it gains
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


## A small glowing ball; a dot this small needs few triangles (PRF-2).
static func ball(color: Color, radius: float, energy: float) -> SphereMesh:
	var sphere: SphereMesh = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 8
	sphere.rings = 4
	sphere.material = glow(color, energy)
	return sphere
