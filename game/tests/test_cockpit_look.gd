extends RefCounted

## The cockpit stands out (#659, GFX-2, GFX-4, CMF-1, ARC-4): each preset's
## cockpit file carries a `"look"` object with an edge highlight, a dim light
## of the frame's own and a procedural panel pattern; bad values are rejected;
## no surface can read black on black under ambient light only; presets 1 and
## 2 keep the pattern calm; and the built frame draws with those values.

const FrameTests := preload("res://tests/test_cockpit_frame.gd")
const LEVEL_LOOK: String = "res://view/level_look.json"
const SHAPES: Array[String] = ["Ledge", "Pillars", "Rim"]
## The ship's collision radius: the frame's light must not reach past it.
const HULL_RADIUS_M: float = 1.0


static func _spec_for(number: int) -> CockpitSpec:
	return CockpitSpec.for_preset(ComfortPresetFiles.load_number(number))


static func _spec_with_look(look: Dictionary) -> CockpitSpec:
	var data: Dictionary = FrameTests.valid_data()
	data["look"] = look
	return CockpitSpec.parse_json(JSON.stringify(data))


## The mine's ambient light, colour times energy, from the level look file.
static func _level_ambient() -> Color:
	var look: Dictionary = LevelLook.load_file()
	var energy: float = float(look["ambient_energy"])
	var color: Color = look["ambient_color"]
	return Color(color.r * energy, color.g * energy, color.b * energy)


func test_every_preset_file_has_a_look() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec_for(number)
		if spec.error != "":
			return "preset %d: %s" % [number, spec.error]
		if spec.look.error != "" or spec.look.edge_width_m <= 0.0 or spec.look.light_energy <= 0.0:
			return "preset %d has no edge highlight or no light of its own" % number
		if spec.look.pattern_contrast <= 0.0:
			return "preset %d has no surface pattern" % number
	return ""


func test_valid_look_reads_every_value() -> String:
	var look: Dictionary = FrameTests.valid_look()
	look["glow"] = 0.6
	look["edge_color"] = [0.9, 0.5, 0.1]
	look["pattern_scale_m"] = 0.2
	look["rivet_size"] = 0.1
	var spec: CockpitSpec = _spec_with_look(look)
	if spec.error != "":
		return spec.error
	if not is_equal_approx(spec.look.glow, 0.6) or spec.look.edge_color != Color(0.9, 0.5, 0.1) \
			or not is_equal_approx(spec.look.pattern_scale_m, 0.2) or not is_equal_approx(spec.look.rivet_size, 0.1):
		return "values not read: glow %s, edge %s, scale %s, rivets %s" % [spec.look.glow,
			spec.look.edge_color, spec.look.pattern_scale_m, spec.look.rivet_size]
	return ""


func test_rejected_looks_name_the_field() -> String:
	for key: String in CockpitLook.RANGES:
		var cases: Dictionary[String, Variant] = {
			"missing": null, "too low": CockpitLook.RANGES[key][0] - 0.001,
			"too high": CockpitLook.RANGES[key][1] + 0.001, "a bool": true, "a string": "1",
		}
		for case: String in cases:
			var look: Dictionary = FrameTests.valid_look()
			if cases[case] == null:
				look.erase(key)
			else:
				look[key] = cases[case]
			var error: String = _spec_with_look(look).error
			if error.find(key) < 0:
				return "%s %s: error \"%s\" does not name it" % [key, case, error]
	for key: String in CockpitLook.COLOR_KEYS:
		for bad: Variant in [null, [1, 1], [0, 0, 2], [0, "a", 0], "white"]:
			var look: Dictionary = FrameTests.valid_look()
			if bad == null:
				look.erase(key)
			else:
				look[key] = bad
			var error: String = _spec_with_look(look).error
			if error.find(key) < 0:
				return "%s %s: error \"%s\" does not name it" % [key, bad, error]
	var extra: Dictionary = FrameTests.valid_look()
	extra["sparkle"] = 1.0
	if _spec_with_look(extra).error.find("sparkle") < 0:
		return "an unknown look key is not named"
	if _spec_with_look({}).error.find("look") < 0:
		return "an empty look is not named"
	var data: Dictionary = FrameTests.valid_data()
	data["look"] = 3
	if CockpitSpec.parse_json(JSON.stringify(data)).error.find("look") < 0:
		return "a look that is not an object was accepted"
	data.erase("look")
	if CockpitSpec.parse_json(JSON.stringify(data)).error.find("look") < 0:
		return "a file without a look was accepted"
	return ""


## The criterion that it can never again be black on black: under the mine's
## ambient light only, and under none at all, every surface of every preset
## shows at least its file's floor.
func test_every_surface_is_above_the_floor_under_ambient_only() -> String:
	var ambient: Color = _level_ambient()
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec_for(number)
		for key: String in CockpitSpec.COLOR_KEYS:
			var base: Color = spec.get(key)
			for light: Color in [ambient, Color.BLACK]:
				var brightness: float = spec.look.lit_brightness(base, light)
				if brightness < spec.look.min_lit_brightness:
					return "preset %d %s shows %.3f under ambient %s, floor %s" % [number, key, brightness,
						light, spec.look.min_lit_brightness]
	return ""


## The old cockpit, interior RGB (0.08, 0.1, 0.13) with no glow, is what the
## owner saw as black on black. Such a file is now refused, naming the floor.
func test_a_black_on_black_cockpit_is_rejected() -> String:
	var data: Dictionary = FrameTests.valid_data()
	data["interior_color"] = [0.08, 0.1, 0.13]
	var error: String = CockpitSpec.parse_json(JSON.stringify(data)).error
	if error.find("min_lit_brightness") < 0 or error.find("interior_color") < 0:
		return "the old dark interior was accepted or not explained: \"%s\"" % error
	var look: Dictionary = FrameTests.valid_look()
	look["glow"] = 0.0
	error = _spec_with_look(look).error
	if error.find("min_lit_brightness") < 0:
		return "a cockpit lit by nothing but a dark mine was accepted: \"%s\"" % error
	return ""


func test_brightness_rises_with_glow_and_ambient_and_falls_with_contrast() -> String:
	var look: CockpitLook = CockpitLook.new()
	var base: Color = Color(0.3, 0.33, 0.38)
	var plain: float = look.lit_brightness(base, Color.BLACK)
	look.glow += 0.2
	if look.lit_brightness(base, Color.BLACK) <= plain:
		return "more glow did not brighten"
	if look.lit_brightness(base, Color(0.2, 0.2, 0.2)) <= look.lit_brightness(base, Color.BLACK):
		return "ambient light did not brighten"
	var before: float = look.lit_brightness(base, Color.BLACK)
	look.pattern_contrast += 0.1
	if look.lit_brightness(base, Color.BLACK) >= before:
		return "a stronger pattern did not darken the darkest tone"
	return ""


## Presets 1 and 2: panels at least `CALM_MIN_PANEL_DEG` wide even on the
## farthest surface, low contrast and no rivets, so nothing fine flickers at
## the edge of view (#659 criterion 3).
func test_presets_1_and_2_keep_the_pattern_calm() -> String:
	for number: int in [1, 2]:
		var spec: CockpitSpec = _spec_for(number)
		if not spec.look.is_calm(spec.frame_distance_m):
			return "preset %d pattern: %.1f degree panels, contrast %s, rivets %s" % [number,
				spec.look.panel_angle_deg(spec.frame_distance_m), spec.look.pattern_contrast, spec.look.rivet_size]
	var busy: CockpitLook = CockpitLook.new()
	busy.pattern_scale_m = 0.04
	if busy.is_calm(0.5):
		return "4 cm panels at 0.5 m counted as calm"
	busy = CockpitLook.new()
	busy.rivet_size = 0.1
	return "" if not busy.is_calm(0.5) else "rivets counted as calm"


func test_the_surface_shader_compiles() -> String:
	var shader: Shader = CockpitMaterials.shader()
	if shader == null or shader.get_mode() != Shader.MODE_SPATIAL:
		return "%s did not load as a spatial shader" % CockpitMaterials.SURFACE_SHADER
	var names: Array[String] = []
	for uniform: Dictionary in shader.get_shader_uniform_list():
		names.append(str(uniform["name"]))
	for wanted: String in ["base_color", "edge_color", "edge_width_m", "edge_axis", "glow",
			"pattern_scale_m", "pattern_contrast", "rivet_size", "overlap_margin"]:
		if not names.has(wanted):
			return "shader did not compile or lacks %s: %s" % [wanted, names]
	if shader.code.contains("sampler2D"):
		return "the pattern must be computed, not read from an imported texture"
	if not shader.code.contains("fwidth"):
		return "the pattern has no fade for small panels, so it would shimmer"
	return ""


func test_the_frame_draws_with_its_files_look() -> String:
	for number: int in range(1, 5):
		var spec: CockpitSpec = _spec_for(number)
		var frame: CockpitFrame = CockpitFrame.new(spec)
		var message: String = _frame_look_message(frame, spec)
		frame.free()
		if message != "":
			return "preset %d: %s" % [number, message]
	return ""


func _frame_look_message(frame: CockpitFrame, spec: CockpitSpec) -> String:
	for part_name: String in ["Solid"] + SHAPES:
		var node: MultiMeshInstance3D = frame.part(part_name)
		if node == null:
			continue
		var material: ShaderMaterial = node.material_override as ShaderMaterial
		if material == null or material.shader != CockpitMaterials.shader():
			return "%s is not drawn with the cockpit surface shader" % part_name
		var want_base: Color = spec.interior_color if part_name == "Solid" else spec.structure_color
		if material.get_shader_parameter("base_color") != want_base:
			return "%s base %s, file %s" % [part_name, material.get_shader_parameter("base_color"), want_base]
		if not is_equal_approx(float(material.get_shader_parameter("pattern_contrast")), spec.look.pattern_contrast) \
				or not is_equal_approx(float(material.get_shader_parameter("pattern_scale_m")), spec.look.pattern_scale_m):
			return "%s pattern differs from the file" % part_name
		var edge: float = float(material.get_shader_parameter("edge_width_m"))
		if part_name == "Solid" and edge != 0.0:
			return "the shell has an edge highlight across every cell"
		if part_name != "Solid" and not is_equal_approx(edge, spec.look.edge_width_m):
			return "%s edge highlight %s, file %s" % [part_name, edge, spec.look.edge_width_m]
	var light: OmniLight3D = frame.get_node_or_null(CockpitMaterials.LIGHT_NAME) as OmniLight3D
	if light == null:
		return "no cockpit light"
	if light.shadow_enabled:
		return "the cockpit light casts shadows; only the headlight may (GFX-4)"
	if not is_equal_approx(light.light_energy, spec.look.light_energy) or light.light_color != spec.look.light_color:
		return "light %s x %s, file %s x %s" % [light.light_color, light.light_energy, spec.look.light_color,
			spec.look.light_energy]
	if light.position.length() + light.omni_range >= HULL_RADIUS_M:
		return "the cockpit light reaches %.2f m, past the hull" % (light.position.length() + light.omni_range)
	return ""


## The largest light any valid file allows still ends inside the hull.
func test_the_largest_valid_light_stays_inside_the_hull() -> String:
	var reach: float = CockpitLook.LIGHT_OFFSET.length() + float(CockpitLook.RANGES["light_range_m"][1])
	return "" if reach < HULL_RADIUS_M else "a valid light reaches %.2f m" % reach


func test_zero_light_energy_builds_no_light() -> String:
	var look: Dictionary = FrameTests.valid_look()
	look["light_energy"] = 0.0
	var frame: CockpitFrame = CockpitFrame.new(_spec_with_look(look))
	var light: Node = frame.get_node_or_null(CockpitMaterials.LIGHT_NAME)
	frame.free()
	return "" if light == null else "a light with no energy was still built"
