extends RefCounted

## Crafting spends banked components and records a permanent upgrade (CRF-3,
## CRF-2, RUN-7, #963). A refused craft leaves the profile byte for byte as it was.

const DIR: String = "user://test_crafting"


static func _text(id: String, branch: String, tier: int, requires: Array, cost: Dictionary) -> String:
	return JSON.stringify({
		"id": id, "name": id.capitalize(), "branch": branch, "kind": "module", "tier": tier,
		"requires": requires, "cost": cost, "grants": id,
	})


## engines: thruster (1) <- afterburner (2); weapons: gun (1); utility: scanner (1).
static func _tree() -> UpgradeTree:
	return UpgradeTree.parse({
		"thruster.json": _text("thruster", "engines", 1, [], {"scrap_alloy": 2}),
		"afterburner.json": _text("afterburner", "engines", 2, ["thruster"], {"scrap_alloy": 1, "circuit_shards": 2}),
		"gun.json": _text("gun", "weapons", 1, [], {"cell_salts": 1}),
		"scanner.json": _text("scanner", "utility", 1, [], {"scrap_alloy": 1}),
	})


static func _profile(counts: Dictionary) -> Profile:
	var profile: Profile = Profile.new()
	profile.bank(counts)
	return profile


func test_the_test_tree_loads() -> String:
	return _tree().error


func test_crafting_tier_1_then_its_tier_2_follower() -> String:
	var tree: UpgradeTree = _tree()
	var profile: Profile = _profile({"scrap_alloy": 5, "circuit_shards": 2})
	var first: String = Crafting.craft(profile, tree, "thruster")
	if first != "":
		return "thruster refused: %s" % first
	if profile.count_of("scrap_alloy") != 3 or profile.crafted != ["thruster"]:
		return "after thruster: banked %s, crafted %s" % [profile.banked, profile.crafted]
	var second: String = Crafting.craft(profile, tree, "afterburner")
	if second != "":
		return "afterburner refused: %s" % second
	if profile.banked != {"scrap_alloy": 2} or profile.crafted != ["thruster", "afterburner"]:
		return "after afterburner: banked %s, crafted %s" % [profile.banked, profile.crafted]
	return ""


func _refused(profile: Profile, id: String, expected: String) -> String:
	var before: String = profile.to_json()
	var reason: String = Crafting.craft(profile, _tree(), id)
	if reason != expected:
		return "%s: reason '%s', expected '%s'" % [id, reason, expected]
	if profile.to_json() != before:
		return "%s: profile changed by a refused craft" % id
	return ""


func test_refused_for_a_missing_prerequisite() -> String:
	return _refused(_profile({"scrap_alloy": 9, "circuit_shards": 9}), "afterburner",
		"\"afterburner\" needs \"thruster\" crafted first")


func test_refused_for_too_few_components() -> String:
	return _refused(_profile({"scrap_alloy": 1, "cell_salts": 4}), "thruster",
		"\"thruster\" is short of 1 scrap_alloy (needs 2, has 1)")


func test_refused_for_crafting_twice() -> String:
	var profile: Profile = _profile({"scrap_alloy": 9})
	if Crafting.craft(profile, _tree(), "thruster") != "":
		return "first craft refused"
	return _refused(profile, "thruster", "\"thruster\" is already crafted")


func test_refused_for_an_unknown_upgrade() -> String:
	return _refused(_profile({"scrap_alloy": 9}), "warp_drive", "unknown upgrade \"warp_drive\"")


func test_spending_exactly_the_banked_count_leaves_zero() -> String:
	var profile: Profile = _profile({"scrap_alloy": 2, "cell_salts": 3})
	if Crafting.craft(profile, _tree(), "thruster") != "":
		return "thruster refused"
	if profile.count_of("scrap_alloy") != 0 or profile.banked.has("scrap_alloy"):
		return "scrap_alloy left: %s" % profile.banked
	if profile.banked != {"cell_salts": 3}:
		return "other counts touched: %s" % profile.banked
	return ""


func test_available_lists_craftable_upgrades_by_branch_tier_and_id() -> String:
	var tree: UpgradeTree = _tree()
	var profile: Profile = _profile({"scrap_alloy": 9, "circuit_shards": 9, "cell_salts": 1})
	var expected: Array[String] = ["gun", "thruster", "scanner"]
	if Crafting.available(profile, tree) != expected:
		return "before: %s" % [Crafting.available(profile, tree)]
	Crafting.craft(profile, tree, "thruster")
	expected = ["gun", "afterburner", "scanner"]
	if Crafting.available(profile, tree) != expected:
		return "after thruster: %s" % [Crafting.available(profile, tree)]
	if not Crafting.available(Profile.new(), tree).is_empty():
		return "an empty profile can craft something"
	return ""


func test_available_orders_tiers_within_a_branch() -> String:
	var tree: UpgradeTree = UpgradeTree.parse({
		"b.json": _text("b", "defence", 2, ["a"], {"scrap_alloy": 1}),
		"z.json": _text("z", "defence", 1, [], {"scrap_alloy": 1}),
		"a.json": _text("a", "defence", 1, [], {"scrap_alloy": 1}),
		"e.json": _text("e", "engines", 1, [], {"scrap_alloy": 1}),
	})
	if tree.error != "":
		return tree.error
	var profile: Profile = _profile({"scrap_alloy": 9})
	profile.crafted.append("a")
	var expected: Array[String] = ["z", "b", "e"]
	var got: Array[String] = Crafting.available(profile, tree)
	if got != expected:
		return "got %s" % [got]
	return ""


func test_available_does_not_change_the_profile() -> String:
	var profile: Profile = _profile({"scrap_alloy": 9, "cell_salts": 1})
	var before: String = profile.to_json()
	Crafting.available(profile, _tree())
	if profile.to_json() != before:
		return "profile changed"
	return ""


func test_a_crafted_upgrade_survives_json_and_a_store_reload() -> String:
	var tree: UpgradeTree = _tree()
	var profile: Profile = _profile({"scrap_alloy": 3})
	if Crafting.craft(profile, tree, "thruster") != "":
		return "thruster refused"
	var parsed: Profile = Profile.parse_json(profile.to_json())
	if parsed.error != "" or parsed.crafted != ["thruster"] or parsed.banked != {"scrap_alloy": 1}:
		return "after JSON: crafted %s, banked %s, error '%s'" % [parsed.crafted, parsed.banked, parsed.error]
	DirAccess.make_dir_recursive_absolute(DIR)
	var store: ProfileStore = ProfileStore.new(DIR + "/meltdown_profile.json")
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())
	var saved: bool = store.save(profile)
	var loaded: Profile = ProfileStore.new(store.path).load_profile()
	DirAccess.remove_absolute(store.path)
	DirAccess.remove_absolute(store.temp_path())
	if not saved:
		return "save failed: %s" % store.message
	if loaded.crafted != ["thruster"] or loaded.banked != {"scrap_alloy": 1}:
		return "after reload: crafted %s, banked %s" % [loaded.crafted, loaded.banked]
	if Crafting.craft(loaded, tree, "thruster") != "\"thruster\" is already crafted":
		return "a reloaded profile could craft thruster again"
	return ""


func test_crafting_works_on_the_shipped_tree() -> String:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	var tree: UpgradeTree = UpgradeTree.parse(texts)
	if tree.error != "":
		return tree.error
	var profile: Profile = _profile({"scrap_alloy": 99, "cell_salts": 99, "circuit_shards": 99, "core_glass": 99})
	# Crafting whatever is available until nothing is left must craft the whole tree.
	var rounds: int = 0
	while not Crafting.available(profile, tree).is_empty() and rounds < 100:
		var id: String = Crafting.available(profile, tree)[0]
		var reason: String = Crafting.craft(profile, tree, id)
		if reason != "":
			return "%s refused: %s" % [id, reason]
		rounds += 1
	if profile.crafted.size() != tree.upgrades.size():
		return "crafted %d of %d" % [profile.crafted.size(), tree.upgrades.size()]
	return ""
