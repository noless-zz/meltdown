extends RefCounted

## The ambient rules in `level_look.json` (#1400, GFX-5, ARC-4): the shipped
## rules parse, a bad rule names its field, a box picks its size by its middle
## side, and a level built with bad rules keeps the global ambient.

const LOOK_FILE: String = "res://view/level_look.json"


func _shipped() -> Dictionary:
	var look: Dictionary = LevelLook.parse(FileAccess.get_file_as_string(LOOK_FILE))
	return AmbientRules.parse(look.get(AmbientRules.KEY))


func _rules_text() -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	return (data[AmbientRules.KEY] as Dictionary).duplicate(true)


func test_the_shipped_rules_parse() -> String:
	var rules: Dictionary = _shipped()
	if rules.has("error"):
		return "shipped rules rejected: %s" % rules["error"]
	if (rules["sizes"] as Array).size() < 2:
		return "the shipped rules give every box the same size"
	if (rules["reactor"] as Dictionary).is_empty():
		return "the shipped rules leave out the reactor's cast"
	return ""


func test_a_look_without_rules_still_parses() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	data.erase(AmbientRules.KEY)
	var look: Dictionary = LevelLook.parse(JSON.stringify(data))
	if look.has("error"):
		return "a look without rules was rejected: %s" % look["error"]
	if look.has(AmbientRules.KEY):
		return "a look without rules gained some"
	return ""


func test_a_bad_rule_names_its_field() -> String:
	var cases: Array[Array] = []
	var energy: Dictionary = _rules_text()
	energy["sizes"][1]["energy"] = 2.5
	cases.append([energy, "ambient_rules.sizes[1].energy"])
	var order: Dictionary = _rules_text()
	order["sizes"][1]["up_to_width_m"] = 1.0
	cases.append([order, "ambient_rules.sizes[1].up_to_width_m"])
	var unknown: Dictionary = _rules_text()
	unknown["reactor"]["glow"] = 1.0
	cases.append([unknown, "ambient_rules.reactor has unknown key \"glow\""])
	var colour: Dictionary = _rules_text()
	colour["sizes"][0]["color"] = [0.1, 0.2]
	cases.append([colour, "ambient_rules.sizes[0].color"])
	var missing: Dictionary = _rules_text()
	missing.erase("blend_m")
	cases.append([missing, "\"blend_m\""])
	var flag: Dictionary = _rules_text()
	flag["reactor"]["strength"] = true
	cases.append([flag, "ambient_rules.reactor.strength"])
	cases.append([[], "ambient_rules must be a JSON object"])
	for case: Array in cases:
		var parsed: Dictionary = AmbientRules.parse(JSON.parse_string(JSON.stringify(case[0])))
		if not parsed.has("error") or not String(parsed["error"]).contains(case[1]):
			return "expected an error naming %s, got %s" % [case[1], parsed]
	return ""


func test_a_box_picks_its_size_by_its_middle_side() -> String:
	var rules: Dictionary = _shipped()
	var cases: Dictionary = {
		Vector3(8, 8, 66): "tunnel", Vector3(66, 8, 8): "tunnel", Vector3(12, 8, 46): "tunnel",
		Vector3(20, 18, 30): "room", Vector3(4, 25, 25): "room", Vector3(50, 40, 60): "large room",
	}
	for size: Vector3 in cases:
		var picked: String = AmbientRules.size_for(rules, size)["name"]
		if picked != cases[size]:
			return "a %s box is a %s, expected a %s" % [size, picked, cases[size]]
	return ""


func test_bad_rules_keep_the_global_ambient() -> String:
	var path: String = "user://test_ambient_rules_bad_look.json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOOK_FILE))
	data[AmbientRules.KEY]["piece_m"] = 99
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()
	var view: LevelView = LevelView.new()
	var result: String = ""
	if view.load_look(path) != "":
		result = "the look itself was rejected for a bad rule: %s" % view.look_error
	var boxes: Array[BoxBounds] = [BoxBounds.new(Vector3(-3, -3, -20), Vector3(3, 3, 0)),
		BoxBounds.new(Vector3(-10, -6, -40), Vector3(10, 6, -18))]
	view.build(BoxUnion.new(boxes))
	if result == "" and not view.ambient_error.contains("ambient_rules.piece_m"):
		result = "the bad rule was not named: \"%s\"" % view.ambient_error
	elif result == "" and view.ambient_bake() != null:
		result = "bad rules still baked"
	var material: ShaderMaterial = view.walls_of(0).mesh.surface_get_material(0) as ShaderMaterial
	var global: Color = AmbientBake.global(view.look())
	if result == "" and material.get_shader_parameter("baked_ambient") == true:
		result = "the walls read a bake that was not made"
	elif result == "" and not (material.get_shader_parameter("ambient_light") as Vector3).is_equal_approx(
			Vector3(global.r, global.g, global.b)):
		result = "the walls' ambient is %s, not the global %s" % [material.get_shader_parameter("ambient_light"), global]
	elif result == "" and not LevelViewMeshes.baked(view.walls_of(0).mesh).is_empty():
		result = "the walls carry baked light without a bake"
	view.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	return result
