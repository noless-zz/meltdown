extends RefCounted

## The cockpit row of the comfort table as data (CMF-1, ARC-4): each preset
## names a cockpit file, the windows widen from preset 1 to 4, bad files name
## the field, and the cockpit scripts are part of the view only (ARC-3, CMF-6).
## The built frame's checks are in `test_cockpit_frame_geometry.gd`; this file
## keeps the fixtures it and other cockpit tests preload.

const COCKPIT_DIR: String = "res://xr/cockpits"
const FRAME_SCRIPT: String = "res://xr/cockpit_frame.gd"
const SPEC_SCRIPT: String = "res://xr/cockpit_spec.gd"
const CORE_DIR: String = "res://core"
## Nearest a mesh may come to the eye: well beyond the camera's 0.05 m near
## plane (#102).
const MIN_DISTANCE_M: float = 0.25
## Farthest a mesh may reach: the ship's collision radius.
const MAX_DISTANCE_M: float = 1.0


static func valid_data() -> Dictionary:
	return {
		"window_half_angle_h_deg": 40.0, "window_half_angle_v_deg": 30.0,
		"frame_distance_m": 0.5, "glass_tint_alpha": 0.1,
		"ledge_top_deg": 30.0, "ledge_height_deg": 12.0, "ledge_half_width_deg": 60.0,
		"ledge_distance_m": 0.36, "pillar_width_deg": 8.0, "pillar_distance_m": 0.42,
		"rim_height_deg": 8.0, "rim_distance_m": 0.42, "part_depth_m": 0.03,
		"guard_margin_deg": 40.0, "guard_after_s": 3.0, "guard_distance_m": 0.45,
		"interior_color": [0.3, 0.33, 0.38], "structure_color": [0.44, 0.47, 0.52],
		"look": valid_look(),
	}


## A valid `"look"` object for a cockpit file (#659).
static func valid_look() -> Dictionary:
	return {
		"glow": 0.45, "edge_color": [0.62, 0.72, 0.82], "edge_width_m": 0.006,
		"light_color": [0.75, 0.85, 1.0], "light_energy": 0.4, "light_range_m": 0.6,
		"pattern_scale_m": 0.12, "pattern_contrast": 0.08, "rivet_size": 0.0,
		"min_lit_brightness": 0.12,
	}


func _valid_data() -> Dictionary:
	return valid_data()


static func spec_for(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


## Nearest and farthest distance from the eye (the frame's origin) of any
## instance of any part, as (nearest, farthest). Each instance is a box with
## orthogonal axes, so its nearest point is the eye clamped into the box. The
## glass is one sheet whose points lie on a sphere; a triangle between them
## comes no nearer than its points times the cosine of one cell.
static func distance_range(frame: CockpitFrame) -> Vector2:
	var result: Vector2 = Vector2(INF, 0.0)
	for point: Vector3 in frame.glass_points():
		result.x = minf(result.x, point.length() * cos(deg_to_rad(CockpitFrame.CELL_DEG)))
		result.y = maxf(result.y, point.length())
	for part_name: String in CockpitFrame.PARTS:
		var node: MultiMeshInstance3D = frame.part(part_name)
		if node == null or part_name == "Glass":
			continue
		var box: AABB = node.multimesh.mesh.get_aabb()
		for instance: Transform3D in frame.instance_transforms(part_name):
			var t: Transform3D = node.transform * instance
			var centre: Vector3 = t * box.get_center()
			var nearest: Vector3 = centre
			for axis: int in 3:
				var column: Vector3 = t.basis[axis]
				var unit: Vector3 = column.normalized()
				var half: float = box.size[axis] * 0.5 * column.length()
				nearest += unit * clampf(-centre.dot(unit), -half, half)
			result.x = minf(result.x, nearest.length())
			for corner: int in 8:
				result.y = maxf(result.y, (t * box.get_endpoint(corner)).length())
	return result


func test_keys_match_the_fields() -> String:
	var fields: Array[String] = []
	var colors: Array[String] = []
	for property: Dictionary in load(SPEC_SCRIPT).get_script_property_list():
		if property["type"] == TYPE_FLOAT:
			fields.append(property["name"])
		elif property["type"] == TYPE_COLOR:
			colors.append(property["name"])
	for key: String in CockpitSpec.KEYS:
		if not fields.has(key):
			return "key %s is not a float field" % key
		if not CockpitSpec.RANGES.has(key):
			return "key %s has no range" % key
	if fields.size() != CockpitSpec.KEYS.size():
		return "fields %s, keys %s" % [fields, CockpitSpec.KEYS]
	if colors != CockpitSpec.COLOR_KEYS:
		return "colour fields %s, colour keys %s" % [colors, CockpitSpec.COLOR_KEYS]
	return ""


func test_every_preset_cockpit_file_loads() -> String:
	for number: int in range(1, 5):
		var preset: ComfortPreset = ComfortPresetFiles.load_number(number)
		if not preset.cockpit_file.begins_with(COCKPIT_DIR + "/"):
			return "preset %d names %s, outside %s" % [number, preset.cockpit_file, COCKPIT_DIR]
		var spec: CockpitSpec = CockpitSpec.for_preset(preset)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
	return ""


func test_presets_use_four_distinct_files() -> String:
	var files: Array[String] = []
	for number: int in range(1, 5):
		var file: String = ComfortPresetFiles.load_number(number).cockpit_file
		if files.has(file):
			return "preset %d repeats %s" % [number, file]
		files.append(file)
	for file_name: String in ["anchored", "guided", "open", "glass"]:
		if not files.has("%s/%s.json" % [COCKPIT_DIR, file_name]):
			return "no preset names %s.json" % file_name
	return ""


func test_windows_widen_from_preset_1_to_4() -> String:
	var previous: CockpitSpec = spec_for(1)
	for number: int in range(2, 5):
		var spec: CockpitSpec = spec_for(number)
		if spec.window_half_angle_h_deg < previous.window_half_angle_h_deg \
				or spec.window_half_angle_v_deg < previous.window_half_angle_v_deg:
			return "preset %d narrows a window half-angle" % number
		# Preset 1 must stay the most enclosed step on both axes (#212).
		if number == 2 and (spec.window_half_angle_h_deg <= previous.window_half_angle_h_deg
				or spec.window_half_angle_v_deg <= previous.window_half_angle_v_deg):
			return "preset 1 window is not strictly smaller than preset 2's on both axes"
		var wider: bool = spec.window_solid_angle() > previous.window_solid_angle()
		var not_narrower: bool = spec.window_solid_angle() >= previous.window_solid_angle()
		if (number < 4 and not wider) or not not_narrower:
			return "preset %d window %.3f sr, preset %d %.3f sr" % [number, spec.window_solid_angle(),
				number - 1, previous.window_solid_angle()]
		previous = spec
	return ""


func test_rejected_files_name_the_field() -> String:
	for key: String in CockpitSpec.KEYS:
		var cases: Dictionary[String, Variant] = {
			"missing": null, "too low": CockpitSpec.RANGES[key][0] - 0.001,
			"too high": CockpitSpec.RANGES[key][1] + 0.001, "a bool": true, "a string": "1",
		}
		for case: String in cases:
			var data: Dictionary = _valid_data()
			if cases[case] == null:
				data.erase(key)
			else:
				data[key] = cases[case]
			var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
			if spec.error.find(key) < 0:
				return "%s %s: error \"%s\" does not name it" % [key, case, spec.error]
	var extra: Dictionary = _valid_data()
	extra["window_tint"] = 0.5
	if CockpitSpec.parse_json(JSON.stringify(extra)).error.find("window_tint") < 0:
		return "an unknown key is not named"
	for text: String in ["", "{", "[]", "not json"]:
		if CockpitSpec.parse_json(text).error == "":
			return "accepted %s" % JSON.stringify(text)
	if CockpitSpec.load_file(COCKPIT_DIR + "/missing.json").error == "":
		return "a missing file was accepted"
	return ""


func test_cockpit_scripts_reference_nothing_in_core() -> String:
	var core_names: Array[String] = []
	for file: String in DirAccess.get_files_at(CORE_DIR):
		if not file.ends_with(".gd"):
			continue
		var found: RegExMatch = RegEx.create_from_string("class_name\\s+(\\w+)") \
			.search(FileAccess.get_file_as_string(CORE_DIR.path_join(file)))
		if found != null:
			core_names.append(found.get_string(1))
	if not core_names.has("Sim"):
		return "core classes were not read"
	for path: String in [FRAME_SCRIPT, SPEC_SCRIPT]:
		var source: String = FileAccess.get_file_as_string(path)
		for core_name: String in core_names:
			if RegEx.create_from_string("\\b%s\\b" % core_name).search(source) != null:
				return "%s references core class %s" % [path, core_name]
	return ""
