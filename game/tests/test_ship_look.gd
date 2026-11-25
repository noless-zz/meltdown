extends RefCounted

## `ShipLook` (#1362, GFX-2, ARC-4, NAM-3): the shipped file parses, every
## bad field is named, and a refused or missing file keeps the plain hull.


static func shipped_raw() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(ShipLook.PATH))


## The shipped data with `change` applied to a deep copy.
static func changed(change: Callable) -> Dictionary:
	var raw: Dictionary = shipped_raw().duplicate(true)
	change.call(raw)
	return raw


func test_the_shipped_look_parses_within_the_piece_budget() -> String:
	var look: ShipLook = ShipLook.load_file()
	if look.error != "":
		return "the shipped look was refused: %s" % look.error
	var pieces: Array = look.look["pieces"]
	if pieces.size() < 6 or pieces.size() > ShipLook.MAX_PIECES:
		return "%d pieces; want a recognisable ship within %d" % [pieces.size(), ShipLook.MAX_PIECES]
	var glowing: int = 0
	for piece: Dictionary in pieces:
		glowing += 1 if piece["material"] == ShipLook.ENGINE else 0
	if glowing == 0:
		return "no piece glows as the engine"
	if look.look["materials"].size() < 2:
		return "the ship is drawn in one material"
	return ""


func test_bad_fields_are_named() -> String:
	var cases: Dictionary = {
		"\"materials.hull.roughness\"": func(raw: Dictionary) -> void: raw["materials"]["hull"]["roughness"] = 2.0,
		"\"materials.hull.albedo\"": func(raw: Dictionary) -> void: raw["materials"]["hull"]["albedo"] = "white",
		"reserved": func(raw: Dictionary) -> void: raw["materials"]["engine"] = raw["materials"]["hull"],
		"\"engine.full_energy\"": func(raw: Dictionary) -> void: raw["engine"]["full_energy"] = 0.1,
		"\"engine\" is missing": func(raw: Dictionary) -> void: (raw["engine"] as Dictionary).erase("color"),
		"\"pieces[0].shape\"": func(raw: Dictionary) -> void: raw["pieces"][0]["shape"] = "teapot",
		"\"pieces[1].material\"": func(raw: Dictionary) -> void: raw["pieces"][1]["material"] = "gold",
		"\"pieces[2].offset\"": func(raw: Dictionary) -> void: raw["pieces"][2]["offset"] = [0.0, 9.0, 0.0],
		"\"pieces[3].size\"": func(raw: Dictionary) -> void: raw["pieces"][3]["size"] = [0.1, 0.1],
		"unknown key \"glow\"": func(raw: Dictionary) -> void: raw["pieces"][0]["glow"] = true,
		"more than": func(raw: Dictionary) -> void: _fill(raw["pieces"]),
		"\"pieces\" must be a list": func(raw: Dictionary) -> void: raw["pieces"] = [],
	}
	for wanted: String in cases:
		var look: ShipLook = ShipLook.new()
		look.use(changed(cases[wanted]))
		if not look.error.contains(wanted):
			return "want an error naming %s, got \"%s\"" % [wanted, look.error]
		if look.look["pieces"].size() != ShipLook.PLAIN["pieces"].size():
			return "a refused look (%s) did not fall back to the plain hull" % wanted
	return ""


func test_a_missing_file_keeps_the_plain_hull() -> String:
	var look: ShipLook = ShipLook.load_file("res://view/no_such_ship_look.json")
	if not look.error.contains("missing"):
		return "the error is \"%s\"" % look.error
	if look.look.is_empty() or look.look["pieces"].size() != ShipLook.PLAIN["pieces"].size():
		return "no plain hull: %s" % look.look
	return ""


func test_the_plain_hull_parses() -> String:
	var parsed: Dictionary = ShipLook.parse(ShipLook.PLAIN)
	return "the plain hull is refused: %s" % parsed["error"] if parsed.has("error") else ""


func test_pieces_of_one_material_share_it() -> String:
	var look: ShipLook = ShipLook.load_file()
	if look.material("hull") != look.material("hull"):
		return "two calls give two hull materials"
	var hull: StandardMaterial3D = look.material("hull")
	var data: Dictionary = look.look["materials"]["hull"]
	if hull.emission_enabled or not is_equal_approx(hull.roughness, data["roughness"]) \
			or not is_equal_approx(hull.metallic, data["metallic"]):
		return "the hull is not the file's lit metal: roughness %.2f metallic %.2f" % [hull.roughness, hull.metallic]
	return ""


static func _fill(pieces: Array) -> void:
	while pieces.size() <= ShipLook.MAX_PIECES:
		pieces.append(pieces[0].duplicate(true))
