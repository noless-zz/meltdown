class_name HubPartInfo
extends RefCounted

## The numbers the Workbench shows for what an upgrade does (CRF-3, CRF-6,
## #1317), read from the files that already define each part, so the hub never
## keeps its own copy of a weapon's damage or a shield's strength (ARC-4).
## Weapons give their damage and shots per second; shield, hull and engine parts
## their stat multipliers; modules the numbers in their own file. Read only: the
## simulation reads these files itself and nothing here reaches it (MP-2).

const WEAPONS_DIR: String = "res://data/weapons"
const PARTS_DIR: String = "res://data/ship_parts"
## Module files, by module id: the utility modules and the two aim modules.
const MODULE_DIRS: Array[String] = ["res://data/utility", "res://data/aim"]
## The simulation's fixed tick rate (ARC-1), to turn a fire interval into a rate.
const TICKS_PER_SECOND: float = 60.0
const DAMAGE: String = "damage"
const RATE: String = "rate"

## Weapon id to its parsed file.
var weapons: Dictionary[String, Dictionary] = {}
## Part id to its `stats` object (stat to multiplier).
var parts: Dictionary[String, Dictionary] = {}
## Module id to its parsed file.
var modules: Dictionary[String, Dictionary] = {}


## Reads the shipped files. A file that does not parse is left out, so its
## upgrade shows no numbers rather than wrong ones.
static func load_shipped() -> HubPartInfo:
	var module_texts: Dictionary = {}
	for dir: String in MODULE_DIRS:
		module_texts.merge(_texts(dir))
	return parse(_texts(WEAPONS_DIR), _texts(PARTS_DIR), module_texts)


## Each argument maps a file name (`<id>.json`) or an id to the file's text.
static func parse(weapon_texts: Dictionary, part_texts: Dictionary, module_texts: Dictionary) -> HubPartInfo:
	var info: HubPartInfo = HubPartInfo.new()
	for file: Variant in weapon_texts:
		var data: Variant = JSON.parse_string(str(weapon_texts[file]))
		if typeof(data) == TYPE_DICTIONARY:
			info.weapons[_id(file)] = data
	for file: Variant in part_texts:
		var data: Variant = JSON.parse_string(str(part_texts[file]))
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("stats")) == TYPE_DICTIONARY:
			info.parts[_id(file)] = data["stats"]
	for file: Variant in module_texts:
		var data: Variant = JSON.parse_string(str(module_texts[file]))
		if typeof(data) == TYPE_DICTIONARY:
			info.modules[_id(file)] = data
	return info


## The weapon's shown name from its file, or "" when no file names it.
func weapon_name(id: String) -> String:
	return str(weapons[id].get("name", "")) if weapons.has(id) else ""


## What `upgrade` does, as `{"key", "value", "multiplier"}` in the file's order:
## a weapon's `damage` and `rate` (shots per second), a part's stat multipliers,
## a module's numbers. Empty when no file describes what it grants.
func effects(upgrade: UpgradeDef) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var id: String = upgrade.grants
	match upgrade.kind:
		"weapon":
			if weapons.has(id):
				var data: Dictionary = weapons[id]
				if _is_number(data.get(DAMAGE)):
					out.append(_entry(DAMAGE, float(data[DAMAGE]), false))
				var ticks: Variant = data.get("fire_interval_ticks")
				if _is_number(ticks) and float(ticks) > 0.0:
					out.append(_entry(RATE, TICKS_PER_SECOND / float(ticks), false))
		"module":
			for key: Variant in modules.get(id, {}):
				if _is_number(modules[id][key]):
					out.append(_entry(str(key), float(modules[id][key]), false))
		_:
			for key: Variant in parts.get(id, {}):
				if _is_number(parts[id][key]):
					out.append(_entry(str(key), float(parts[id][key]), true))
	return out


static func _entry(key: String, value: float, multiplier: bool) -> Dictionary:
	return {"key": key, "value": value, "multiplier": multiplier}


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


static func _id(file: Variant) -> String:
	var name: String = str(file)
	return name.get_basename() if name.ends_with(".json") else name


static func _texts(dir: String) -> Dictionary:
	var texts: Dictionary = {}
	for file: String in DirAccess.get_files_at(dir):
		if file.ends_with(".json"):
			texts[file] = FileAccess.get_file_as_string(dir.path_join(file))
	return texts
