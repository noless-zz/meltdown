extends RefCounted

## The look of a mine's inside (#609, GFX-4, LGT-1, ARC-4): every key of the
## look file is required and a bad one is named, floor, ceiling and walls are
## tinted by the way they face, the environment is dark, walls fog with distance, and
## the level view and the test tunnel both draw with it.

const LOOK_FILE: String = "res://view/level_look.json"


func _valid() -> Dictionary:
	var data: Dictionary = {}
	for key: String in LevelLook.COLOR_KEYS:
		data[key] = [0.1, 0.12, 0.14]
	for key: String in LevelLook.RANGES:
		data[key] = LevelLook.RANGES[key][1]
	return data


func _one_box() -> BoxUnion:
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-2, -3, -4), Vector3(2, 3, 4))]
	return BoxUnion.new(boxes)


func test_the_shipped_file_parses_and_matches_the_fallback() -> String:
	var look: Dictionary = LevelLook.load_file(LOOK_FILE)
	if look.has("error"):
		return "shipped look rejected: %s" % look["error"]
	for key: String in LevelLook.keys():
		var shipped: Variant = look[key]
		var fallback: Variant = LevelLook.FALLBACK[key]
		var same: bool = (shipped as Color).is_equal_approx(fallback) if shipped is Color \
				else is_equal_approx(float(shipped), float(fallback))
		if not same:
			return "%s is %s in the file but %s in the fallback" % [key, shipped, fallback]
	return ""


func test_every_key_is_required_and_named_when_missing() -> String:
	if LevelLook.parse(JSON.stringify(_valid())).has("error"):
		return "a valid look was rejected: %s" % LevelLook.parse(JSON.stringify(_valid()))["error"]
	for key: String in LevelLook.keys():
		var data: Dictionary = _valid()
		data.erase(key)
		var error: String = String(LevelLook.parse(JSON.stringify(data)).get("error", ""))
		if not error.contains("missing") or not error.contains(key):
			return "missing %s gave \"%s\"" % [key, error]
	return ""


func test_bad_values_are_named() -> String:
	var cases: Dictionary[String, Variant] = {
		"fog_density": 0.5, "ambient_energy": 1.0, "grid_spacing_m": 0.1, "grid_line_width_m": true,
		"grid_line_factor": -1.0, "floor_color": [0.1, 0.1], "ceiling_color": [0.1, 1.5, 0.1],
		"fog_color": "black", "edge_energy": 2.0,
	}
	for key: String in cases:
		var data: Dictionary = _valid()
		data[key] = cases[key]
		var error: String = String(LevelLook.parse(JSON.stringify(data)).get("error", ""))
		if not error.contains(key):
			return "bad %s gave \"%s\"" % [key, error]
	var extra: Dictionary = _valid()
	extra["texture"] = "rock.png"
	if not String(LevelLook.parse(JSON.stringify(extra)).get("error", "")).contains("texture"):
		return "an unknown key was not named"
	var missing: Dictionary = LevelLook.load_file("res://view/no_such_look.json")
	if not String(missing.get("error", "")).contains("no_such_look"):
		return "a missing file did not name its path: %s" % missing
	return ""


func test_tint_follows_the_way_a_face_points() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	var cases: Array[Array] = [
		[Vector3.UP, LevelLook.FLOOR], [Vector3.DOWN, LevelLook.CEILING],
		[Vector3.LEFT, LevelLook.WALL], [Vector3.RIGHT, LevelLook.WALL],
		[Vector3.FORWARD, LevelLook.WALL], [Vector3.BACK, LevelLook.WALL],
		[Vector3(0.0, 2.0, 1.0), LevelLook.FLOOR], [Vector3(0.0, -1.0, 2.0), LevelLook.WALL],
	]
	for case: Array in cases:
		var normal: Vector3 = case[0]
		var expected: String = case[1]
		if LevelLook.surface_class(normal) != expected:
			return "a face pointing %s is a %s, expected %s" % [normal, LevelLook.surface_class(normal), expected]
		if LevelLook.tint_for(look, normal) != look["%s_color" % expected]:
			return "a face pointing %s has the wrong tint" % normal
	var tints: Array[Color] = [look["floor_color"], look["ceiling_color"], look["wall_color"]]
	if tints[0] == tints[1] or tints[0] == tints[2] or tints[1] == tints[2]:
		return "floor, ceiling and walls share a tint, so up and down do not read"
	return ""


func test_the_environment_is_dark_and_walls_fog_with_distance() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	var env: Environment = LevelLook.environment(look)
	if float(look["fog_density"]) <= 0.0:
		return "the shipped look has no fog, so far walls do not darken"
	var code: String = (load(LevelLook.WALL_SHADER) as Shader).code
	if not code.contains("FOG =") or not code.contains("fog_density"):
		return "the wall shader does not fog by distance"
	# Far walls must get darker, not lighter: the fog is near black.
	if (look["fog_color"] as Color).get_luminance() > 0.05:
		return "fog colour %s would brighten far walls" % look["fog_color"]
	if env.ambient_light_source != Environment.AMBIENT_SOURCE_COLOR:
		return "ambient light does not come from the look's colour"
	if env.ambient_light_energy > float(LevelLook.RANGES["ambient_energy"][1]):
		return "ambient energy %s is not low (LGT-1)" % env.ambient_light_energy
	return ""


func test_wall_material_carries_the_grid_and_tint() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	var material: ShaderMaterial = LevelLook.wall_material(look, look["floor_color"])
	if material.shader == null:
		return "the wall shader did not load"
	var expected: Dictionary = {
		"tint": look["floor_color"], "grid_spacing": look["grid_spacing_m"],
		"line_width": look["grid_line_width_m"], "line_factor": look["grid_line_factor"],
		"roughness_value": look["roughness"], "fog_color": look["fog_color"],
		"fog_density": look["fog_density"],
	}
	for parameter: String in expected:
		if material.get_shader_parameter(parameter) != expected[parameter]:
			return "%s is %s, expected %s" % [parameter, material.get_shader_parameter(parameter), expected[parameter]]
	if FileAccess.get_file_as_string(LevelLook.WALL_SHADER).contains("texture("):
		return "the wall shader samples a texture; the grid must be worked out"
	return ""


func test_level_view_draws_each_class_in_its_tint_with_fog() -> String:
	var view: LevelView = LevelView.new()
	view.build(_one_box())
	var walls: MeshInstance3D = view.get_node(LevelView.WALLS_NAME) as MeshInstance3D
	var result: String = ""
	if walls.mesh.get_surface_count() != LevelLook.CLASSES.size():
		result = "one box gave %d wall surfaces, expected one per class" % walls.mesh.get_surface_count()
	for surface: int in walls.mesh.get_surface_count() if result == "" else 0:
		var normals: PackedVector3Array = walls.mesh.surface_get_arrays(surface)[Mesh.ARRAY_NORMAL]
		var material: ShaderMaterial = walls.mesh.surface_get_material(surface) as ShaderMaterial
		for normal: Vector3 in normals:
			if material.get_shader_parameter("tint") != LevelLook.tint_for(view.look(), normal):
				result = "surface %d draws a face pointing %s in the wrong tint" % [surface, normal]
				break
	var world: WorldEnvironment = view.get_node_or_null(LevelView.ENVIRONMENT_NAME) as WorldEnvironment
	if result == "" and (world == null or world.environment.background_color != view.look()["fog_color"]):
		result = "the level view has no dark environment in the fog's colour"
	view.free()
	return result


func test_the_test_tunnel_uses_the_same_look() -> String:
	var tunnel: TestTunnel = TestTunnel.new()
	tunnel.build()
	var look: Dictionary = LevelLook.load_file(LOOK_FILE)
	var result: String = ""
	var expected: Dictionary = {"Floor": Vector3.UP, "Ceiling": Vector3.DOWN, "LeftWall": Vector3.RIGHT, "FarEnd": Vector3.BACK}
	for part: String in expected:
		var box: MeshInstance3D = tunnel.get_node("Shell/" + part) as MeshInstance3D
		var material: ShaderMaterial = (box.mesh as BoxMesh).material as ShaderMaterial
		if material == null or material.get_shader_parameter("tint") != LevelLook.tint_for(look, expected[part]):
			result = "%s is not drawn in the level look's tint" % part
			break
	var world: WorldEnvironment = tunnel.get_node_or_null("Environment") as WorldEnvironment
	if result == "" and (world == null or world.environment.background_color != look["fog_color"]):
		result = "the tunnel has no dark environment in the fog's colour"
	if result == "" and not is_equal_approx(world.environment.ambient_light_energy, float(look["ambient_energy"])):
		result = "the tunnel's ambient light is not the level look's"
	tunnel.free()
	return result
