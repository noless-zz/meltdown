class_name UpgradeTree
extends RefCounted

## Every craftable upgrade, read from the files in `UPGRADES_DIR`, and the tree
## their `requires` lists form (CRF-3, CRF-6, CRF-7). The caller reads the files
## and hands their texts over by file name, because core never opens files.
## Loading only checks the tree; crafting itself lives outside core.

const UPGRADES_DIR: String = "res://data/upgrades"

## Every upgrade, sorted by id so the order never depends on how the caller
## collected the files.
var upgrades: Array[UpgradeDef] = []
## Set by `parse` when a text was rejected; empty otherwise.
var error: String = ""
var _by_id: Dictionary[String, UpgradeDef] = {}
var _file_of: Dictionary[String, String] = {}


## Parses `texts`, file text by file name. Each error starts with the file name
## and names the key. On failure `error` is set and the tree is empty, so no
## caller works with part of it.
static func parse(texts: Dictionary) -> UpgradeTree:
	var tree: UpgradeTree = UpgradeTree.new()
	var files: Array = texts.keys()
	files.sort()
	for file: Variant in files:
		var name: String = str(file)
		if typeof(texts[file]) != TYPE_STRING:
			return _failed("%s: text must be a string" % name)
		var upgrade: UpgradeDef = UpgradeDef.parse_json(texts[file])
		if upgrade.error != "":
			return _failed("%s: %s" % [name, upgrade.error])
		if tree._file_of.has(upgrade.id):
			return _failed("%s: key \"id\" is \"%s\", already used by %s" % [name, upgrade.id, tree._file_of[upgrade.id]])
		tree._file_of[upgrade.id] = name
		tree._by_id[upgrade.id] = upgrade
	var ids: Array[String] = []
	ids.assign(tree._by_id.keys())
	ids.sort()
	for id: String in ids:
		tree.upgrades.append(tree._by_id[id])
	var message: String = tree._check_links()
	if message != "":
		return _failed(message)
	return tree


## True when an upgrade with this id exists.
func has_upgrade(id: String) -> bool:
	return _by_id.has(id)


## The upgrade with this id, or null.
func get_upgrade(id: String) -> UpgradeDef:
	return _by_id.get(id, null)


## Returns "" when upgrade `id` can be crafted now, otherwise one reason: an
## unknown id, already crafted, a prerequisite not crafted, or short of a
## component. `banked` maps component kind id to count. Changes nothing.
func missing(id: String, crafted: Array[String], banked: Dictionary) -> String:
	var upgrade: UpgradeDef = get_upgrade(id)
	if upgrade == null:
		return "unknown upgrade \"%s\"" % id
	if crafted.has(id):
		return "\"%s\" is already crafted" % id
	for required: String in upgrade.requires:
		if not crafted.has(required):
			return "\"%s\" needs \"%s\" crafted first" % [id, required]
	for component: String in upgrade.cost:
		var have: int = int(banked.get(component, 0))
		var need: int = upgrade.cost[component]
		if have < need:
			return "\"%s\" is short of %d %s (needs %d, has %d)" % [id, need - have, component, need, have]
	return ""


## Checks what single files cannot: every `requires` names an upgrade, the
## links form no cycle, and each tier is above the tiers it requires.
func _check_links() -> String:
	for upgrade: UpgradeDef in upgrades:
		for required: String in upgrade.requires:
			if not _by_id.has(required):
				return "%s: key \"requires\" names \"%s\", which is no upgrade" % [_file_of[upgrade.id], required]
	# Cycles first: a cycle would also break the tier rule, but naming the cycle
	# tells the author what is actually wrong.
	var done: Dictionary[String, bool] = {}
	for upgrade: UpgradeDef in upgrades:
		var path: Array[String] = []
		var cycle: Array[String] = _find_cycle(upgrade.id, path, done)
		if not cycle.is_empty():
			return "%s: key \"requires\" forms a cycle: %s" % [_file_of[cycle[0]], " -> ".join(cycle)]
	for upgrade: UpgradeDef in upgrades:
		for required: String in upgrade.requires:
			var below: int = _by_id[required].tier
			if upgrade.tier <= below:
				return "%s: key \"tier\" is %d, must be above tier %d of required \"%s\"" % [_file_of[upgrade.id], upgrade.tier, below, required]
	return ""


## Depth-first walk along `requires`. Returns the cycle as ids, first id
## repeated at the end, or an empty list.
func _find_cycle(id: String, path: Array[String], done: Dictionary[String, bool]) -> Array[String]:
	if done.has(id):
		return []
	var at: int = path.find(id)
	if at >= 0:
		var cycle: Array[String] = path.slice(at)
		cycle.append(id)
		return cycle
	path.append(id)
	for required: String in _by_id[id].requires:
		var cycle: Array[String] = _find_cycle(required, path, done)
		if not cycle.is_empty():
			return cycle
	path.pop_back()
	done[id] = true
	return []


static func _failed(message: String) -> UpgradeTree:
	var tree: UpgradeTree = UpgradeTree.new()
	tree.error = message
	return tree
