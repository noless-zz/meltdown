extends RefCounted

## The two crafted weapons of #1102 (SLV-2, CRF-6, CRF-7, ARC-4): each is a
## weapon upgrade at its tier, marked crafted-only so it stays out of the
## salvage catalogue and moves no pinned hash, and fires clearly unlike the
## four weapons robots drop.

const WEAPONS_DIR: String = "res://data/weapons"
const DROPPED_IDS: Array[String] = ["arc_lance", "needle_gun", "pulse_cannon", "slug_thrower"]
## Crafted weapon id -> [tier, the upgrade it requires].
const CRAFTED: Dictionary = {
	"drift_mortar": [2, "slug_thrower"],
	"hollow_spike": [3, "arc_lance"],
}
const DEEPEST_COMPONENT: String = "core_glass"


static func _weapon(id: String) -> WeaponDef:
	return WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPONS_DIR.path_join(id + ".json")))


static func _tree() -> UpgradeTree:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	return UpgradeTree.parse(texts)


static func _upgrade(tree: UpgradeTree, id: String) -> UpgradeDef:
	for upgrade: UpgradeDef in tree.upgrades:
		if upgrade.id == id:
			return upgrade
	return null


func test_each_crafted_weapon_loads_crafted_only() -> String:
	for id: String in CRAFTED:
		var weapon: WeaponDef = _weapon(id)
		if weapon.error != "":
			return "%s does not load: %s" % [id, weapon.error]
		if not weapon.crafted_only:
			return "%s is not crafted-only, so it would move every session hash" % id
	return ""


func test_each_crafted_weapon_is_an_upgrade_at_its_tier() -> String:
	var tree: UpgradeTree = _tree()
	if tree.error != "":
		return tree.error
	for id: String in CRAFTED:
		var upgrade: UpgradeDef = _upgrade(tree, id)
		if upgrade == null:
			return "no upgrade crafts %s" % id
		var expected: Array = CRAFTED[id]
		if upgrade.kind != "weapon" or upgrade.branch != "weapons" or upgrade.grants != id:
			return "%s is %s/%s granting %s" % [id, upgrade.branch, upgrade.kind, upgrade.grants]
		if upgrade.tier != int(expected[0]) or upgrade.requires != [str(expected[1])]:
			return "%s is tier %d requiring %s" % [id, upgrade.tier, upgrade.requires]
		var required: UpgradeDef = _upgrade(tree, str(expected[1]))
		if required == null or required.kind != "weapon" or required.tier != upgrade.tier - 1:
			return "%s does not require a tier-%d weapon" % [id, upgrade.tier - 1]
	var spike: UpgradeDef = _upgrade(tree, "hollow_spike")
	if not spike.cost.has(DEEPEST_COMPONENT):
		return "the tier-3 hollow spike costs %s, no %s" % [spike.cost, DEEPEST_COMPONENT]
	return ""


## Clearly distinct: against every other weapon, at least two of fire interval,
## projectile speed, lifetime and damage differ by half again or more.
func test_crafted_weapons_fire_unlike_the_dropped_ones() -> String:
	var all_ids: Array[String] = DROPPED_IDS.duplicate()
	for id: String in CRAFTED:
		all_ids.append(id)
	for id: String in CRAFTED:
		var crafted: WeaponDef = _weapon(id)
		for other_id: String in all_ids:
			if other_id == id:
				continue
			var other: WeaponDef = _weapon(other_id)
			var differing: int = 0
			for pair: Array in [
				[crafted.fire_interval_ticks, other.fire_interval_ticks],
				[crafted.projectile_speed, other.projectile_speed],
				[crafted.lifetime, other.lifetime],
				[crafted.damage, other.damage],
			]:
				if _apart(float(pair[0]), float(pair[1])):
					differing += 1
			if differing < 2:
				return "%s fires too much like %s" % [id, other_id]
	return ""


static func _apart(a: float, b: float) -> bool:
	return maxf(a, b) >= 1.5 * minf(a, b)


func test_the_salvage_catalogue_keeps_only_dropped_weapons() -> String:
	var ids: Array[String] = []
	ids.assign(LocalSession.load_parts().keys())
	ids.sort()
	if ids != DROPPED_IDS:
		return "the salvage catalogue holds %s" % [ids]
	return ""
