extends RefCounted

## Upgrade tree as data (CRF-3, CRF-6, CRF-7, ARC-4, #962): each load failure
## names the file and key, the shipped tree loads and has the required shape,
## and `missing()` gives one reason without changing anything.

const SCRATCH_DIR: String = "user://test_upgrade_tree"
const WEAPONS_DIR: String = "res://data/weapons"


static func _text(id: String, tier: int, requires: Array, cost: Dictionary, branch: String = "engines", kind: String = "engine") -> String:
	return JSON.stringify({
		"id": id, "name": id.capitalize(), "branch": branch, "kind": kind, "tier": tier,
		"requires": requires, "cost": cost, "grants": id,
	})


## A small valid tree: a (tier 1) <- b (tier 2) <- c (tier 3).
static func _good() -> Dictionary:
	return {
		"a.json": _text("a", 1, [], {"scrap_alloy": 2}),
		"b.json": _text("b", 2, ["a"], {"scrap_alloy": 1, "circuit_shards": 3}),
		"c.json": _text("c", 3, ["b"], {"core_glass": 1}),
	}


## Writes `texts` into a fresh scratch folder and reads the folder back the way
## a caller of `UpgradeTree.parse` does.
static func _through_folder(texts: Dictionary) -> UpgradeTree:
	var dir: String = ProjectSettings.globalize_path(SCRATCH_DIR)
	if DirAccess.dir_exists_absolute(dir):
		for file: String in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.make_dir_recursive_absolute(dir)
	for file: Variant in texts:
		var out: FileAccess = FileAccess.open(dir.path_join(str(file)), FileAccess.WRITE)
		out.store_string(texts[file])
		out.close()
	return UpgradeTree.parse(_read_folder(dir))


static func _read_folder(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _shipped() -> UpgradeTree:
	return UpgradeTree.parse(_read_folder(UpgradeTree.UPGRADES_DIR))


static func _components() -> ComponentList:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(ComponentList.COMPONENTS_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(ComponentList.COMPONENTS_DIR.path_join(file))
	return ComponentList.parse(texts)


func test_good_scratch_folder_loads() -> String:
	var tree: UpgradeTree = _through_folder(_good())
	if tree.error != "":
		return tree.error
	var b: UpgradeDef = tree.get_upgrade("b")
	if tree.upgrades.size() != 3 or b == null:
		return "expected a, b and c"
	if b.display_name != "B" or b.branch != "engines" or b.kind != "engine" or b.tier != 2 or b.requires != ["a"] or b.grants != "b":
		return "fields not read"
	if b.cost != {"circuit_shards": 3, "scrap_alloy": 1}:
		return "cost read as %s" % b.cost
	return ""


func test_each_load_failure_names_file_and_key() -> String:
	var cases: Array = [
		["dup.json", _text("a", 1, [], {"scrap_alloy": 1}), "dup.json: key \"id\" is \"a\", already used by a.json"],
		["d.json", _text("d", 1, [], {"scrap_alloy": 1}, "armour", "hull"), "d.json: key \"branch\""],
		["d.json", _text("d", 1, [], {"scrap_alloy": 1}, "defence", "plating"), "d.json: key \"kind\""],
		["d.json", _text("d", 2, ["nope"], {"scrap_alloy": 1}), "d.json: key \"requires\" names \"nope\", which is no upgrade"],
		["d.json", _text("d", 2, ["a"], {"scrap_alloy": 0}), "d.json: key \"cost\""],
		["d.json", _text("d", 2, ["a"], {"scrap_alloy": 1.5}), "d.json: key \"cost\""],
		["d.json", _text("d", 2, ["a"], {"scrap_alloy": -2}), "d.json: key \"cost\""],
		["d.json", _text("d", 2, ["a"], {"scrap_alloy": "3"}), "d.json: key \"cost\""],
		["d.json", _text("d", 2, ["a"], {}), "d.json: key \"cost\""],
		["d.json", _text("d", 2, ["b"], {"scrap_alloy": 1}), "d.json: key \"tier\" is 2, must be above tier 2 of required \"b\""],
		["d.json", _text("d", 1, ["a"], {"scrap_alloy": 1}), "d.json: key \"tier\" is 1, must be above tier 1 of required \"a\""],
		["d.json", _text("d", 0, [], {"scrap_alloy": 1}), "d.json: key \"tier\""],
		["d.json", _text("d", 1, [], {"scrap_alloy": 1}).replace("\"grants\"", "\"grant\""), "d.json: unknown key \"grant\""],
	]
	for case: Array in cases:
		var texts: Dictionary = _good()
		texts[case[0]] = case[1]
		var tree: UpgradeTree = _through_folder(texts)
		if not tree.error.begins_with(case[2]):
			return "expected \"%s\", got \"%s\"" % [case[2], tree.error]
		if not tree.upgrades.is_empty() or tree.has_upgrade("a"):
			return "a rejected tree kept upgrades"
	return ""


func test_cycle_is_named() -> String:
	var texts: Dictionary = _good()
	texts["a.json"] = _text("a", 1, ["c"], {"scrap_alloy": 2})
	var tree: UpgradeTree = _through_folder(texts)
	if tree.error != "a.json: key \"requires\" forms a cycle: a -> c -> b -> a":
		return "cycle gave \"%s\"" % tree.error
	texts = _good()
	texts["s.json"] = _text("s", 2, ["s"], {"scrap_alloy": 1})
	tree = _through_folder(texts)
	if tree.error != "s.json: key \"requires\" forms a cycle: s -> s":
		return "self cycle gave \"%s\"" % tree.error
	return ""


func test_shipped_tree_loads_with_two_per_branch_and_a_tier_two() -> String:
	var tree: UpgradeTree = _shipped()
	if tree.error != "":
		return tree.error
	for branch: String in UpgradeDef.BRANCHES:
		var count: int = 0
		var linked: bool = false
		for upgrade: UpgradeDef in tree.upgrades:
			if upgrade.branch != branch:
				continue
			count += 1
			for required: String in upgrade.requires:
				if upgrade.tier == 2 and tree.get_upgrade(required).tier == 1:
					linked = true
		if count < 2:
			return "branch %s has %d upgrades" % [branch, count]
		if not linked:
			return "branch %s has no tier-2 upgrade requiring a tier-1 one" % branch
	return ""


func test_shipped_ids_match_files_and_weapons_exist() -> String:
	var weapons: PackedStringArray = DirAccess.get_files_at(WEAPONS_DIR)
	var files: PackedStringArray = DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR)
	for upgrade: UpgradeDef in _shipped().upgrades:
		if not files.has(upgrade.id + ".json"):
			return "upgrade %s is not in %s.json" % [upgrade.id, upgrade.id]
		if upgrade.kind == "weapon" and not weapons.has(upgrade.grants + ".json"):
			return "weapon upgrade %s grants %s, not a file in %s" % [upgrade.id, upgrade.grants, WEAPONS_DIR]
	return ""


func test_shipped_costs_name_component_kinds() -> String:
	var components: ComponentList = _components()
	if components.error != "":
		return components.error
	for upgrade: UpgradeDef in _shipped().upgrades:
		for kind: String in upgrade.cost:
			if not components.has_kind(kind):
				return "%s costs \"%s\", which is no component kind" % [upgrade.id, kind]
	return ""


## CRF-7: each tier above 1 uses at least one component kind that no lower tier
## uses, so climbing the tree needs components from deeper down.
func test_shipped_higher_tiers_need_new_kinds() -> String:
	var by_tier: Dictionary[int, Array] = {}
	for upgrade: UpgradeDef in _shipped().upgrades:
		if not by_tier.has(upgrade.tier):
			by_tier[upgrade.tier] = []
		for kind: String in upgrade.cost:
			if not by_tier[upgrade.tier].has(kind):
				by_tier[upgrade.tier].append(kind)
	var tiers: Array[int] = []
	tiers.assign(by_tier.keys())
	tiers.sort()
	if tiers.size() < 2:
		return "the shipped tree has only one tier"
	var lower: Array = []
	for tier: int in tiers:
		var fresh: bool = false
		for kind: Variant in by_tier[tier]:
			if not lower.has(kind):
				fresh = true
		if tier > tiers[0] and not fresh:
			return "tier %d uses only kinds lower tiers use: %s" % [tier, by_tier[tier]]
		lower.append_array(by_tier[tier])
	return ""


func test_missing_gives_each_reason() -> String:
	var tree: UpgradeTree = UpgradeTree.parse(_good())
	var none: Array[String] = []
	var a_done: Array[String] = ["a"]
	var cases: Array = [
		["zz", none, {}, "unknown upgrade \"zz\""],
		["a", a_done, {"scrap_alloy": 9}, "\"a\" is already crafted"],
		["b", none, {"scrap_alloy": 9, "circuit_shards": 9}, "\"b\" needs \"a\" crafted first"],
		["b", a_done, {"scrap_alloy": 1, "circuit_shards": 1}, "\"b\" is short of 2 circuit_shards (needs 3, has 1)"],
		["b", a_done, {"circuit_shards": 3}, "\"b\" is short of 1 scrap_alloy (needs 1, has 0)"],
		["a", none, {"scrap_alloy": 2}, ""],
		["b", a_done, {"scrap_alloy": 1, "circuit_shards": 3}, ""],
	]
	for case: Array in cases:
		var crafted: Array[String] = case[1]
		var banked: Dictionary = case[2]
		var crafted_before: Array[String] = crafted.duplicate()
		var banked_before: Dictionary = banked.duplicate()
		var reason: String = tree.missing(case[0], crafted, banked)
		if reason != case[3]:
			return "missing(%s) expected \"%s\", got \"%s\"" % [case[0], case[3], reason]
		if crafted != crafted_before or banked != banked_before:
			return "missing(%s) changed its arguments" % case[0]
	return ""


func test_same_input_same_result() -> String:
	var texts: Dictionary = _read_folder(UpgradeTree.UPGRADES_DIR)
	var reversed: Dictionary = {}
	var files: Array = texts.keys()
	files.reverse()
	for file: Variant in files:
		reversed[file] = texts[file]
	var one: UpgradeTree = UpgradeTree.parse(texts)
	var two: UpgradeTree = UpgradeTree.parse(reversed)
	var ids_one: Array[String] = []
	var ids_two: Array[String] = []
	for upgrade: UpgradeDef in one.upgrades:
		ids_one.append(upgrade.id)
	for upgrade: UpgradeDef in two.upgrades:
		ids_two.append(upgrade.id)
	if ids_one != ids_two:
		return "order depends on file order"
	var crafted: Array[String] = []
	var banked: Dictionary = {"scrap_alloy": 3}
	for upgrade: UpgradeDef in one.upgrades:
		if one.missing(upgrade.id, crafted, banked) != two.missing(upgrade.id, crafted, banked):
			return "missing(%s) differs between loads" % upgrade.id
	return ""
