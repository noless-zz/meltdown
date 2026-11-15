extends RefCounted

## The cockpit row of the comfort table as data (CMF-1, ARC-4): each preset
## names a cockpit file, the windows widen from preset 1 to 4, the built frame
## stays between the camera's near plane and the ship's hull, and it is part
## of the view only (ARC-3, CMF-6).

const COCKPIT_DIR: String = "res://xr/cockpits"
const FRAME_SCRIPT: String = "res://xr/cockpit_frame.gd"
const SPEC_SCRIPT: String = "res://xr/cockpit_spec.gd"
const CORE_DIR: String = "res://core"
## Nearest a mesh may come to the eye: well beyond the camera's 0.05 m near
## plane (#102).
const MIN_DISTANCE_M: float = 0.25
## Farthest a mesh may reach: the ship's collision radius.
const MAX_DISTANCE_M: float = 1.0
const PARTS: Array[String] = ["Solid", "Glass", "Struts"]


func _valid_data() -> Dictionary:
	return {
		"window_half_angle_h_deg": 40.0, "window_half_angle_v_deg": 30.0,
		"strut_width_m": 0.02, "frame_distance_m": 0.5, "glass_tint_alpha": 0.1,
	}


func _spec_for(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


## Nearest and farthest distance from the eye (the frame's origin) of any
## instance of any part, as (nearest, farthest). Each instance is a box with
## orthogonal axes, so its nearest point is the eye clamped into the box.
static func distance_range(frame: CockpitFrame) -> Vector2:
	var result: Vector2 = Vector2(INF, 0.0)
	for part_name: String in PARTS:
		var node: MultiMeshInstance3D = frame.part(part_name)
		if node == null:
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
	for property: Dictionary in load(SPEC_SCRIPT).get_script_property_list():
		if property["type"] == TYPE_FLOAT:
			fields.append(property["name"])
	for key: String in CockpitSpec.KEYS:
		if not fields.has(key):
			return "key %s is not a float field" % key
		if not CockpitSpec.RANGES.has(key):
			return "key %s has no range" % key
	if fields.size() != CockpitSpec.KEYS.size():
		return "fields %s, keys %s" % [fields, CockpitSpec.KEYS]
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
	var previous: CockpitSpec = _spec_for(1)
	for number: int in range(2, 5):
		var spec: CockpitSpec = _spec_for(number)
		if spec.window_half_angle_h_deg < previous.window_half_angle_h_deg \
				or spec.window_half_angle_v_deg < previous.window_half_angle_v_deg:
			return "preset %d narrows a window half-angle" % number
		var wider: bool = spec.window_solid_angle() > previous.window_solid_angle()
		var not_narrower: bool = spec.window_solid_angle() >= previous.window_solid_angle()
		if (number < 4 and not wider) or not not_narrower:
			return "preset %d window %.3f sr, preset %d %.3f sr" % [number, spec.window_solid_angle(),
				number - 1, previous.window_solid_angle()]
		previous = spec
	return ""


func test_every_preset_frame_lies_between_near_plane_and_hull() -> String:
	for number: int in range(1, 5):
		var frame: CockpitFrame = CockpitFrame.new(_spec_for(number))
		var span: Vector2 = distance_range(frame)
		var parts: int = frame.get_child_count()
		frame.free()
		if parts == 0:
			return "preset %d built nothing" % number
		if span.x < MIN_DISTANCE_M or span.y > MAX_DISTANCE_M:
			return "preset %d spans %.3f..%.3f m" % [number, span.x, span.y]
	return ""


func test_range_extremes_stay_between_near_plane_and_hull() -> String:
	for extreme: int in 2:
		var data: Dictionary = {}
		for key: String in CockpitSpec.KEYS:
			data[key] = CockpitSpec.RANGES[key][extreme]
		var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
		if spec.error != "":
			return "extreme %d rejected: %s" % [extreme, spec.error]
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var span: Vector2 = distance_range(frame)
		frame.free()
		if span.x < MIN_DISTANCE_M or span.y > MAX_DISTANCE_M:
			return "extreme %d spans %.3f..%.3f m" % [extreme, span.x, span.y]
	return ""


## The closest geometry a valid file can build: the frame as near as allowed,
## the widest struts, and the narrowest window so struts exist on every edge.
## Neither all-minimum nor all-maximum covers this combination.
func test_nearest_valid_frame_stays_beyond_near_plane() -> String:
	var data: Dictionary = {
		"window_half_angle_h_deg": CockpitSpec.RANGES["window_half_angle_h_deg"][0],
		"window_half_angle_v_deg": CockpitSpec.RANGES["window_half_angle_v_deg"][0],
		"strut_width_m": CockpitSpec.RANGES["strut_width_m"][1],
		"frame_distance_m": CockpitSpec.RANGES["frame_distance_m"][0],
		"glass_tint_alpha": 1.0,
	}
	var spec: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
	if spec.error != "":
		return "nearest combination rejected: %s" % spec.error
	var frame: CockpitFrame = CockpitFrame.new(spec)
	var struts: int = frame.instance_count("Struts")
	var span: Vector2 = distance_range(frame)
	frame.free()
	if struts == 0:
		return "a 10 degree window built no struts"
	if span.x < MIN_DISTANCE_M or span.y > MAX_DISTANCE_M:
		return "nearest combination spans %.3f..%.3f m" % [span.x, span.y]
	return ""


func test_frame_is_primitive_meshes_without_collision() -> String:
	var frame: CockpitFrame = CockpitFrame.new(_spec_for(1))
	var message: String = ""
	for child: Node in frame.find_children("*", "", true, false):
		if child is CollisionObject3D or child is CollisionShape3D:
			message = "%s is a collision node" % child.name
		elif not child is MultiMeshInstance3D:
			message = "%s is a %s" % [child.name, child.get_class()]
		elif not (child as MultiMeshInstance3D).multimesh.mesh is PrimitiveMesh:
			message = "%s is not a primitive mesh" % child.name
	for part_name: String in PARTS:
		if frame.instance_count(part_name) == 0:
			message = "preset 1 has no %s" % part_name
	frame.free()
	return message


func test_glass_window_has_no_struts_on_the_rim() -> String:
	var frame: CockpitFrame = CockpitFrame.new(_spec_for(4))
	var spec: CockpitSpec = frame.spec
	var struts: int = frame.instance_count("Struts")
	frame.free()
	if spec.window_half_angle_h_deg < 90.0:
		return "preset 4 is expected to open the full width"
	# Only the top and bottom edges remain, one segment per cell across 180 degrees.
	var expected: int = 2 * ceili(180.0 / CockpitFrame.CELL_DEG)
	if struts != expected:
		return "%d strut segments, expected %d" % [struts, expected]
	return ""


func test_zero_tint_builds_no_glass() -> String:
	var data: Dictionary = _valid_data()
	data["glass_tint_alpha"] = 0.0
	var frame: CockpitFrame = CockpitFrame.new(CockpitSpec.parse_json(JSON.stringify(data)))
	var glass: MultiMeshInstance3D = frame.part("Glass")
	frame.free()
	return "" if glass == null else "a fully clear window still has glass"


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


func test_switching_preset_swaps_the_frame_without_touching_a_sim() -> String:
	var sim: Sim = Sim.new(7)
	var inputs: Array[ShipInput] = [ShipInput.new()]
	for i: int in 30:
		sim.step(inputs)
	var hash_before: int = sim.state_hash()
	var frame: CockpitFrame = CockpitFrame.new(_spec_for(1))
	var solid_before: int = frame.instance_count("Solid")
	frame.set_spec(_spec_for(4))
	var solid_after: int = frame.instance_count("Solid")
	var parts: int = frame.get_child_count()
	frame.free()
	if solid_after >= solid_before:
		return "solid panels %d before, %d after: the frame was not swapped" % [solid_before, solid_after]
	if parts != PARTS.size():
		return "%d parts after the swap; the old frame was not removed" % parts
	if sim.state_hash() != hash_before:
		return "switching the cockpit changed the simulation"
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
