extends RefCounted

## The last six parts of #1090 (SLV-2, CRF-3, CRF-6, CRF-7, ARC-4): two
## crafted-only weapons and four ship parts, each an upgrade at its tier, the
## weapons firing unlike every other weapon, and the ship parts covering
## shield, hull and engine inside `ShipPartDef`'s multiplier range.

const WEAPONS_DIR: String = "res://data/weapons"
const DEEPEST_TIER: int = 3
const DEEPEST_COMPONENT: String = "core_glass"
## Weapon id -> [tier, the upgrade it requires or "" for none].
const WEAPONS: Dictionary = {
	"ember_coil": [1, ""],
	"quill_battery": [2, "ember_coil"],
}
## Part id -> [kind, tier, the upgrade it requires or "" for none].
const PARTS: Dictionary = {
	"prism_veil": ["shield", 1, ""],
	"spar_lattice": ["hull", 2, "layered_plating"],
	"coldfire_nozzle": ["engine", 3, "vectored_thrusters"],
	"halo_weir": ["shield", 3, "baffled_emitter"],
}


static func _weapon(id: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS_DIR.path_join(id + ".json")))


static func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


## Checks that `id` is crafted by an upgrade of `kind` at `tier` requiring
## `required` (none when empty), with the deepest tier costing core glass.
static func _check_upgrade(tree: UpgradeTree, id: String, kind: String, tier: int, required: String) -> String:
	var upgrade: UpgradeDef = tree.get_upgrade(id)
	if upgrade == null:
		return "no upgrade crafts %s" % id
	if upgrade.kind != kind or upgrade.grants != id or upgrade.tier != tier:
		return "%s is a tier-%d %s granting %s" % [id, upgrade.tier, upgrade.kind, upgrade.grants]
	var expected: Array[String] = []
	if required != "":
		expected.append(required)
	if upgrade.requires != expected:
		return "%s requires %s, expected %s" % [id, upgrade.requires, expected]
	if tier == DEEPEST_TIER and not upgrade.cost.has(DEEPEST_COMPONENT):
		return "tier-3 %s costs %s, no %s" % [id, upgrade.cost, DEEPEST_COMPONENT]
	return ""


func test_weapons_load_crafted_only_at_their_tiers() -> String:
	var tree: UpgradeTree = _tree()
	if tree.error != "":
		return tree.error
	for id: String in WEAPONS:
		var weapon: WeaponDef = _weapon(id)
		if weapon.error != "":
			return "%s does not load: %s" % [id, weapon.error]
		if not weapon.crafted_only:
			return "%s is not crafted-only, so it would move every session hash" % id
		var expected: Array = WEAPONS[id]
		var problem: String = _check_upgrade(tree, id, "weapon", int(expected[0]), str(expected[1]))
		if problem != "":
			return problem
		if tree.get_upgrade(id).branch != "weapons":
			return "%s is not in the weapons branch" % id
	return ""


func test_parts_load_within_range_at_their_tiers() -> String:
	var tree: UpgradeTree = _tree()
	if tree.error != "":
		return tree.error
	for id: String in PARTS:
		var path: String = ShipPartDef.PARTS_DIR.path_join(id + ".json")
		var part: ShipPartDef = ShipPartDef.parse_json(FileAccess.get_file_as_string(path), id + ".json")
		if part.error != "":
			return "%s does not load: %s" % [id, part.error]
		var expected: Array = PARTS[id]
		if part.kind != str(expected[0]):
			return "%s is a %s part, expected %s" % [id, part.kind, expected[0]]
		if part.stats.is_empty():
			return "%s changes no number" % id
		var problem: String = _check_upgrade(tree, id, str(expected[0]), int(expected[1]), str(expected[2]))
		if problem != "":
			return problem
	return ""


func test_parts_cover_shield_hull_engine_and_three_tiers() -> String:
	var kinds: Array[String] = []
	var tiers: Array[int] = []
	for id: String in PARTS:
		kinds.append(str(PARTS[id][0]))
	for table: Dictionary in [WEAPONS, PARTS]:
		for id: String in table:
			var tier: int = int(table[id][1]) if table == PARTS else int(table[id][0])
			if not tiers.has(tier):
				tiers.append(tier)
	for kind: String in ["shield", "hull", "engine"]:
		if not kinds.has(kind):
			return "no new %s part" % kind
	tiers.sort()
	if tiers != [1, 2, 3]:
		return "the six parts span tiers %s, not 1 to 3" % [tiers]
	return ""


## Clearly distinct: against every other shipped weapon, at least two of fire
## interval, projectile speed, lifetime and damage differ by half again.
func test_weapons_fire_unlike_every_other_weapon() -> String:
	for id: String in WEAPONS:
		var weapon: WeaponDef = _weapon(id)
		for file: String in DirAccess.get_files_at(WEAPONS_DIR):
			if not file.ends_with(".json") or file.get_basename() == id:
				continue
			var other: WeaponDef = _weapon(file.get_basename())
			var differing: int = 0
			for pair: Array in [
				[weapon.fire_interval_ticks, other.fire_interval_ticks],
				[weapon.projectile_speed, other.projectile_speed],
				[weapon.lifetime, other.lifetime],
				[weapon.damage, other.damage],
			]:
				if maxf(float(pair[0]), float(pair[1])) >= 1.5 * minf(float(pair[0]), float(pair[1])):
					differing += 1
			if differing < 2:
				return "%s fires too much like %s" % [id, file.get_basename()]
	return ""
