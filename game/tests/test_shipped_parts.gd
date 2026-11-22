extends RefCounted

## The shipped parts and upgrades fit together (SLV-2, CRF-6, CRF-7, CRF-3,
## ARC-4, #1056): the tree loads, every non-weapon upgrade grants a part file of
## its own kind, every shield, hull and engine part can be crafted, and the
## deepest tier always costs a deep component. Data only, so a broken file
## shows up here rather than in a run.

const WEAPONS_DIR: String = "res://data/weapons"
const DEEPEST_TIER: int = 3
## SLV-2: parts across weapons, shields, engines and utilities at release.
const RELEASE_PART_COUNT: int = 30


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts


static func _tree() -> UpgradeTree:
	return UpgradeTree.parse(_texts(UpgradeTree.UPGRADES_DIR))


## Part id to parsed part; a part that fails to parse keeps its error.
static func _parts() -> Dictionary[String, ShipPartDef]:
	var parts: Dictionary[String, ShipPartDef] = {}
	var texts: Dictionary = _texts(ShipPartDef.PARTS_DIR)
	for file: Variant in texts:
		parts[str(file).get_basename()] = ShipPartDef.parse_json(texts[file], str(file))
	return parts


func test_tree_and_parts_load() -> String:
	var tree: UpgradeTree = _tree()
	if tree.error != "":
		return tree.error
	for id: String in _parts():
		var part: ShipPartDef = _parts()[id]
		if part.error != "":
			return part.error
	return ""


func test_every_non_weapon_grant_has_a_part_of_its_kind() -> String:
	var parts: Dictionary[String, ShipPartDef] = _parts()
	for upgrade: UpgradeDef in _tree().upgrades:
		if upgrade.kind == "weapon":
			continue
		if not parts.has(upgrade.grants):
			return "upgrade %s grants %s, which has no part file" % [upgrade.id, upgrade.grants]
		if parts[upgrade.grants].kind != upgrade.kind:
			return "upgrade %s is kind %s but part %s is kind %s" % [
				upgrade.id, upgrade.kind, upgrade.grants, parts[upgrade.grants].kind]
	return ""


func test_every_part_except_modules_is_granted() -> String:
	var granted: Array[String] = []
	for upgrade: UpgradeDef in _tree().upgrades:
		granted.append(upgrade.grants)
	var parts: Dictionary[String, ShipPartDef] = _parts()
	for id: String in parts:
		if parts[id].kind != "module" and not granted.has(id):
			return "part %s is granted by no upgrade" % id
	return ""


## CRF-7: the deepest tier needs at least one component found only deep down.
func test_tier_three_costs_a_tier_three_component() -> String:
	var components: ComponentList = ComponentList.parse(_texts(ComponentList.COMPONENTS_DIR))
	if components.error != "":
		return components.error
	var found: bool = false
	for upgrade: UpgradeDef in _tree().upgrades:
		if upgrade.tier != DEEPEST_TIER:
			continue
		found = true
		var deep: bool = false
		for kind: String in upgrade.cost:
			if components.has_kind(kind) and components.get_kind(kind).tier == DEEPEST_TIER:
				deep = true
		if not deep:
			return "tier-3 upgrade %s costs %s, no tier-3 component" % [upgrade.id, upgrade.cost]
	if not found:
		return "no tier-3 upgrade shipped"
	return ""


## SLV-2 asks for 30 parts at release; the count is printed so each run shows
## it, and checked not to shrink below the 18 the first parts brought.
func test_shipped_part_count() -> String:
	var weapons: int = _texts(WEAPONS_DIR).size()
	var parts: int = _parts().size()
	print("  shipped parts: %d (%d weapons + %d part files)" % [weapons + parts, weapons, parts])
	if weapons + parts < 18:
		return "only %d parts shipped" % (weapons + parts)
	return ""


## SLV-2: weapons plus ship parts, utility modules included, reach the 30 the
## release needs (#1090). Fails as soon as removing a file drops the count.
func test_at_least_release_part_count() -> String:
	var total: int = _texts(WEAPONS_DIR).size() + _parts().size()
	if total < RELEASE_PART_COUNT:
		return "only %d parts shipped, SLV-2 needs %d" % [total, RELEASE_PART_COUNT]
	return ""
