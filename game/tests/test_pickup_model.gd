extends RefCounted

## `PickupModel` (#1308, GFX-2, ARC-4, ARC-5, GFX-4): a model parses from
## data with every bad field named, builds one primitive per piece with a lit
## body and glowing pieces, changes with each documented key, adds no light,
## and an empty model leaves the holder as it was.


static func valid_model() -> Dictionary:
	return {
		"body": {"albedo": [0.3, 0.3, 0.3], "roughness": 0.4, "metallic": 0.8},
		"pieces": [
			{"shape": "box", "size": [0.3, 0.2, 0.4], "offset": [0.0, 0.0, 0.3]},
			{"shape": "cylinder", "size": [0.1, 0.5, 0.1], "offset": [0.0, 0.0, -0.4], "turn": [90.0, 0.0, 0.0]},
			{"shape": "sphere", "size": [0.1, 0.1, 0.1], "offset": [0.0, 0.0, -0.9], "glow": true},
		],
	}


static func glow_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.emission = Color(0.2, 0.9, 0.4)
	return material


## What was built for `data` (raw JSON values) under a fresh holder, one
## `{"mesh", "transform", "material"}` per piece.
static func built(data: Dictionary, glow: Material = null) -> Array[Dictionary]:
	var parsed: Dictionary = PickupModel.parse("model", data)
	var pieces: Array[Dictionary] = []
	if parsed.has("error"):
		return pieces
	var holder: Node3D = Node3D.new()
	PickupModel.new().dress(holder, "key", parsed, glow if glow != null else glow_material())
	for child: Node in PickupModel.model_of(holder).get_children():
		var piece: MeshInstance3D = child as MeshInstance3D
		pieces.append({"mesh": piece.mesh, "transform": piece.transform, "material": piece.material_override})
	holder.free()
	return pieces


func test_a_model_builds_one_piece_each_with_a_lit_body_and_a_glowing_core() -> String:
	var glow: StandardMaterial3D = glow_material()
	var pieces: Array[Dictionary] = built(valid_model(), glow)
	if pieces.size() != 3:
		return "%d pieces built" % pieces.size()
	var body: StandardMaterial3D = pieces[0]["material"] as StandardMaterial3D
	if body == null or body.emission_enabled or not is_equal_approx(body.metallic, 0.8) \
			or not is_equal_approx(body.roughness, 0.4):
		return "the body is not a lit metal: %s" % body
	if pieces[1]["material"] != body:
		return "two body pieces of one look do not share their material"
	if pieces[2]["material"] != glow:
		return "the glow piece does not take the view's glowing material"
	if not (pieces[0]["transform"] as Transform3D).origin.is_equal_approx(Vector3(0.0, 0.0, 0.3)):
		return "the first piece sits at %s" % (pieces[0]["transform"] as Transform3D).origin
	if not (pieces[1]["mesh"] is CylinderMesh):
		return "the second piece is a %s" % pieces[1]["mesh"]
	return ""


func test_each_documented_key_changes_the_result() -> String:
	var base: Array[Dictionary] = built(valid_model())
	var edits: Dictionary = {
		"body.albedo": func(m: Dictionary) -> void: m["body"]["albedo"] = [0.9, 0.1, 0.1],
		"body.roughness": func(m: Dictionary) -> void: m["body"]["roughness"] = 0.9,
		"body.metallic": func(m: Dictionary) -> void: m["body"]["metallic"] = 0.1,
		"pieces.shape": func(m: Dictionary) -> void: m["pieces"][0]["shape"] = "torus",
		"pieces.size": func(m: Dictionary) -> void: m["pieces"][0]["size"] = [0.5, 0.5, 0.5],
		"pieces.offset": func(m: Dictionary) -> void: m["pieces"][0]["offset"] = [0.2, 0.0, 0.3],
		"pieces.turn": func(m: Dictionary) -> void: m["pieces"][0]["turn"] = [0.0, 45.0, 0.0],
		"pieces.glow": func(m: Dictionary) -> void: m["pieces"][0]["glow"] = true,
		"pieces": func(m: Dictionary) -> void: (m["pieces"] as Array).pop_back(),
	}
	for key: String in edits:
		var model: Dictionary = valid_model().duplicate(true)
		(edits[key] as Callable).call(model)
		var pieces: Array[Dictionary] = built(model)
		if pieces.is_empty():
			return "editing %s made the model fail to parse" % key
		if _signature(pieces) == _signature(base):
			return "editing %s changed nothing drawn" % key
	return ""


func test_a_bad_model_is_rejected_with_the_field_named() -> String:
	var bad: Dictionary = {
		"model.body": func(m: Dictionary) -> void: m["body"] = 1,
		"model.body.albedo": func(m: Dictionary) -> void: m["body"]["albedo"] = [1.0, 2.0, 0.0],
		"model.body.roughness": func(m: Dictionary) -> void: m["body"]["roughness"] = 1.5,
		"model.body\" is missing key \"metallic": func(m: Dictionary) -> void: m["body"].erase("metallic"),
		"model.body\" has unknown key \"shine": func(m: Dictionary) -> void: m["body"]["shine"] = 1,
		"model.pieces": func(m: Dictionary) -> void: m["pieces"] = [],
		"model.pieces[0].shape": func(m: Dictionary) -> void: m["pieces"][0]["shape"] = "teapot",
		"model.pieces[1].size": func(m: Dictionary) -> void: m["pieces"][1]["size"] = [0.0, 1.0, 1.0],
		"model.pieces[0].offset": func(m: Dictionary) -> void: m["pieces"][0]["offset"] = [9.0, 0.0, 0.0],
		"model.pieces[1].turn": func(m: Dictionary) -> void: m["pieces"][1]["turn"] = [90.0, 0.0],
		"model.pieces[2].glow": func(m: Dictionary) -> void: m["pieces"][2]["glow"] = 1,
		"model.pieces[0]\" has unknown key \"light": func(m: Dictionary) -> void: m["pieces"][0]["light"] = true,
		"more than 8 pieces": func(m: Dictionary) -> void: m["pieces"] = valid_model()["pieces"] + valid_model()["pieces"] + valid_model()["pieces"],
		"model\" is missing key \"body": func(m: Dictionary) -> void: m.erase("body"),
	}
	if PickupModel.parse("model", valid_model()).has("error"):
		return "the valid model was rejected: %s" % PickupModel.parse("model", valid_model())
	for field: String in bad:
		var model: Dictionary = valid_model().duplicate(true)
		(bad[field] as Callable).call(model)
		var parsed: Dictionary = PickupModel.parse("model", model)
		if not String(parsed.get("error", "")).contains(field):
			return "%s: %s" % [field, parsed]
	return ""


func test_an_empty_model_removes_the_built_one_and_a_new_key_rebuilds() -> String:
	var models: PickupModel = PickupModel.new()
	var holder: Node3D = Node3D.new()
	var model: Dictionary = PickupModel.parse("model", valid_model())
	models.dress(holder, "a", model, glow_material())
	var first: Node3D = PickupModel.model_of(holder)
	models.dress(holder, "a", model, glow_material())
	var problem: String = ""
	if PickupModel.model_of(holder) != first or holder.get_child_count() != 1:
		problem = "dressing again with the same key rebuilt the model"
	models.dress(holder, "b", model, glow_material())
	if problem == "" and (PickupModel.model_of(holder) == first or holder.get_child_count() != 1):
		problem = "a new key did not replace the model"
	models.dress(holder, "b", {}, null)
	if problem == "" and (PickupModel.model_of(holder) != null or holder.get_child_count() != 0):
		problem = "an empty model left %d children" % holder.get_child_count()
	holder.free()
	return problem


func test_a_model_adds_no_light_and_states_its_cost() -> String:
	var models: PickupModel = PickupModel.new()
	var holder: Node3D = Node3D.new()
	var model: Dictionary = PickupModel.parse("model", valid_model())
	models.dress(holder, "a", model, glow_material())
	var lights: Array[Node] = holder.find_children("*", "Light3D", true, false)
	holder.free()
	if not lights.is_empty():
		return "the model added %d lights" % lights.size()
	var cost: Dictionary = models.cost(model)
	if cost["draw_calls"] != 3 or int(cost["triangles"]) <= 0:
		return "cost %s" % cost
	return ""


static func _signature(pieces: Array[Dictionary]) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for piece: Dictionary in pieces:
		var material: StandardMaterial3D = piece["material"] as StandardMaterial3D
		parts.append("%s %s %s %s %s %s" % [(piece["mesh"] as Mesh).get_class(), piece["transform"], material.albedo_color,
			material.roughness, material.metallic, material.emission_enabled])
	return " | ".join(parts)
