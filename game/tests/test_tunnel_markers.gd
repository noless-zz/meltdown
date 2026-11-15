extends RefCounted

## The distance markers of the stereo test tunnel must be readable side by
## side from where the player starts (PLT-2). In the first headset session
## the 5 m and 20 m markers were almost in line and hid each other.

const MIN_SEPARATION_DEGREES: float = 3.0
const EXPECTED_DISTANCES: Array[float] = [1.0, 5.0, 20.0]
## The floor origin, as the issue states it, and seated, marker-height and
## standing eye heights above it. The markers hang at eye height, so from the
## floor they are spread vertically even when a headset sees them in line.
const EYE_HEIGHTS: Array[float] = [0.0, 1.2, 1.4, 1.7]


## Positions of `child_path` under every marker ("." for the marker itself),
## in tunnel space. Empty if the tunnel could not be built.
func _marker_points(child_path: String) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var scene: PackedScene = load("res://view/test_tunnel.tscn") as PackedScene
	if scene == null:
		return points
	var tunnel: Node = scene.instantiate()
	tunnel.call("build")
	var markers: Node = tunnel.get_node_or_null("Markers")
	if markers != null:
		for marker: Node3D in markers.get_children():
			var target: Node3D = marker.get_node(child_path) as Node3D
			points.append(marker.position if target == marker else marker.position + target.position)
	tunnel.free()
	return points


## Smallest view angle, in degrees, between any two of `points` seen from `eye`.
func _smallest_angle(points: Array[Vector3], eye: Vector3) -> float:
	var smallest: float = 180.0
	for i: int in points.size():
		for j: int in range(i + 1, points.size()):
			var angle: float = rad_to_deg((points[i] - eye).angle_to(points[j] - eye))
			smallest = minf(smallest, angle)
	return smallest


func _check_separation(child_path: String, what: String) -> String:
	var points: Array[Vector3] = _marker_points(child_path)
	if points.size() != EXPECTED_DISTANCES.size():
		return "expected %d markers, found %d" % [EXPECTED_DISTANCES.size(), points.size()]
	for height: float in EYE_HEIGHTS:
		var angle: float = _smallest_angle(points, Vector3(0.0, height, 0.0))
		if angle < MIN_SEPARATION_DEGREES:
			return "%s are only %.2f degrees apart from eye height %.1f m" % [what, angle, height]
	return ""


func test_markers_are_at_least_three_degrees_apart() -> String:
	return _check_separation(".", "two markers")


func test_marker_labels_are_at_least_three_degrees_apart() -> String:
	return _check_separation("Label", "two labels")


func test_marker_distances_stay_1_5_and_20_metres() -> String:
	var points: Array[Vector3] = _marker_points(".")
	if points.size() != EXPECTED_DISTANCES.size():
		return "expected %d markers, found %d" % [EXPECTED_DISTANCES.size(), points.size()]
	for i: int in points.size():
		if not is_equal_approx(-points[i].z, EXPECTED_DISTANCES[i]):
			return "marker %d is %.2f m down the tunnel, expected %.0f m" % [
				i, -points[i].z, EXPECTED_DISTANCES[i]]
	return ""


func test_smallest_angle_sees_markers_in_line() -> String:
	# The layout of the first headset session: 5 m and 20 m nearly in line.
	var old_layout: Array[Vector3] = [
		Vector3(-0.5, 1.4, -1.0), Vector3(0.0, 1.4, -5.0), Vector3(0.5, 1.4, -20.0)]
	var angle: float = _smallest_angle(old_layout, Vector3(0.0, 1.4, 0.0))
	if angle >= MIN_SEPARATION_DEGREES:
		return "the old layout measures %.2f degrees, so the check would not have caught it" % angle
	return ""
