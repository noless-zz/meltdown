extends RefCounted

## The ship marker on the held map is a dart that turns with the ship (#679,
## MAP-1, NAM-3, ARC-4): its basis follows the ship's orientation, its nose
## points along the ship's forward, its top side along the ship's up, it is
## sized from the look file and in the marker colour.

const EPSILON: float = 0.01


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


func _built() -> MapHologram:
	var map: MapHologram = MapHologram.new()
	var explored: Array[int] = [0]
	map.build(_one_box(), explored)
	return map


## Yaw 90°, pitch 45°, roll 90°, applied in that order in the ship's own axes.
func _turned() -> Basis:
	var basis: Basis = Basis.IDENTITY
	basis = basis.rotated(basis.y, deg_to_rad(90.0))
	basis = basis.rotated(basis.x.normalized(), deg_to_rad(45.0))
	basis = basis.rotated(basis.z.normalized(), deg_to_rad(90.0))
	return basis


func _marker_basis(map: MapHologram) -> Basis:
	return (map.get_node(MapHologram.MARKER_NAME) as Node3D).basis


func _basis_close(a: Basis, b: Basis) -> bool:
	return (a.x - b.x).length() < EPSILON and (a.y - b.y).length() < EPSILON \
		and (a.z - b.z).length() < EPSILON


func test_marker_basis_follows_the_ship_orientation() -> String:
	var map: MapHologram = _built()
	var ship: Basis = _turned()
	map.set_ship_orientation(ship)
	var got: Basis = _marker_basis(map)
	map.free()
	if not _basis_close(got, ship):
		return "marker basis %s, ship %s" % [got, ship]
	return ""


func test_nose_points_along_the_ship_forward_and_fin_along_up() -> String:
	var map: MapHologram = _built()
	var ship: Basis = _turned()
	map.set_ship_orientation(ship)
	var nose: Vector3 = _marker_basis(map) * MapShipMarker.NOSE
	var top: Vector3 = _marker_basis(map) * MapShipMarker.TOP
	map.free()
	var forward: Vector3 = -ship.z
	if (nose - forward).length() > EPSILON:
		return "nose %s, ship forward %s" % [nose, forward]
	if (top - ship.y).length() > EPSILON:
		return "top %s, ship up %s" % [top, ship.y]
	return ""


func test_marker_keeps_turning_with_later_orientations() -> String:
	var map: MapHologram = _built()
	map.set_ship_orientation(_turned())
	map.set_ship_orientation(Basis.IDENTITY)
	var got: Basis = _marker_basis(map)
	map.set_zoom(2.0)
	var zoomed: Basis = _marker_basis(map)
	map.free()
	if not _basis_close(got, Basis.IDENTITY):
		return "after resetting, marker basis %s" % got
	if not _basis_close(zoomed, Basis.IDENTITY):
		return "zoom changed the marker basis to %s" % zoomed
	return ""


func test_shape_has_one_sharp_nose_ahead_and_a_fin_only_on_top() -> String:
	var points: PackedVector3Array = MapShipMarker.points(1.0)
	var foremost: Vector3 = points[0]
	var highest: float = -INF
	var lowest: float = INF
	for point: Vector3 in points:
		if point.dot(MapShipMarker.NOSE) > foremost.dot(MapShipMarker.NOSE):
			foremost = point
		highest = maxf(highest, point.dot(MapShipMarker.TOP))
		lowest = minf(lowest, point.dot(MapShipMarker.TOP))
	if absf(foremost.x) > EPSILON or absf(foremost.y) > EPSILON:
		return "foremost point %s is not on the centre line" % foremost
	# The fin must rise clearly further above the wings than the keel hangs below,
	# or the top and bottom sides would read alike.
	if highest < 2.0 * absf(lowest):
		return "top reaches %.2f, bottom %.2f: the sides look alike" % [highest, lowest]
	if points.size() % 3 != 0 or points.size() > 60:
		return "%d points: not a small triangle list" % points.size()
	return ""


func test_marker_is_sized_from_the_look_and_in_the_marker_colour() -> String:
	var map: MapHologram = _built()
	var mesh: ArrayMesh = map.get_node(MapHologram.MARKER_NAME).mesh as ArrayMesh
	var look: Dictionary = map.look()
	map.free()
	if mesh == null:
		return "the marker is not a dart mesh"
	var span: AABB = mesh.get_aabb()
	var want: float = MapShipMarker.length_for(float(look["marker_radius_m"]))
	if absf(span.size.z - want) > 1e-5:
		return "dart length %.4f, want %.4f from the look" % [span.size.z, want]
	var material: StandardMaterial3D = mesh.surface_get_material(0) as StandardMaterial3D
	if material == null or not material.emission.is_equal_approx(look["marker_color"]):
		return "marker material is not in the marker colour"
	if material.cull_mode != BaseMaterial3D.CULL_DISABLED:
		return "a single-sheet dart must render both faces"
	return ""
