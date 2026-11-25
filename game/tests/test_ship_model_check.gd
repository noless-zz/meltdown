extends RefCounted

## The `ship_model` acceptance check (#1362, DEV-6): passes the shipped look
## and records its cost, fails a refused look or a dead engine, and poses the
## ship nose-on and side-on to the camera for the screenshots.

const Check := preload("res://acceptance/checks/ship_model_check.gd")


func test_the_shipped_look_passes_and_records_its_cost() -> String:
	var measurements: Dictionary = {}
	var verdict: Array = Check.judge_look(ShipLook.load_file(), measurements)
	if verdict[0] != AcceptanceReport.RESULT_PASS:
		return "verdict %s" % [verdict]
	for key: String in ["ship_draw_calls", "ship_triangles", "ship_materials", "ship_lights"]:
		if not measurements.has(key):
			return "no %s in %s" % [key, measurements]
	return ""


func test_a_refused_look_fails() -> String:
	var look: ShipLook = ShipLook.new()
	look.use({"pieces": 3})
	var verdict: Array = Check.judge_look(look, {})
	if verdict[0] != AcceptanceReport.RESULT_FAIL or not str(verdict[1]).contains("refused"):
		return "verdict %s" % [verdict]
	return ""


func test_the_front_pose_points_the_nose_at_the_eye() -> String:
	var eye: Transform3D = Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.0, 2.0, 3.0))
	var pose: Transform3D = Check.pose_before(eye, false, 4.0)
	var nose: Vector3 = -pose.basis.z
	var to_eye: Vector3 = (eye.origin - pose.origin).normalized()
	if not is_equal_approx(eye.origin.distance_to(pose.origin), 4.0):
		return "the ship hangs %.2f m away" % eye.origin.distance_to(pose.origin)
	return "" if nose.dot(to_eye) > 0.99 else "the nose points %s, the eye is towards %s" % [nose, to_eye]


func test_the_side_pose_shows_the_ship_across_the_view() -> String:
	var eye: Transform3D = Transform3D(Basis(Vector3.UP, -1.1), Vector3.ZERO)
	var pose: Transform3D = Check.pose_before(eye, true, 4.0)
	var nose: Vector3 = -pose.basis.z
	return "" if nose.dot(eye.basis.x) > 0.99 else "the nose points %s, not to the eye's right" % nose
