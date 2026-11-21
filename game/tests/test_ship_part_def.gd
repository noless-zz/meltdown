extends RefCounted

## Shield, hull and engine parts as data (SLV-2, CRF-3, CRW-3, ARC-4, #1030):
## each load error names the file and key, `apply` multiplies a copy of the
## ship data in a fixed order and keeps it inside `ShipTuning.RANGES`, and
## every non-weapon upgrade grants a shipped part of its kind.

const SHIP_FILE: String = "res://data/ships/default_ship.json"


static func _text(data: Dictionary) -> String:
	return JSON.stringify(data)


static func _good(stats: Dictionary = {"max_shield": 1.2}, kind: String = "shield") -> Dictionary:
	return {"id": "p", "name": "Test Part", "kind": kind, "stats": stats}


static func _part(id: String, kind: String, stats: Dictionary) -> ShipPartDef:
	var part: ShipPartDef = ShipPartDef.parse_json(_text({"id": id, "name": id, "kind": kind, "stats": stats}), id + ".json")
	assert(part.error == "", part.error)
	return part


static func _ship_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SHIP_FILE))


static func _shipped() -> Dictionary:
	var parts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ShipPartDef.PARTS_DIR):
		if file.ends_with(".json"):
			parts[file] = ShipPartDef.parse_json(
				FileAccess.get_file_as_string(ShipPartDef.PARTS_DIR.path_join(file)), file)
	return parts


static func _hash_of(data: Dictionary) -> int:
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	assert(tuning.error == "", tuning.error)
	var ship: ShipState = ShipState.new()
	tuning.apply_to(ship)
	return ship.state_hash()


func test_good_part_loads() -> String:
	var part: ShipPartDef = ShipPartDef.parse_json(_text(_good()), "p.json")
	if part.error != "":
		return part.error
	if part.id != "p" or part.display_name != "Test Part" or part.kind != "shield" or part.stats != {"max_shield": 1.2}:
		return "fields not read: %s %s %s %s" % [part.id, part.display_name, part.kind, part.stats]
	return ""


func test_each_load_error_names_file_and_key() -> String:
	var unknown: Dictionary = _good()
	unknown["colour"] = "red"
	var no_stats: Dictionary = _good()
	no_stats.erase("stats")
	var bad_kind: Dictionary = _good()
	bad_kind["kind"] = "weapon"
	var cases: Array = [
		["p.json", "{", "p.json: invalid JSON"],
		["p.json", "[]", "p.json: top level must be a JSON object"],
		["p.json", _text(unknown), "p.json: unknown key \"colour\""],
		["p.json", _text(no_stats), "p.json: missing key \"stats\""],
		["q.json", _text(_good()), "q.json: key \"id\" is \"p\", must match the file name"],
		["p.json", _text(bad_kind), "p.json: key \"kind\" must be one of"],
		["p.json", _text(_good({"max_speed": 1.2})), "p.json: stats key \"max_speed\" is not allowed for kind shield"],
		["p.json", _text(_good({"max_shield": 1.6})), "p.json: stats key \"max_shield\" is 1.6, must be 0.5 to 1.5"],
		["p.json", _text(_good({"max_shield": 0.4})), "p.json: stats key \"max_shield\" is 0.4, must be 0.5 to 1.5"],
		["p.json", _text(_good({"max_shield": true})), "p.json: stats key \"max_shield\" must be a number"],
		["p.json", _text(_good({"wall_damage_per_speed": 1.1}, "module")), "p.json: stats key \"wall_damage_per_speed\" is not allowed for kind module"],
	]
	for case: Array in cases:
		var part: ShipPartDef = ShipPartDef.parse_json(case[1], case[0])
		if not part.error.begins_with(case[2]):
			return "expected \"%s\", got \"%s\"" % [case[2], part.error]
	return ""


func test_every_kind_accepts_its_keys_at_the_limits() -> String:
	for kind: String in ShipPartDef.KINDS:
		var stats: Dictionary = {}
		var flip: bool = false
		for key: String in ShipPartDef.STAT_KEYS[kind]:
			stats[key] = ShipPartDef.MULTIPLIER_MAX if flip else ShipPartDef.MULTIPLIER_MIN
			flip = not flip
		var part: ShipPartDef = ShipPartDef.parse_json(_text(_good(stats, kind)), "p.json")
		if part.error != "":
			return "%s: %s" % [kind, part.error]
		for key: String in stats:
			if not ShipTuning.KEYS.has(key):
				return "%s allows %s, which is not a ship tuning key" % [kind, key]
	return ""


func test_no_parts_keeps_the_state_hash_and_input() -> String:
	var data: Dictionary = _ship_data()
	var before: Dictionary = data.duplicate(true)
	var none: Array[ShipPartDef] = []
	var result: Dictionary = ShipPartDef.apply(data, none)
	if result != data:
		return "no parts changed the data"
	if _hash_of(result) != _hash_of(data):
		return "no parts changed the state hash"
	if data != before:
		return "apply edited its argument"
	return ""


func test_shield_part_raises_max_shield_by_its_multiplier() -> String:
	var data: Dictionary = _ship_data()
	var parts: Array[ShipPartDef] = [_part("s", "shield", {"max_shield": 1.3})]
	var result: Dictionary = ShipPartDef.apply(data, parts)
	if not is_equal_approx(float(result["max_shield"]), float(data["max_shield"]) * 1.3):
		return "max_shield %s, want %s" % [result["max_shield"], float(data["max_shield"]) * 1.3]
	if result["max_hull"] != data["max_hull"]:
		return "a shield part changed max_hull"
	if data["max_shield"] != _ship_data()["max_shield"]:
		return "apply edited its argument"
	if ShipTuning.parse_json(JSON.stringify(result)).error != "":
		return "result no longer parses"
	return ""


func test_two_parts_combine_the_same_in_any_order() -> String:
	var data: Dictionary = _ship_data()
	var a: ShipPartDef = _part("a", "engine", {"max_speed": 1.3, "acceleration": 0.7})
	var b: ShipPartDef = _part("b", "engine", {"max_speed": 1.1, "afterburner_drain": 0.9})
	var forward: Array[ShipPartDef] = [a, b]
	var backward: Array[ShipPartDef] = [b, a]
	var one: Dictionary = ShipPartDef.apply(data, forward)
	var two: Dictionary = ShipPartDef.apply(data, backward)
	if one != two:
		return "order changed the result: %s vs %s" % [one, two]
	if _hash_of(one) != _hash_of(two):
		return "order changed the state hash"
	if forward[0] != a:
		return "apply reordered its argument"
	return ""


func test_results_stay_inside_the_ranges() -> String:
	var data: Dictionary = _ship_data()
	data["max_speed"] = 190.0
	data["afterburner_max_speed"] = 200.0
	data["max_shield"] = 9000.0
	var parts: Array[ShipPartDef] = [
		_part("e", "engine", {"max_speed": 1.5, "afterburner_max_speed": 0.5}),
		_part("s", "shield", {"max_shield": 1.5}),
	]
	var result: Dictionary = ShipPartDef.apply(data, parts)
	if result["max_speed"] != 200.0:
		return "max_speed %s, want the cap 200" % result["max_speed"]
	if result["afterburner_max_speed"] != result["max_speed"]:
		return "afterburner_max_speed %s fell below max_speed %s" % [result["afterburner_max_speed"], result["max_speed"]]
	if result["max_shield"] != 10000.0:
		return "max_shield %s, want the cap 10000" % result["max_shield"]
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(result))
	if tuning.error != "":
		return tuning.error
	return ""


func test_shipped_parts_load_with_two_per_kind() -> String:
	var counts: Dictionary = {}
	var parts: Dictionary = _shipped()
	for file: String in parts:
		var part: ShipPartDef = parts[file]
		if part.error != "":
			return part.error
		counts[part.kind] = int(counts.get(part.kind, 0)) + 1
	for kind: String in ["shield", "hull", "engine"]:
		if int(counts.get(kind, 0)) < 2:
			return "kind %s has %d parts, want at least 2" % [kind, counts.get(kind, 0)]
	return ""


func test_non_weapon_upgrades_grant_a_part_of_their_kind() -> String:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	var tree: UpgradeTree = UpgradeTree.parse(texts)
	if tree.error != "":
		return tree.error
	var parts: Dictionary = _shipped()
	for upgrade: UpgradeDef in tree.upgrades:
		if upgrade.kind == "weapon":
			continue
		var file: String = upgrade.grants + ".json"
		if not parts.has(file):
			return "%s upgrade %s grants %s, not a file in %s" % [upgrade.kind, upgrade.id, upgrade.grants, ShipPartDef.PARTS_DIR]
		var part: ShipPartDef = parts[file]
		if part.kind != upgrade.kind:
			return "upgrade %s is kind %s but part %s is kind %s" % [upgrade.id, upgrade.kind, part.id, part.kind]
	return ""
