extends RefCounted

## The modelled dash (#1306, GFX-2, CMF-1, ARC-4): presets with a ledge ship
## boxes and knobs on it, every piece stays below the window and inside the
## shell, so the window shows what it showed before; the dash leaves room for
## a cockpit-mounted map; and the frame builds each piece with its tone and
## lamp and no light of its own.

const FrameTests := preload("res://tests/test_cockpit_frame.gd")
## Where a cockpit-mounted map may go (owner's comment on #1306, 23 Nov): the
## dash right of centre, away from the status panel he keeps bottom-left.
## Degrees of yaw no dash piece may reach.
const MAP_PLACE_YAW: Vector2 = Vector2(0.0, 35.0)


static func _spec_with_dash(dash: Variant) -> CockpitSpec:
	var data: Dictionary = FrameTests.valid_data()
	data["dash"] = dash
	return CockpitSpec.parse_json(JSON.stringify(data))


## A piece that fits `FrameTests.valid_data()`: below its 30 degree window,
## in front of its 0.36 m ledge.
static func _piece() -> Dictionary:
	return {"shape": "box", "yaw_deg": -10, "pitch_deg": -36, "distance_m": 0.33, "size_m": [0.06, 0.03, 0.02]}


func test_presets_with_a_ledge_ship_a_dash() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var has_ledge: bool = spec.ledge_height_deg > 0.0
		var shapes: Array[String] = []
		for piece: CockpitDashPiece in spec.dash:
			if not shapes.has(piece.shape):
				shapes.append(piece.shape)
		if has_ledge and shapes.size() != CockpitDashPiece.SHAPES.size():
			return "preset %d dash has only %s" % [number, shapes]
		if not has_ledge and not spec.dash.is_empty():
			return "preset %d has a dash and no ledge to carry it" % number
	return ""


func test_shipped_pieces_stay_below_the_window_and_on_the_ledge() -> String:
	for number: int in range(1, 4):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var band: Vector2 = frame.ledge_band()
		frame.free()
		for index: int in spec.dash.size():
			var piece: CockpitDashPiece = spec.dash[index]
			for corner: Vector3 in CockpitGeometry.corners(piece.placed(), true):
				var angles: Vector2 = CockpitGeometry.yaw_pitch(corner)
				if -angles.y < spec.window_half_angle_v_deg or -angles.y > band.y:
					return "preset %d dash[%d] reaches pitch %.1f, off the ledge (%s)" % [number, index, angles.y, band]
			if piece.distance_m + piece.size_m.z > spec.ledge_distance_m + 1e-4:
				return "preset %d dash[%d] sinks behind the ledge's face" % [number, index]
	return ""


func test_the_dash_leaves_a_place_for_a_map() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		for index: int in spec.dash.size():
			for corner: Vector3 in CockpitGeometry.corners(spec.dash[index].placed(), true):
				var yaw: float = CockpitGeometry.yaw_pitch(corner).x
				if yaw > MAP_PLACE_YAW.x and yaw < MAP_PLACE_YAW.y:
					return "preset %d dash[%d] takes yaw %.1f, kept for a cockpit map" % [number, index, yaw]
	return ""


func test_the_frame_builds_each_piece_with_its_tone_and_lamp() -> String:
	var lamp: Dictionary = _piece()
	lamp["tone"] = 0.5
	lamp["lamp_color"] = [0.2, 0.9, 0.3]
	var knob: Dictionary = _piece()
	knob["shape"] = "knob"
	knob["yaw_deg"] = -25
	var spec: CockpitSpec = _spec_with_dash([_piece(), lamp, knob])
	if spec.error != "":
		return spec.error
	var frame: CockpitFrame = CockpitFrame.new(spec)
	var boxes: MultiMeshInstance3D = frame.part("Dash")
	var knobs: MultiMeshInstance3D = frame.part("Knobs")
	var message: String = ""
	if boxes == null or knobs == null or boxes.multimesh.instance_count != 2 or knobs.multimesh.instance_count != 1:
		message = "the dash is not built as two boxes and one knob"
	elif not (knobs.multimesh.mesh is CylinderMesh):
		message = "a knob is not a cylinder"
	elif not boxes.multimesh.use_colors or not boxes.multimesh.use_custom_data:
		message = "the dash carries no tone or lamp per piece"
	elif not (boxes.material_override as ShaderMaterial).get_shader_parameter("instance_tint"):
		message = "the dash material ignores each piece's tone"
	elif frame.instance_transforms("Dash")[1] != spec.dash[1].placed():
		message = "a piece is not where its file puts it"
	frame.free()
	if message != "":
		return message
	if spec.dash[1].tone != 0.5 or spec.dash[1].lamp_color != Color(0.2, 0.9, 0.3) or spec.dash[0].tone != 1.0 \
			or spec.dash[0].lamp_color != Color.BLACK:
		return "tone and lamp not read, or no default without them"
	return ""


func test_a_knob_faces_the_eye() -> String:
	var piece: CockpitDashPiece = CockpitDashPiece.new()
	piece.shape = "knob"
	piece.yaw_deg = -20.0
	piece.pitch_deg = -35.0
	var axis: Vector3 = piece.placed().basis.y.normalized()
	var toward_eye: Vector3 = -CockpitGeometry.direction(piece.yaw_deg, piece.pitch_deg)
	if axis.dot(toward_eye) < 0.999:
		return "the knob's axis points %s, not at the eye" % axis
	return ""


func test_no_dash_builds_no_dash_part() -> String:
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.parse_json(JSON.stringify(FrameTests.valid_data())))
	var built: bool = frame.part("Dash") != null or frame.part("Knobs") != null
	frame.free()
	return "a file without a dash built one" if built else ""


func test_rejected_pieces_name_the_field() -> String:
	var cases: Array[Array] = [
		["in the window", {"pitch_deg": -20}, "dash[0] reaches into the window"],
		["past the shell", {"distance_m": 0.49}, "past the shell"],
		["too near", {"distance_m": 0.2}, "dash[0].distance_m"],
		["bad shape", {"shape": "lever"}, "dash[0].shape"],
		["bad size", {"size_m": [0.1, 0.1]}, "dash[0].size_m"],
		["huge", {"size_m": [0.5, 0.1, 0.1]}, "dash[0].size_m"],
		["dark tone", {"tone": 0.0}, "dash[0].tone"],
		["bad lamp", {"lamp_color": "red"}, "dash[0].lamp_color"],
		["unknown key", {"spin": 1}, "spin"],
	]
	for case: Array in cases:
		var piece: Dictionary = _piece()
		piece.merge(case[1], true)
		var error: String = _spec_with_dash([piece]).error
		if error.find(case[2]) < 0:
			return "%s: error \"%s\" does not name \"%s\"" % [case[0], error, case[2]]
	var missing: Dictionary = _piece()
	missing.erase("size_m")
	if _spec_with_dash([missing]).error.find("dash[0].size_m is missing") < 0:
		return "a missing size is not named"
	if _spec_with_dash({}).error.find("dash") < 0:
		return "a dash that is not a list is not named"
	return ""
