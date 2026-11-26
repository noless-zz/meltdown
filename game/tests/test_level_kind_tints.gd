extends RefCounted

## One wall surface per box (#1383, PRF-4, PRF-2, GFX-3, GFX-2): a box of the
## mine draws its floor, walls, ceiling and opening frames in one surface and
## its bevels in one more, so two draw calls a box. The wall material carries
## the three tints from `level_look.json` (ARC-4) and the shader picks one per
## face by the same rule as `LevelLook.surface_class`, so the look is the one
## the three surfaces per kind drew before.

const G2_FILE: String = "res://data/levels/g2_level.json"
const Levels := preload("res://tests/bot_sweep_levels.gd")


func _g2() -> BoxUnion:
	return LevelDef.parse_json(FileAccess.get_file_as_string(G2_FILE)).union


## The tint uniform the shader reads for a face pointing along `normal`,
## mirroring its rule: up beyond `floor_min_up` is a floor, down beyond it a
## ceiling, the rest walls.
static func _picked(material: ShaderMaterial, normal: Vector3) -> Color:
	var up: float = normal.normalized().y
	var floor_min_up: float = float(material.get_shader_parameter("floor_min_up"))
	if material.get_shader_parameter("tint_by_kind") != true:
		return material.get_shader_parameter("tint")
	if up > floor_min_up:
		return material.get_shader_parameter("floor_tint")
	if up < -floor_min_up:
		return material.get_shader_parameter("ceiling_tint")
	return material.get_shader_parameter("tint")


func test_the_wall_material_carries_the_three_tints_of_the_look() -> String:
	var look: Dictionary = LevelLook.FALLBACK.duplicate()
	# Tints are data: a look with other colours gives a material with those.
	look["floor_color"] = Color(0.5, 0.1, 0.1)
	look["wall_color"] = Color(0.1, 0.5, 0.1)
	look["ceiling_color"] = Color(0.1, 0.1, 0.5)
	var material: ShaderMaterial = LevelViewMeshes.kind_material(look)
	var expected: Dictionary = {"tint_by_kind": true, "floor_tint": look["floor_color"],
		"tint": look["wall_color"], "ceiling_tint": look["ceiling_color"],
		"floor_min_up": LevelLook.FLOOR_MIN_UP}
	for parameter: String in expected:
		if material.get_shader_parameter(parameter) != expected[parameter]:
			return "%s is %s, expected %s" % [parameter, material.get_shader_parameter(parameter), expected[parameter]]
	# Single-tint materials (bevels, the test tunnel) keep one tint for every face.
	var plain: ShaderMaterial = LevelLook.wall_material(look, look["floor_color"])
	if plain.get_shader_parameter("tint_by_kind") == true:
		return "a plain wall material picks its tint by face"
	return ""


func test_the_shader_picks_the_tint_by_the_face_kind() -> String:
	var code: String = FileAccess.get_file_as_string(LevelLook.WALL_SHADER)
	# `kind` is (floor, wall, ceiling), set from `floor_min_up`; the base colour
	# is the tint it picks.
	for needle: String in ["uniform bool tint_by_kind", "uniform vec3 floor_tint", "uniform vec3 ceiling_tint",
			"floor_tint * kind.x + tint * kind.y + ceiling_tint * kind.z", "vec3 base = face_tint",
			"if (up > floor_min_up)", "} else if (up < -floor_min_up)"]:
		if not code.contains(needle):
			return "the wall shader lacks \"%s\"" % needle
	if code.contains("vec3 base = tint "):
		return "the wall shader still bases the colour on the plain tint"
	return ""


func test_every_face_gets_the_tint_its_own_surface_had() -> String:
	var view: LevelView = LevelView.new()
	view.build(_g2())
	var result: String = ""
	var kinds: Dictionary = {}
	for box: int in view.box_count():
		var walls: MeshInstance3D = view.walls_of(box)
		if walls == null or walls.mesh == null:
			continue
		var material: ShaderMaterial = walls.mesh.surface_get_material(0) as ShaderMaterial
		var normals: PackedVector3Array = walls.mesh.surface_get_arrays(0)[Mesh.ARRAY_NORMAL]
		for normal: Vector3 in normals:
			kinds[LevelLook.surface_class(normal)] = true
			if _picked(material, normal) != LevelLook.tint_for(view.look(), normal):
				result = "box %d draws a face pointing %s in %s, not %s" % [box, normal,
						_picked(material, normal), LevelLook.tint_for(view.look(), normal)]
				break
		if result != "":
			break
	if result == "" and kinds.size() != LevelLook.CLASSES.size():
		result = "G2 drew only %s faces; expected floors, walls and ceilings" % [kinds.keys()]
	view.free()
	return result


func test_each_box_draws_walls_and_frames_in_one_surface() -> String:
	var levels: Levels = Levels.new()
	var unions: Array[BoxUnion] = [_g2(), levels.level_of(levels.generate(11)).union]
	for union: BoxUnion in unions:
		var view: LevelView = LevelView.new()
		view.build(union)
		var result: String = ""
		var vertices: int = 0
		for box: int in view.box_count():
			var walls: MeshInstance3D = view.walls_of(box)
			# A box whose every face is open to others has no walls to draw.
			if walls == null:
				continue
			if walls.mesh == null or walls.mesh.get_surface_count() != 1:
				result = "box %d draws its walls in %d surfaces" % [box,
						walls.mesh.get_surface_count() if walls.mesh != null else 0]
			elif view.surfaces_of(box) > 2:
				result = "box %d costs %d draw calls, expected at most 2" % [box, view.surfaces_of(box)]
			if result != "":
				break
			vertices += (walls.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		if result == "" and vertices != (view.quads().size() + view.frames().size()) * 6:
			result = "%d wall vertices for %d quads and frames" % [vertices, view.quads().size() + view.frames().size()]
		view.free()
		if result != "":
			return result
	return ""


func test_walls_still_cast_the_headlight_shadow_and_never_glow() -> String:
	var view: LevelView = LevelView.new()
	view.build(_g2())
	var walls: MeshInstance3D = view.walls_of(0)
	var material: ShaderMaterial = walls.mesh.surface_get_material(0) as ShaderMaterial
	var glow: Variant = material.get_shader_parameter("glow")
	var result: String = ""
	if walls.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
		result = "the walls no longer block the headlight"
	elif glow != null and (glow as Color).get_luminance() > 0.0:
		result = "the walls glow; only the bevels may"
	elif view.bevels_of(0).mesh.surface_get_material(0).get_shader_parameter("tint_by_kind") == true:
		result = "the bevels pick their tint by face; they keep the wall tint"
	view.free()
	return result
