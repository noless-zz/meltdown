extends RefCounted

## The status panel back in its corner and out of the middle of the view
## (#1452). The owner saw it drift to the centre: the tally lines of #1356 sit
## on top of the panel, and in the old bottom corner they reached the eye
## line, and a store with no saved choice gave the centre place instead of
## the bottom-left corner #1321 kept as the default.
##
## The panel is projected from the eye point of each cockpit file with every
## row it may draw filled in: its centre must stay outside a cone around
## straight ahead and its rows outside a narrower one, on every cockpit, in
## every corner (`StatusPanelBounds`). Since #1507 the whole panel must also
## lie inside both eyes' views (`EyeViews`), and stay put in the view however
## the ship turns. Presentation only (ARC-3).

const PATH: String = "user://test_status_panel_place.json"
const COCKPIT_DIR: String = "res://xr/cockpits"
## The rows still need only a glance and a small turn of the head.
const VIEW_LIMIT_DEG: float = 50.0


func _cockpit_files() -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(COCKPIT_DIR):
		if file.ends_with(".json"):
			files.append("%s/%s" % [COCKPIT_DIR, file])
	files.sort()
	return files


## The nearest and farthest angle off straight ahead of `points` on a panel in
## `corner`, seen from the eye point of a cockpit placed at `cockpit`.
static func _angles(points: Array[Vector3], corner: String, cockpit: Transform3D) -> Vector2:
	PanelCorner.current = corner
	return StatusPanelBounds.angles(points, StatusPanel.rig_transform(cockpit), cockpit)


func test_a_fresh_install_puts_the_panel_bottom_left() -> String:
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	var store: PanelCorner = PanelCorner.new(PATH)
	store.load_saved()
	var current: String = PanelCorner.current
	PanelCorner.current = PanelCorner.DEFAULT_CORNER
	if PanelCorner.DEFAULT_CORNER != "bottom_left":
		return "the default corner is %s" % PanelCorner.DEFAULT_CORNER
	if store.corner() != "bottom_left" or current != "bottom_left":
		return "no saved choice gave %s (in use %s)" % [store.corner(), current]
	return ""


func test_no_corner_reaches_the_middle_of_the_view_on_any_cockpit() -> String:
	var files: Array[String] = _cockpit_files()
	if files.size() < 4:
		return "expected the four cockpit files, found %s" % [files]
	var panel: StatusPanel = StatusPanel.new()
	var points: Array[Vector3] = StatusPanelBounds.drawn_points(panel)
	panel.free()
	# Turned and moved, as after a recentre in a turned seat.
	var cockpit: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, 1.2, -0.4))
	var message: String = ""
	for file: String in files:
		var spec: CockpitSpec = CockpitSpec.load_file(file)
		if spec == null or spec.error != "":
			message = "%s is rejected" % file
			break
		for corner: String in StatusPanelLook.CORNER_NAMES:
			var angles: Vector2 = _angles(points, corner, cockpit)
			PanelCorner.current = corner
			var centre: float = StatusPanelBounds.centre_angle(StatusPanel.rig_transform(cockpit), cockpit)
			if centre < StatusPanelBounds.CENTRAL_CONE_DEG and message == "":
				message = "%s, %s: the panel's centre is %.1f degrees from straight ahead" % [
					file.get_file(), corner, centre]
			if angles.x < StatusPanelBounds.ROW_CONE_DEG and message == "":
				message = "%s, %s: the panel comes %.1f degrees from straight ahead" % [
					file.get_file(), corner, angles.x]
			if angles.y > VIEW_LIMIT_DEG and message == "":
				message = "%s, %s: a row is %.1f degrees off ahead" % [file.get_file(), corner, angles.y]
	PanelCorner.current = PanelCorner.DEFAULT_CORNER
	return message


func test_every_corner_lies_inside_both_eyes_on_every_cockpit() -> String:
	var files: Array[String] = _cockpit_files()
	var views: EyeViews = EyeViews.load_file()
	if views.error != "":
		return "the shipped eye views are rejected: %s" % views.error
	var panel: StatusPanel = StatusPanel.new()
	var points: Array[Vector3] = StatusPanelBounds.drawn_points(panel)
	panel.free()
	var cockpit: Transform3D = Transform3D(Basis(Vector3.UP, 0.7), Vector3(0.3, 1.2, -0.4))
	var message: String = ""
	for file: String in files:
		var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.load_file(file))
		for corner: String in PanelCorner.names():
			PanelCorner.current = corner
			var placed: StatusPanel = StatusPanel.new()
			RigViews.place_at(cockpit, frame, placed)
			var problem: String = StatusPanelBounds.eyes_problem(points, placed.transform, frame.transform, views)
			placed.free()
			# The centre place is the old one below the eye, kept for the dev menu.
			if problem != "" and corner != PanelCorner.CENTRE and message == "":
				message = "%s, %s: %s" % [file.get_file(), corner, problem]
		frame.free()
	PanelCorner.current = PanelCorner.DEFAULT_CORNER
	return message


func test_turning_or_rolling_the_ship_keeps_the_panel_still_in_the_view() -> String:
	var panel: StatusPanel = StatusPanel.new()
	var points: Array[Vector3] = StatusPanelBounds.drawn_points(panel)
	var views: EyeViews = EyeViews.load_file()
	var message: String = ""
	for corner: String in StatusPanelLook.CORNER_NAMES:
		PanelCorner.current = corner
		var seen: Array[Vector3] = []
		# Level, yawed, rolled, pitched and all three, far from the origin.
		var poses: Array[Transform3D] = [Transform3D.IDENTITY,
			Transform3D(Basis(Vector3.UP, 1.9), Vector3(4.0, 0.0, -2.0)),
			Transform3D(Basis(Vector3.FORWARD, 2.6), Vector3(0.0, 3.0, 1.0)),
			Transform3D(Basis(Vector3.RIGHT, -1.2), Vector3(-1.0, 1.5, 0.0)),
			Transform3D(Basis.from_euler(Vector3(0.8, -2.2, 1.4)), Vector3(9.0, -4.0, 7.0))]
		for pose: Transform3D in poses:
			RigViews.place_at(pose, null, panel)
			var into: Transform3D = pose.affine_inverse() * panel.transform
			if seen.is_empty():
				for point: Vector3 in points:
					seen.append(into * point)
			for index: int in points.size():
				if (into * points[index]).distance_to(seen[index]) > 0.0005 and message == "":
					message = "%s: the panel moved in the view at ship pose %s" % [corner, pose]
			var problem: String = StatusPanelBounds.eyes_problem(points, panel.transform, pose, views)
			if problem != "" and message == "":
				message = "%s at ship pose %s: %s" % [corner, pose, problem]
	PanelCorner.current = PanelCorner.DEFAULT_CORNER
	panel.free()
	return message


func test_the_panel_is_fixed_to_the_cockpit_and_a_new_corner_moves_it() -> String:
	var cockpit: Transform3D = Transform3D(Basis(Vector3.RIGHT, 0.3), Vector3(0.0, 1.1, 0.2))
	var panel: StatusPanel = StatusPanel.new()
	PanelCorner.current = "bottom_left"
	RigViews.place_at(cockpit, null, panel)
	var left: Transform3D = panel.transform
	var expected: Transform3D = cockpit * StatusPanelLook.placement(StatusPanelLook.shared(), "bottom_left")
	PanelCorner.current = "top_right"
	RigViews.place_at(cockpit, null, panel)
	var right: Transform3D = panel.transform
	PanelCorner.current = PanelCorner.DEFAULT_CORNER
	panel.free()
	if not left.is_equal_approx(expected):
		return "bottom left placed at %s, expected %s" % [left, expected]
	if right.origin.distance_to(left.origin) < 0.1:
		return "choosing top_right moved the panel only %.3f m" % right.origin.distance_to(left.origin)
	return ""
