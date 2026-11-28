extends RefCounted

## Physically based mine walls per theme (#1292, GFX-2, ARC-4, ARC-5): the
## material builds from the data file, every documented key reaches the wall
## shader and changes it, a missing key or file falls back to the look the
## walls had before (the shader's own defaults), and nothing is an image.

const FILE: String = "res://view/level_wall_material.json"


func _theme_text(values: Dictionary) -> String:
	return JSON.stringify({"default_theme": "t", "themes": {"t": values}})


## A value for `key` inside its range that differs from the neutral one.
func _other_value(key: String) -> float:
	var bounds: Array = LevelWallMaterial.RANGES[key]
	var high: float = float(bounds[1])
	var low: float = float(bounds[0])
	return high if not is_equal_approx(high, float(LevelWallMaterial.NEUTRAL[key])) else low


func _material(values: Dictionary) -> ShaderMaterial:
	return LevelLookMaterials.wall_material(LevelLook.FALLBACK, LevelLook.FALLBACK["wall_color"], values)


## The default value of every `uniform float` in the wall shader, by name.
func _shader_defaults() -> Dictionary:
	var defaults: Dictionary = {}
	var pattern: RegEx = RegEx.create_from_string("uniform float (\\w+) = ([-0-9.]+);")
	for found: RegExMatch in pattern.search_all(FileAccess.get_file_as_string(LevelLook.WALL_SHADER)):
		defaults[found.get_string(1)] = float(found.get_string(2))
	return defaults


func test_the_shipped_file_parses_with_its_default_theme() -> String:
	var parsed: Dictionary = LevelWallMaterial.parse(FileAccess.get_file_as_string(FILE))
	if parsed.has("error"):
		return "shipped file rejected: %s" % parsed["error"]
	var theme: Dictionary = parsed["themes"][parsed["default_theme"]]
	for key: String in LevelWallMaterial.RANGES:
		if not FileAccess.get_file_as_string(FILE).contains("\"%s\"" % key):
			return "the shipped theme leaves %s to the fallback; the file should show every key" % key
	if is_equal_approx(float(theme["albedo_noise"]), 0.0) or is_equal_approx(float(theme["normal_strength"]), 0.0):
		return "the shipped theme is as flat as the old look"
	return ""


func test_the_wall_material_builds_from_the_data_file() -> String:
	var theme: Dictionary = LevelWallMaterial.load_theme("", FILE)
	var material: ShaderMaterial = LevelLookMaterials.wall_material(LevelLook.FALLBACK, LevelLook.FALLBACK["floor_color"])
	for key: String in LevelWallMaterial.UNIFORMS:
		var uniform: String = LevelWallMaterial.UNIFORMS[key]
		if not is_equal_approx(float(material.get_shader_parameter(uniform)), float(theme[key])):
			return "%s is %s, the file says %s" % [uniform, material.get_shader_parameter(uniform), theme[key]]
	return ""


func test_each_documented_key_changes_the_material() -> String:
	var source: String = FileAccess.get_file_as_string("res://view/level_wall_material.gd")
	var neutral: ShaderMaterial = _material(LevelWallMaterial.NEUTRAL)
	for key: String in LevelWallMaterial.RANGES:
		if not source.contains("`%s`" % key):
			return "%s is not explained in LevelWallMaterial's comment" % key
		var values: Dictionary = {}
		values[key] = _other_value(key)
		var parsed: Dictionary = LevelWallMaterial.parse(_theme_text(values))
		if parsed.has("error"):
			return "%s = %s rejected: %s" % [key, values[key], parsed["error"]]
		var changed: ShaderMaterial = _material(parsed["themes"]["t"])
		var differing: Array[String] = []
		for uniform: String in LevelWallMaterial.UNIFORMS.values():
			if not is_equal_approx(float(changed.get_shader_parameter(uniform)), float(neutral.get_shader_parameter(uniform))):
				differing.append(uniform)
		if differing != [LevelWallMaterial.UNIFORMS[key]]:
			return "changing %s changed %s" % [key, differing]
	return ""


func test_every_uniform_exists_in_the_shader_with_the_neutral_default() -> String:
	var defaults: Dictionary = _shader_defaults()
	for key: String in LevelWallMaterial.UNIFORMS:
		var uniform: String = LevelWallMaterial.UNIFORMS[key]
		if not defaults.has(uniform):
			return "the wall shader has no float uniform %s" % uniform
		if not is_equal_approx(float(defaults[uniform]), float(LevelWallMaterial.NEUTRAL[key])):
			return "%s defaults to %s in the shader but %s is neutral" % [uniform, defaults[uniform], LevelWallMaterial.NEUTRAL[key]]
	return ""


func test_the_neutral_values_draw_the_old_flat_look() -> String:
	# The strengths are what put noise, metal and bevels on; at 0 the shader
	# skips them and the walls draw as before #1292.
	for key: String in ["albedo_noise", "roughness_noise", "metallic", "metal_share", "normal_strength", "bevel_strength"]:
		if not is_equal_approx(float(LevelWallMaterial.NEUTRAL[key]), 0.0):
			return "neutral %s is %s, not 0" % [key, LevelWallMaterial.NEUTRAL[key]]
	return ""


func test_a_missing_key_falls_back_to_the_current_look() -> String:
	var values: Dictionary = {"albedo_noise": 0.3}
	var parsed: Dictionary = LevelWallMaterial.parse(_theme_text(values))
	if parsed.has("error"):
		return "a theme with one key was rejected: %s" % parsed["error"]
	var theme: Dictionary = parsed["themes"]["t"]
	for key: String in LevelWallMaterial.RANGES:
		var expected: float = 0.3 if key == "albedo_noise" else float(LevelWallMaterial.NEUTRAL[key])
		if not is_equal_approx(float(theme[key]), expected):
			return "%s is %s, expected %s" % [key, theme[key], expected]
	return ""


func test_a_bad_file_or_theme_falls_back_and_names_the_field() -> String:
	var cases: Dictionary[String, String] = {
		_theme_text({"metallic": 2.0}): "themes.t.metallic",
		_theme_text({"bevel_strength": true}): "themes.t.bevel_strength",
		_theme_text({"albedo_map": "rock.png"}): "themes.t.albedo_map",
		JSON.stringify({"default_theme": "x", "themes": {"t": {}}}): "default_theme",
		JSON.stringify({"themes": {}}): "themes",
		JSON.stringify({"default_theme": "t", "themes": {"t": {}}, "extra": 1}): "extra",
	}
	for text: String in cases:
		var error: String = String(LevelWallMaterial.parse(text).get("error", ""))
		if not error.contains(cases[text]):
			return "%s gave \"%s\", expected it to name %s" % [text, error, cases[text]]
	if LevelWallMaterial.load_theme("", "res://view/no_such_material.json") != LevelWallMaterial.NEUTRAL:
		return "a missing file did not fall back to the neutral look"
	if LevelWallMaterial.load_theme("no_such_theme", FILE) != LevelWallMaterial.NEUTRAL:
		return "an unknown theme did not fall back to the neutral look"
	return ""


func test_the_level_view_draws_walls_with_the_shipped_theme() -> String:
	var view: LevelView = LevelView.new()
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	view.build(BoxUnion.new(boxes))
	var walls: MeshInstance3D = view.walls_of(0)
	var theme: Dictionary = LevelWallMaterial.load_theme()
	var result: String = ""
	for surface: int in walls.mesh.get_surface_count():
		var material: ShaderMaterial = walls.mesh.surface_get_material(surface) as ShaderMaterial
		if not is_equal_approx(float(material.get_shader_parameter("normal_strength")), float(theme["normal_strength"])):
			result = "surface %d has no theme on it" % surface
	view.free()
	return result


func test_nothing_is_an_image() -> String:
	# ARC-5: text resources only; the shader works the surface out from noise.
	var code: String = FileAccess.get_file_as_string(LevelLook.WALL_SHADER)
	if code.contains("sampler2D") or code.contains("texture("):
		return "the wall shader samples a texture"
	if not FileAccess.get_file_as_string(FILE).is_empty() and FileAccess.get_file_as_string(FILE).contains(".png"):
		return "the material file names an image"
	return ""
