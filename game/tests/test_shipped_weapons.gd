extends RefCounted

## Every weapon the upgrade tree can craft has a weapon file that loads
## (SLV-2, CRF-6, ARC-4, #1070). The part check in `test_shipped_parts.gd`
## skips weapon upgrades, so a crafted weapon with a missing or broken file
## would otherwise only show up in a run.

const WEAPONS_DIR: String = "res://data/weapons"


func test_every_weapon_grant_has_a_weapon_file_that_loads() -> String:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(UpgradeTree.UPGRADES_DIR):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(UpgradeTree.UPGRADES_DIR.path_join(file))
	var tree: UpgradeTree = UpgradeTree.parse(texts)
	if tree.error != "":
		return tree.error
	var checked: int = 0
	for upgrade: UpgradeDef in tree.upgrades:
		if upgrade.kind != "weapon":
			continue
		var path: String = WEAPONS_DIR.path_join(upgrade.grants + ".json")
		if not FileAccess.file_exists(path):
			return "upgrade %s grants %s, which has no weapon file" % [upgrade.id, upgrade.grants]
		var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(path))
		if weapon.error != "":
			return "weapon %s does not load: %s" % [upgrade.grants, weapon.error]
		checked += 1
	if checked == 0:
		return "no weapon upgrade shipped"
	return ""
