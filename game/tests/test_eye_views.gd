extends RefCounted

## Each eye's own view (#1507, CMF-8): the shipped file, each bad key named,
## the right eye as the left's mirror, edges read back from a runtime-style
## off-axis projection, and a point one eye cannot see named by eye and edge.
## Presentation only (ARC-3).

const GOOD: String = "{\"ipd_m\": 0.063, \"outward_deg\": 52, \"inward_deg\": 42, \"up_deg\": 44, \"down_deg\": 52, \"edge_margin_deg\": 3}"


func test_the_shipped_file_is_read() -> String:
	var views: EyeViews = EyeViews.load_file()
	if views.error != "":
		return "the shipped file is rejected: %s" % views.error
	if not is_equal_approx(views.origins[EyeViews.RIGHT].x - views.origins[EyeViews.LEFT].x, float(views.values["ipd_m"])):
		return "the eyes sit %s apart" % [views.origins]
	return ""


func test_each_bad_key_names_its_field() -> String:
	var ipd: String = "\"ipd_m\": 0.063,"
	var cases: Dictionary = {
		GOOD.replace(ipd, ""): "missing key \"ipd_m\"",
		GOOD.replace(ipd, "\"ipd_m\": 0.2,"): "\"ipd_m\" is 0.2",
		GOOD.replace(ipd, "\"ipd_m\": true,"): "\"ipd_m\" must be a number",
		GOOD.replace(ipd, ipd + " \"fov\": 90,"): "unknown key \"fov\"",
		GOOD.replace(" \"inward_deg\": 42,", ""): "missing key \"inward_deg\"",
		GOOD.replace("\"up_deg\": 44", "\"up_deg\": 90"): "\"up_deg\" is 90",
		GOOD.replace(", \"edge_margin_deg\": 3", ""): "missing key \"edge_margin_deg\"",
		"[1]": "top level must be a JSON object",
	}
	for text: String in cases:
		var parsed: Dictionary = EyeViews.parse(text)
		if not str(parsed.get("error", "")).begins_with(cases[text]):
			return "%s gave %s, expected %s" % [text, parsed, cases[text]]
	return ""


func test_a_rejected_file_falls_back_and_says_why() -> String:
	var path: String = "user://test_eye_views.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(GOOD.replace("52, \"inward", "5, \"inward"))
	file.close()
	var views: EyeViews = EyeViews.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not views.error.contains("outward_deg"):
		return "the error is \"%s\"" % views.error
	if not is_equal_approx(float(views.values["outward_deg"]), 52.0):
		return "the fallback is %s" % [views.values]
	return ""


func test_the_right_eye_is_the_left_eyes_mirror() -> String:
	var views: EyeViews = EyeViews.from_values(EyeViews.parse(GOOD))
	var left: Rect2 = views.edges[EyeViews.LEFT]
	var right: Rect2 = views.edges[EyeViews.RIGHT]
	if not is_equal_approx(left.position.x, -right.end.x) or not is_equal_approx(left.end.x, -right.position.x):
		return "left %s, right %s" % [left, right]
	if not is_equal_approx(rad_to_deg(atan(left.end.x)), 42.0) or not is_equal_approx(rad_to_deg(atan(left.position.y)), -52.0):
		return "the left eye's edges are %s" % left
	return ""


func test_edges_are_read_back_from_an_off_axis_projection() -> String:
	# As a runtime gives one eye: wider to the outside than towards the nose.
	var near: float = 0.05
	var want: Rect2 = Rect2(-1.2, -1.1, 2.1, 2.0)
	var projection: Projection = Projection.create_frustum(want.position.x * near, want.end.x * near,
		want.position.y * near, want.end.y * near, near, 100.0)
	var got: Rect2 = EyeViews.edges_of(projection)
	if not got.position.is_equal_approx(want.position) or not got.size.is_equal_approx(want.size):
		return "read %s, expected %s" % [got, want]
	return ""


func test_a_point_one_eye_misses_is_named_by_eye_and_edge() -> String:
	var views: EyeViews = EyeViews.from_values(EyeViews.parse(GOOD))
	if views.problem_at(Vector3(0.0, -0.1, -0.5)) != "":
		return "a point ahead and a little down is refused: %s" % views.problem_at(Vector3(0.0, -0.1, -0.5))
	# 41 degrees left of the left eye: inside it, past the right eye's inner edge less the margin.
	var far_left: Vector3 = Vector3(-0.0315 - tan(deg_to_rad(41.0)) * 0.5, 0.0, -0.5)
	var problem: String = views.problem_at(far_left)
	if not problem.begins_with("right eye") or not problem.contains("left edge"):
		return "far left gave \"%s\"" % problem
	var far_right: Vector3 = Vector3(-far_left.x, 0.0, -0.5)
	problem = views.problem_at(far_right)
	if not problem.begins_with("left eye") or not problem.contains("right edge"):
		return "far right gave \"%s\"" % problem
	problem = views.problem_at(Vector3(0.0, -0.75, -0.5))
	if not problem.contains("bottom edge"):
		return "far down gave \"%s\"" % problem
	if not views.problem_at(Vector3(0.0, 0.0, 0.2)).contains("behind"):
		return "a point behind was not refused"
	return ""


func test_no_running_headset_gives_no_runtime_views() -> String:
	if EyeViews.from_interface(null, 3.0) != null:
		return "a missing interface gave views"
	var xr: XRInterface = XRServer.primary_interface
	if (xr == null or not xr.is_initialized()) and EyeViews.from_interface(xr, 3.0) != null:
		return "an interface that is not running gave views"
	return ""
