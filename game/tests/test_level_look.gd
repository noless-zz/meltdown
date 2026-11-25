extends RefCounted

## The look of a mine's inside (#609, GFX-4, LGT-1, ARC-4): every key of the
## look file is required and a bad one is named, floor, ceiling and walls are
## tinted by the way they face, the environment is dark, walls fog with distance, and
## the level view and the test tunnel both draw with it. Plating (#660): every
## value is in the file, seams cannot swallow panels, contrast stays low, and the
## shader picks the face kind from the normal by the same rule as `surface_class`.

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
		"fog_color": "black", "edge_energy": 2.0, "plate_floor_m": 0.1, "plate_wall_aspect": 0.5,
		"plate_ceiling_stagger": 0.75, "plate_seam_m": 0.001, "plate_contrast": 0.5,
		"plate_floor_aspect": "wide", "plate_wall_m": false,
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
	var walls: MeshInstance3D = view.walls_of(0)
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


func test_a_seam_wider_than_a_quarter_panel_is_named() -> String:
	var data: Dictionary = _valid()
	data["plate_ceiling_m"] = 0.4
	data["plate_seam_m"] = 0.15
	var error: String = String(LevelLook.parse(JSON.stringify(data)).get("error", ""))
	if not error.contains("plate_seam_m") or not error.contains("plate_ceiling_m"):
		return "a seam of 0.15 m on 0.4 m ceiling panels gave \"%s\"" % error
	data["plate_seam_m"] = 0.1
	if LevelLook.parse(JSON.stringify(data)).has("error"):
		return "a seam of exactly a quarter panel was rejected"
	return ""


func test_the_shipped_plating_tells_the_three_kinds_apart_gently() -> String:
	var look: Dictionary = LevelLook.load_file(LOOK_FILE)
	var seen: Array[Vector3] = []
	for kind: String in LevelLook.SHADER_KINDS:
		var shape: Vector3 = Vector3(float(look["plate_%s_m" % kind]),
				float(look["plate_%s_aspect" % kind]), float(look["plate_%s_stagger" % kind]))
		if seen.has(shape):
			return "%s panels are the same shape as another kind's, so the pattern does not tell them apart" % kind
		seen.append(shape)
	# Gentle enough for comfort presets 1 and 2: a panel strays at most 10 % in
	# tone either way and a seam is no more than a third darker.
	if float(look["plate_contrast"]) > 0.15:
		return "plate contrast %s is too strong for the gentle presets" % look["plate_contrast"]
	return ""


func test_face_kind_boundaries_including_sloped_faces() -> String:
	var just_over: float = LevelLook.FLOOR_MIN_UP + 0.001
	var just_under: float = LevelLook.FLOOR_MIN_UP - 0.001
	var side: float = sqrt(1.0 - just_over * just_over)
	var side_under: float = sqrt(1.0 - just_under * just_under)
	var cases: Array = [
		[Vector3(side, just_over, 0.0), LevelLook.FLOOR],
		[Vector3(0.0, just_under, side_under), LevelLook.WALL],
		[Vector3(-side, -just_over, 0.0), LevelLook.CEILING],
		[Vector3(0.0, -just_under, -side_under), LevelLook.WALL],
		# 30 degrees off level is a wall; 30 degrees off straight up is a floor.
		[Vector3(cos(PI / 6.0), sin(PI / 6.0), 0.0), LevelLook.WALL],
		[Vector3(0.0, cos(PI / 6.0), sin(PI / 6.0)), LevelLook.FLOOR],
		[Vector3(0.0, -cos(PI / 6.0), sin(PI / 6.0)), LevelLook.CEILING],
		# Length does not matter: a long normal is classed by its direction.
		[Vector3(0.0, 10.0, 0.0), LevelLook.FLOOR],
	]
	for case: Array in cases:
		if LevelLook.surface_class(case[0]) != case[1]:
			return "a face pointing %s is a %s, expected %s" % [case[0], LevelLook.surface_class(case[0]), case[1]]
	# 45 degrees exactly is where the rule turns; it must sit at sqrt(0.5).
	if absf(LevelLook.FLOOR_MIN_UP - sqrt(0.5)) > 1e-4:
		return "the floor threshold %s is not 45 degrees" % LevelLook.FLOOR_MIN_UP
	return ""


func test_wall_material_carries_the_plating_of_every_kind() -> String:
	var look: Dictionary = LevelLook.FALLBACK
	var material: ShaderMaterial = LevelLook.wall_material(look, look["wall_color"])
	var expected: Dictionary = {
		"plate_size": Vector3(look["plate_floor_m"], look["plate_wall_m"], look["plate_ceiling_m"]),
		"plate_aspect": Vector3(look["plate_floor_aspect"], look["plate_wall_aspect"], look["plate_ceiling_aspect"]),
		"plate_stagger": Vector3(look["plate_floor_stagger"], look["plate_wall_stagger"], look["plate_ceiling_stagger"]),
		"seam_width": look["plate_seam_m"], "plate_contrast": look["plate_contrast"],
		"floor_min_up": LevelLook.FLOOR_MIN_UP,
	}
	for parameter: String in expected:
		var value: Variant = material.get_shader_parameter(parameter)
		var same: bool = (value as Vector3).is_equal_approx(expected[parameter]) if value is Vector3 \
				else is_equal_approx(float(value), float(expected[parameter]))
		if not same:
			return "%s is %s, expected %s" % [parameter, value, expected[parameter]]
	var code: String = (load(LevelLook.WALL_SHADER) as Shader).code
	for needle: String in ["floor_min_up", "plate_stagger", "fwidth(cell.x)", "on_seam"]:
		if not code.contains(needle):
			return "the wall shader does not use %s" % needle
	return ""
