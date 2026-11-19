extends RefCounted

## The cockpit frame reads as a ship (#607, CMF-1, ARC-4): a dashboard ledge,
## two canopy pillars and a rim, nothing of the frame across the window, the
## glass one seamless sheet, the ledge nearer than the pillars, and an interior
## tint apart from the tunnel's walls, all from `xr/cockpits/*.json`.

const FrameTests := preload("res://tests/test_cockpit_frame.gd")
const LEVEL_LOOK: String = "res://view/level_look.json"
const SHAPES: Array[String] = ["Ledge", "Pillars", "Rim"]
## Rounding allowed when a corner sits exactly on the window's edge, degrees.
const EDGE_TOLERANCE_DEG: float = 0.001


static func _spec_for(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


static func _spec_from(data: Dictionary) -> CockpitSpec:
	return CockpitSpec.parse_json(JSON.stringify(data))


## Empty when the whole piece lies outside the window. Every corner beyond the
## same edge is enough: the space beyond one edge is convex, so the piece
## between its corners lies there too.
static func _outside_message(spec: CockpitSpec, corners: Array[Vector3]) -> String:
	var h: float = spec.window_half_angle_h_deg - EDGE_TOLERANCE_DEG
	var v: float = spec.window_half_angle_v_deg - EDGE_TOLERANCE_DEG
	var beyond: Dictionary[String, bool] = {"left": true, "right": true, "below": true, "above": true}
	for corner: Vector3 in corners:
		var angles: Vector2 = CockpitGeometry.yaw_pitch(corner)
		beyond["left"] = beyond["left"] and angles.x <= -h
		beyond["right"] = beyond["right"] and angles.x >= h
		beyond["below"] = beyond["below"] and angles.y <= -v
		beyond["above"] = beyond["above"] and angles.y >= v
	if beyond.values().has(true):
		return ""
	var first: Vector2 = CockpitGeometry.yaw_pitch(corners[0])
	return "a piece near yaw %.1f, pitch %.1f reaches into the window" % [first.x, first.y]


## Empty when no solid panel or shape of `frame` lies inside its window.
static func _window_clear_message(frame: CockpitFrame) -> String:
	for part_name: String in CockpitFrame.PARTS:
		if part_name == "Glass":
			continue
		var deep: bool = CockpitFrame.BOX_PARTS.has(part_name)
		for placed: Transform3D in frame.instance_transforms(part_name):
			var message: String = _outside_message(frame.spec, CockpitGeometry.corners(placed, deep))
			if message != "":
				return "%s: %s" % [part_name, message]
	return ""


func test_presets_1_and_2_build_every_named_part() -> String:
	for number: int in [1, 2]:
		var spec: CockpitSpec = _spec_for(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var missing: Array[String] = []
		for part_name: String in CockpitFrame.PARTS:
			if frame.instance_count(part_name) == 0:
				missing.append(part_name)
		frame.free()
		if not missing.is_empty():
			return "preset %d has no %s" % [number, missing]
	return ""


func test_nothing_of_the_frame_lies_inside_any_preset_window() -> String:
	for number: int in range(1, 5):
		var frame: CockpitFrame = CockpitFrame.new(_spec_for(number))
		var message: String = _window_clear_message(frame)
		frame.free()
		if message != "":
			return "preset %d: %s" % [number, message]
	return ""


## The largest shapes on the narrowest and on a tall, wide window, where
## pieces sit high above the horizon and lean most.
func test_nothing_lies_inside_the_window_at_the_extremes() -> String:
	for window: Vector2 in [Vector2(10.0, 10.0), Vector2(70.0, 60.0), Vector2(85.0, 75.0)]:
		var data: Dictionary = FrameTests.valid_data()
		data["window_half_angle_h_deg"] = window.x
		data["window_half_angle_v_deg"] = window.y
		data["ledge_top_deg"] = window.y
		for key: String in ["ledge_height_deg", "ledge_half_width_deg", "pillar_width_deg", "rim_height_deg"]:
			data[key] = CockpitSpec.RANGES[key][1]
		var frame: CockpitFrame = CockpitFrame.new(_spec_from(data))
		var message: String = _window_clear_message(frame)
		frame.free()
		if message != "":
			return "window %s: %s" % [window, message]
	return ""


## Overlapping tinted panels drew darker seams every 10 degrees: the grid the
## owner saw. The glass is now one instance whose points stay in the window.
func test_the_glass_is_one_seamless_sheet_inside_the_window() -> String:
	for number: int in range(1, 5):
		var frame: CockpitFrame = CockpitFrame.new(_spec_for(number))
		var spec: CockpitSpec = frame.spec
		var count: int = frame.instance_count("Glass")
		var points: PackedVector3Array = frame.glass_points()
		frame.free()
		if count != 1:
			return "preset %d glass has %d instances" % [number, count]
		for point: Vector3 in points:
			var angles: Vector2 = CockpitGeometry.yaw_pitch(point)
			if absf(angles.x) > spec.window_half_angle_h_deg + EDGE_TOLERANCE_DEG \
					or absf(angles.y) > spec.window_half_angle_v_deg + EDGE_TOLERANCE_DEG:
				return "preset %d glass reaches yaw %.1f, pitch %.1f" % [number, angles.x, angles.y]
			if not is_equal_approx(point.length(), spec.frame_distance_m):
				return "preset %d glass point at %.3f m, not on the shell" % [number, point.length()]
	return ""


static func _nearest(frame: CockpitFrame, part_name: String) -> float:
	var nearest: float = INF
	for placed: Transform3D in frame.instance_transforms(part_name):
		for corner: Vector3 in CockpitGeometry.corners(placed, true):
			nearest = minf(nearest, corner.length())
	return nearest


func test_the_ledge_is_nearer_than_the_pillars() -> String:
	for number: int in [1, 2]:
		var frame: CockpitFrame = CockpitFrame.new(_spec_for(number))
		var ledge: float = _nearest(frame, "Ledge")
		var pillars: float = _nearest(frame, "Pillars")
		var shell: float = frame.spec.frame_distance_m
		frame.free()
		if ledge >= pillars:
			return "preset %d: ledge %.3f m, pillars %.3f m" % [number, ledge, pillars]
		if pillars >= shell:
			return "preset %d: pillars %.3f m are not in front of the shell at %.3f m" % [number, pillars, shell]
	return ""


static func _color_gap(a: Color, b: Color) -> float:
	return absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)


func test_the_interior_tint_differs_from_the_tunnel_walls() -> String:
	var look: Variant = JSON.parse_string(FileAccess.get_file_as_string(LEVEL_LOOK))
	if typeof(look) != TYPE_DICTIONARY or not (look as Dictionary).has("wall_color"):
		return "%s has no wall_color" % LEVEL_LOOK
	var wall_parts: Array = look["wall_color"]
	var wall: Color = Color(float(wall_parts[0]), float(wall_parts[1]), float(wall_parts[2]))
	for number: int in [1, 2]:
		var spec: CockpitSpec = _spec_for(number)
		if _color_gap(spec.interior_color, wall) < 0.08:
			return "preset %d interior %s is close to the walls' %s" % [number, spec.interior_color, wall]
		if spec.interior_color.get_luminance() > 0.2:
			return "preset %d interior %s is not dim" % [number, spec.interior_color]
		if _color_gap(spec.structure_color, spec.interior_color) < 0.15:
			return "preset %d shapes do not stand out from the shell" % number
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var solid: Color = (frame.part("Solid").material_override as StandardMaterial3D).albedo_color
		var ledge: Color = (frame.part("Ledge").material_override as StandardMaterial3D).albedo_color
		frame.free()
		if solid != spec.interior_color or ledge != spec.structure_color:
			return "preset %d does not draw with its file's colours" % number
	return ""


## The status panel's bottom row rests on the ledge's band. #605 raised the
## panel toward the eye line, so its lower rows, not its centre, meet the ledge.
func test_the_ledge_sits_under_the_status_panel() -> String:
	var panel_pitch: float = -CockpitGeometry.yaw_pitch(StatusPanel.row_point(StatusPanel.PRESET_Y)).y
	for number: int in [1, 2]:
		var frame: CockpitFrame = CockpitFrame.new(_spec_for(number))
		var band: Vector2 = frame.ledge_band()
		frame.free()
		if panel_pitch < band.x - 5.0 or panel_pitch > band.y:
			return "preset %d: panel %.1f degrees down, ledge %.1f..%.1f" % [number, panel_pitch, band.x, band.y]
	return ""


func test_ledge_top_moves_the_ledge_but_never_into_the_window() -> String:
	var data: Dictionary = FrameTests.valid_data()
	data["ledge_top_deg"] = 40.0
	var frame: CockpitFrame = CockpitFrame.new(_spec_from(data))
	var lowered: Vector2 = frame.ledge_band()
	data["ledge_top_deg"] = 10.0
	frame.set_spec(_spec_from(data))
	var raised: Vector2 = frame.ledge_band()
	var message: String = _window_clear_message(frame)
	frame.free()
	if not is_equal_approx(lowered.x, 40.0) or not is_equal_approx(lowered.y, 52.0):
		return "ledge_top_deg 40 gave band %s" % lowered
	if not is_equal_approx(raised.x, data["window_half_angle_v_deg"]):
		return "ledge_top_deg 10 put the ledge top at %.1f, inside the window" % raised.x
	return message


func test_zero_sizes_build_no_shapes() -> String:
	var data: Dictionary = FrameTests.valid_data()
	for key: String in ["ledge_height_deg", "pillar_width_deg", "rim_height_deg"]:
		data[key] = 0.0
	var frame: CockpitFrame = CockpitFrame.new(_spec_from(data))
	var message: String = ""
	for part_name: String in SHAPES:
		if frame.part(part_name) != null:
			message = "zero size still built %s" % part_name
	frame.free()
	return message


func test_bad_colours_and_shapes_behind_the_shell_are_rejected() -> String:
	for key: String in CockpitSpec.COLOR_KEYS:
		for bad: Variant in [null, [0.1, 0.2], [0.1, 0.2, 1.5], [0.1, true, 0.2], "grey"]:
			var data: Dictionary = FrameTests.valid_data()
			if bad == null:
				data.erase(key)
			else:
				data[key] = bad
			var error: String = _spec_from(data).error
			if error.find(key) < 0:
				return "%s = %s: error \"%s\" does not name it" % [key, bad, error]
	for key: String in CockpitSpec.SHAPE_DISTANCE_KEYS:
		var data: Dictionary = FrameTests.valid_data()
		data[key] = 0.48
		var error: String = _spec_from(data).error
		if error.find(key) < 0:
			return "%s past the shell: error \"%s\" does not name it" % [key, error]
	return ""
