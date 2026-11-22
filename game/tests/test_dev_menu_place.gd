extends RefCounted

## Where the dev menu opens (#1206, PLT-5, CMF-8, ARC-4): centred 1 m along
## the head's forward direction with its middle row there, facing the head and
## upright, the distance and offset from `dev_menu.json`; world-locked after
## it opens; and in front of nothing the status panel draws, at every corner.

const TOLERANCE_M: float = 0.05
## Half the status panel's size, generously: its rows span 7.5 row pitches
## (`StatusPanel.ROW_PITCH`) and its labels and bars about 0.26 m across.
const PANEL_HALF: Vector2 = Vector2(0.14, 0.11)


static func _head(yaw_deg: float, pitch_deg: float, at: Vector3) -> Transform3D:
	var basis: Basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(basis, at)


## The mean of the shown rows' positions in the menu's parent space.
static func _rows_centre(menu: DevMenu) -> Vector3:
	var sum: Vector3 = Vector3.ZERO
	var count: int = 0
	for child: Node in menu.get_children():
		var line: Label3D = child as Label3D
		if line != null and line.visible:
			sum += menu.transform * line.position
			count += 1
	return sum / maxf(1.0, float(count))


func test_the_menu_opens_centred_one_metre_ahead_of_the_head_facing_it() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	if spec.error != "" or spec.distance_m != 1.0 or spec.offset_m != Vector2.ZERO:
		return "the shipped file gave distance %s, offset %s: %s" % [spec.distance_m, spec.offset_m, spec.error]
	for pose: Array in [[0.0, 0.0], [40.0, 0.0], [-75.0, -20.0], [180.0, 15.0]]:
		var head: Transform3D = _head(pose[0], pose[1], Vector3(0.3, 1.6, -0.2))
		var ahead: Vector3 = head.origin - head.basis.z * 1.0
		var menu: DevMenu = DevMenu.new(spec, [])
		menu.place(head)
		menu.open("top_left", "")
		var centre: Vector3 = menu.transform.origin
		var rows: Vector3 = _rows_centre(menu)
		var faces: float = menu.transform.basis.z.normalized().dot((head.origin - centre).normalized())
		var tilt: float = menu.transform.basis.x.y
		menu.free()
		if centre.distance_to(ahead) > TOLERANCE_M or rows.distance_to(ahead) > TOLERANCE_M:
			return "head %s: centre %s, rows' middle %s, 1 m ahead %s" % [pose, centre, rows, ahead]
		if faces < 0.99 or absf(tilt) > 0.001:
			return "head %s: the menu faces the head by %.3f and tilts %.3f" % [pose, faces, tilt]
	return ""


func test_a_level_head_puts_the_middle_row_at_eye_height() -> String:
	var spec: DevMenuSpec = DevMenuSpec.load_file()
	var head: Transform3D = _head(25.0, 0.0, Vector3(0.0, 1.55, 0.0))
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.place(head)
	menu.open("top_left", "")
	var rows: Vector3 = _rows_centre(menu)
	menu.free()
	if absf(rows.y - head.origin.y) > 0.001:
		return "the middle row is at %.3f m, the eyes at %.3f m" % [rows.y, head.origin.y]
	return ""


func test_distance_and_offset_come_from_the_file() -> String:
	var text: String = JSON.stringify({"entries": [{"kind": "close", "label": "Close"}],
		"corners": ["top_left"], "distance_m": 1.4, "offset_m": [0.1, -0.2]})
	var spec: DevMenuSpec = DevMenuSpec.parse(text)
	if spec.error != "":
		return "a valid place was rejected: %s" % spec.error
	var menu: DevMenu = DevMenu.new(spec, [])
	menu.place(Transform3D.IDENTITY)
	var at: Vector3 = menu.transform.origin
	menu.free()
	if at.distance_to(Vector3(0.1, -0.2, -1.4)) > 0.001:
		return "the menu opened at %s" % [at]
	for bad: Dictionary in [{"distance_m": 0}, {"distance_m": "far"}, {"offset_m": [1]}, {"offset_m": ["a", 0]}]:
		var data: Dictionary = {"entries": [{"kind": "close", "label": "Close"}], "corners": ["a"]}
		data.merge(bad)
		if DevMenuSpec.parse(JSON.stringify(data)).error == "":
			return "%s was accepted" % [bad]
	return ""


func test_the_open_menu_stays_where_it_opened_as_the_head_turns() -> String:
	var rig: Node3D = Node3D.new()
	var camera: Node3D = Node3D.new()
	camera.name = "Camera"
	rig.add_child(camera)
	camera.transform = _head(0.0, 0.0, Vector3(0.0, 1.6, 0.0))
	var wiring: DevMenuWiring = DevMenuWiring.new()
	wiring.attach(rig, null, LevelStart.new(), func() -> void: pass, null, null,
		DevMenu.new(DevMenuSpec.load_file(), []))
	wiring.read({"buttons": {ControllerSampler.MENU_BUTTON: true}}, 1.0)
	wiring.read({"buttons": {}}, 1.2)
	var opened: Vector3 = wiring.menu.transform.origin
	camera.transform = _head(60.0, -30.0, Vector3(0.1, 1.5, 0.0))
	wiring.read({"buttons": {}}, 1.3)
	var later: Vector3 = wiring.menu.transform.origin
	var open: bool = wiring.is_open()
	rig.free()
	if not open or opened.distance_to(Vector3(0.0, 1.6, -1.0)) > TOLERANCE_M:
		return "the menu opened %s at %s, not 1 m ahead of the camera" % [open, opened]
	if later != opened:
		return "the menu followed the head from %s to %s" % [opened, later]
	return ""


## The panel's farthest point along the view and the menu's nearest, from the
## head point the panel is placed around, for one corner.
static func _depths(corner: String) -> Vector2:
	var saved: String = PanelCorner.current
	PanelCorner.current = corner
	var panel: Transform3D = StatusPanel.rig_transform(Transform3D.IDENTITY)
	PanelCorner.current = saved
	var farthest_panel: float = 0.0
	for x: float in [-PANEL_HALF.x, PANEL_HALF.x]:
		for y: float in [-PANEL_HALF.y, PANEL_HALF.y]:
			farthest_panel = maxf(farthest_panel, -(panel * Vector3(x, y, 0.0)).z)
	var menu: DevMenu = DevMenu.new(DevMenuSpec.load_file(), [])
	menu.place(Transform3D.IDENTITY)
	menu.open(corner, "")
	var nearest_menu: float = INF
	for child: Node in menu.get_children():
		var line: Label3D = child as Label3D
		if line != null and line.visible:
			nearest_menu = minf(nearest_menu, -(menu.transform * line.position).z)
	menu.free()
	return Vector2(farthest_panel, nearest_menu)


static func _clear_of_panel(corner: String) -> String:
	var depths: Vector2 = _depths(corner)
	if depths.y <= depths.x + 0.1:
		return "%s: the menu's nearest row is %.2f m ahead, the panel reaches %.2f m" % [
			corner, depths.y, depths.x]
	return ""


func test_the_menu_does_not_overlap_the_panel_bottom_left() -> String:
	return _clear_of_panel("bottom_left")


func test_the_menu_does_not_overlap_the_panel_bottom_right() -> String:
	return _clear_of_panel("bottom_right")


func test_the_menu_does_not_overlap_the_panel_top_left() -> String:
	return _clear_of_panel("top_left")


func test_the_menu_does_not_overlap_the_panel_top_right() -> String:
	return _clear_of_panel("top_right")


func test_the_menu_does_not_overlap_the_panel_centre() -> String:
	return _clear_of_panel(PanelCorner.CENTRE)
