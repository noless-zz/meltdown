extends RefCounted

## The cockpit's physically based finish (#1306, GFX-2, ARC-4, ARC-5): each
## preset's file gives its surfaces a roughness, metalness, seams, bolts and
## wear, and open and glass canopies a faint edge reflection; every key moves
## the built material; a missing key, surface or object keeps today's look;
## bad values are rejected naming the field; and the comfort limits of each
## preset (window, guard) stay where they were (CMF-1).

const FrameTests := preload("res://tests/test_cockpit_frame.gd")
## Each built part and the finish surface that covers it.
const PART_OF_SURFACE: Dictionary[String, String] = {
	"frame": "Solid", "ledge": "Ledge", "pillars": "Pillars", "rim": "Rim",
}
## The window and guard of each preset before #1306, which the look must not
## change (CMF-1): [h, v, guard_margin_deg, guard_after_s, guard_distance_m].
const COMFORT_LIMITS: Dictionary[int, Array] = {
	1: [38.0, 26.0, 40.0, 3.0, 0.45],
	2: [50.0, 30.0, 40.0, 3.0, 0.45],
	3: [75.0, 55.0, 40.0, 3.0, 0.45],
	4: [90.0, 75.0, 40.0, 3.0, 0.45],
}


static func _spec_with_finish(finish: Variant) -> CockpitSpec:
	var data: Dictionary = FrameTests.valid_data()
	if finish != null:
		data["finish"] = finish
	return CockpitSpec.parse_json(JSON.stringify(data))


## The shader parameter `parameter` of the built part `part_name`.
static func _parameter(spec: CockpitSpec, part_name: String, parameter: String) -> Variant:
	var frame: CockpitFrame = CockpitFrame.new(spec)
	var node: MultiMeshInstance3D = frame.part(part_name)
	var result: Variant = null
	if node != null and node.material_override is ShaderMaterial:
		result = (node.material_override as ShaderMaterial).get_shader_parameter(parameter)
	frame.free()
	return result


static func _glass_material(spec: CockpitSpec) -> Material:
	var frame: CockpitFrame = CockpitFrame.new(spec)
	var material: Material = frame.part("Glass").material_override if frame.part("Glass") != null else null
	frame.free()
	return material


## A value of `key` inside `bounds` that is not `neutral`.
static func _other(neutral: float, bounds: Array) -> float:
	return float(bounds[1]) if not is_equal_approx(float(bounds[1]), neutral) else float(bounds[0])


func test_every_preset_ships_a_finish() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		for surface: String in CockpitFinish.SURFACES:
			var values: Dictionary = spec.finish.surfaces[surface]
			if values["metallic"] <= 0.0 or values["seam_depth_m"] <= 0.0 or values["wear"] <= 0.0:
				return "preset %d leaves the %s surface flat: %s" % [number, surface, values]
	for number: int in [3, 4]:
		if FrameTests.spec_for(number).finish.glass_fresnel <= 0.0:
			return "preset %d glass has no edge reflection" % number
	return ""


func test_shipped_values_build_into_the_materials() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var metallic: Variant = _parameter(spec, "Solid", "metallic")
		if metallic == null or not is_equal_approx(float(metallic), float(spec.finish.surfaces["frame"]["metallic"])):
			return "preset %d shell is built with metallic %s" % [number, metallic]
	return ""


func test_no_finish_keeps_todays_look() -> String:
	var spec: CockpitSpec = _spec_with_finish(null)
	if spec.error != "":
		return spec.error
	var today: Dictionary[String, float] = {
		"roughness": 0.75, "metallic": 0.0, "seam_depth_m": 0.0, "bolt_height_m": 0.0, "wear": 0.0,
	}
	for surface: String in PART_OF_SURFACE:
		for key: String in today:
			var value: Variant = _parameter(spec, PART_OF_SURFACE[surface], key)
			if value == null or not is_equal_approx(float(value), today[key]):
				return "%s %s is %s without a finish, was %s before #1306" % [surface, key, value, today[key]]
	var glass: Material = _glass_material(spec)
	if not glass is ShaderMaterial or glass.next_pass != null:
		return "without a finish the glass is not the filter alone: %s" % glass
	return ""


func test_missing_keys_fall_back_one_by_one() -> String:
	var spec: CockpitSpec = _spec_with_finish({"ledge": {"metallic": 0.6}})
	if spec.error != "":
		return spec.error
	for surface: String in CockpitFinish.SURFACES:
		for key: String in CockpitFinish.SURFACE_NEUTRAL:
			var expected: float = 0.6 if surface == "ledge" and key == "metallic" else CockpitFinish.SURFACE_NEUTRAL[key]
			if not is_equal_approx(float(spec.finish.surfaces[surface][key]), expected):
				return "%s.%s is %s, expected %s" % [surface, key, spec.finish.surfaces[surface][key], expected]
	for key: String in CockpitFinish.NEUTRAL:
		if not is_equal_approx(float(spec.finish.get(key)), CockpitFinish.NEUTRAL[key]):
			return "%s is %s without its key" % [key, spec.finish.get(key)]
	if spec.finish.glass_fresnel_color != CockpitFinish.NEUTRAL_COLOR:
		return "the reflection colour moved without its key"
	return ""


func test_each_surface_key_changes_only_its_surface() -> String:
	for surface: String in PART_OF_SURFACE:
		for key: String in CockpitFinish.SURFACE_NEUTRAL:
			var changed: float = _other(CockpitFinish.SURFACE_NEUTRAL[key], CockpitFinish.SURFACE_RANGES[key])
			var spec: CockpitSpec = _spec_with_finish({surface: {key: changed}})
			if spec.error != "":
				return "%s.%s: %s" % [surface, key, spec.error]
			for other: String in PART_OF_SURFACE:
				var built: float = float(_parameter(spec, PART_OF_SURFACE[other], key))
				var expected: float = changed if other == surface else CockpitFinish.SURFACE_NEUTRAL[key]
				if not is_equal_approx(built, expected):
					return "%s.%s = %s builds %s %s as %s" % [surface, key, changed, other, key, built]
	return ""


func test_each_shared_key_changes_the_result() -> String:
	var wear: CockpitSpec = _spec_with_finish({"wear_scale_m": 0.2})
	if not is_equal_approx(float(_parameter(wear, "Ledge", "wear_scale_m")), 0.2):
		return "wear_scale_m does not reach the surfaces"
	var cases: Dictionary[String, Array] = {
		"glass_fresnel": [0.2, "fresnel", 0.2],
		"glass_fresnel_power": [5.0, "fresnel_power", 5.0],
		"glass_fresnel_color": [[1.0, 0.5, 0.25], "fresnel_color", Color(1.0, 0.5, 0.25)],
	}
	for key: String in cases:
		var finish: Dictionary = {"glass_fresnel": 0.1}
		finish[key] = cases[key][0]
		var glass: Material = _glass_material(_spec_with_finish(finish))
		var material: Material = glass.next_pass if glass != null else null
		if not material is ShaderMaterial:
			return "%s: the glass has no reflection" % key
		var built: Variant = (material as ShaderMaterial).get_shader_parameter(cases[key][1])
		if built != cases[key][2] and not (built is float and is_equal_approx(built, cases[key][2])):
			return "%s builds %s %s" % [key, cases[key][1], built]
	return ""


func test_the_reflection_adds_to_the_filter_growing_to_the_edge() -> String:
	var material: Material = _glass_material(_spec_with_finish({"glass_fresnel": 0.2}))
	var filter: Vector3 = (material as ShaderMaterial).get_shader_parameter("filter_color")
	var through: float = float(FrameTests.valid_data()["glass_transmission"])
	if not is_equal_approx(maxf(filter.x, maxf(filter.y, filter.z)), through):
		return "glass_transmission %s became filter %s" % [through, filter]
	var glass: String = FileAccess.get_file_as_string(CockpitMaterials.GLASS_SHADER)
	if not glass.contains("blend_mul") or glass.contains("blend_mix"):
		return "the glass no longer multiplies the view: a mixed-in colour is a veil on a dark mine (#1459)"
	var shader: String = FileAccess.get_file_as_string(CockpitMaterials.GLASS_REFLECTION_SHADER)
	if not shader.contains("blend_add") or not shader.contains("pow(edge, fresnel_power)"):
		return "the reflection no longer adds light growing to the edge"
	if CockpitFinish.RANGES["glass_fresnel"][1] > 0.3:
		return "the reflection may hide the view"
	return ""


func test_rejected_finishes_name_the_field() -> String:
	var cases: Array[Array] = [
		["a list", [], "finish"],
		["unknown key", {"floor": {}}, "floor"],
		["unknown surface key", {"rim": {"shine": 1}}, "shine"],
		["surface not an object", {"rim": 1}, "rim"],
		["too rough", {"frame": {"roughness": 2}}, "frame.roughness"],
		["bool", {"ledge": {"wear": true}}, "ledge.wear"],
		["deep seams", {"pillars": {"seam_depth_m": 0.05}}, "pillars.seam_depth_m"],
		["blinding glass", {"glass_fresnel": 0.5}, "glass_fresnel"],
		["bad colour", {"glass_fresnel_color": [1, 1]}, "glass_fresnel_color"],
	]
	for case: Array in cases:
		var error: String = _spec_with_finish(case[1]).error
		if error.find(case[2]) < 0:
			return "%s: error \"%s\" does not name %s" % [case[0], error, case[2]]
	return ""


func test_window_and_guard_stay_as_they_were() -> String:
	for number: int in COMFORT_LIMITS:
		var spec: CockpitSpec = FrameTests.spec_for(number)
		var now: Array = [spec.window_half_angle_h_deg, spec.window_half_angle_v_deg, spec.guard_margin_deg,
			spec.guard_after_s, spec.guard_distance_m]
		for index: int in now.size():
			if not is_equal_approx(float(now[index]), float(COMFORT_LIMITS[number][index])):
				return "preset %d comfort limits are %s, were %s" % [number, now, COMFORT_LIMITS[number]]
	return ""


func test_the_look_adds_no_light() -> String:
	for number: int in range(1, 5):
		var frame: CockpitFrame = CockpitFrame.new(FrameTests.spec_for(number))
		var lights: int = frame.find_children("*", "Light3D", true, false).size()
		frame.free()
		if lights > 1:
			return "preset %d cockpit has %d lights; only its own dim light may be there (GFX-4)" % [number, lights]
	return ""


func test_the_surface_shader_keeps_todays_look_when_neutral() -> String:
	var shader: String = FileAccess.get_file_as_string(CockpitMaterials.SURFACE_SHADER)
	for needed: String in ["uniform float roughness = 0.75;", "uniform float metallic = 0.0;",
			"if (wear > 0.0)", "if (seam_depth_m > 0.0 || bolt_height_m > 0.0)", "uniform bool instance_tint = false;"]:
		if not shader.contains(needed):
			return "the surface shader lost \"%s\"" % needed
	if shader.contains("texture(") or shader.contains("sampler2D"):
		return "the surface shader samples a texture; it must stay procedural (ARC-5)"
	return ""
