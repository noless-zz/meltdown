class_name ShipLoadout
extends RefCounted

## The weapons a ship starts a run with, one weapon id per slot, read from the
## `loadout` entry of a ship data file (CMB-1, ARC-4).
##
## The file names weapons by id only. Core never opens files, so the caller
## reads `res://data/weapons/<id>.json` for every id in `weapon_ids()` and
## hands the texts to `resolve`, which turns them into `WeaponDef`s. Only
## resolved weapons are equipped and recorded in a replay, so a replay carries
## the weapon values themselves and needs no files to reproduce a run (ARC-2).
##
## CMB-1 fills slots only by salvage found during the run. A starting weapon
## from data keeps combat testable before salvage exists; a ship file whose
## loadout is empty, or has none, keeps the strict rule.
##
## Data file shape, each list at most `SLOTS_PER_KIND` long, "" for an empty slot:
##
##     "loadout": {"primary": ["pulse_cannon", ""], "secondary": ["", ""]}

## Slots of each kind, as in `ShipState`.
const SLOTS_PER_KIND: int = 2
## The slot kinds, in the order replays write them.
const KINDS: Array[String] = ["primary", "secondary"]
## Longest weapon id, as for `RobotDef` ids.
const ID_MAX_LENGTH: int = 64

## Weapon id of each slot, "" when empty.
var primary_ids: Array[String] = ["", ""]
var secondary_ids: Array[String] = ["", ""]
## Weapon of each slot once resolved, null when empty or not yet resolved.
var primary_weapons: Array[WeaponDef] = [null, null]
var secondary_weapons: Array[WeaponDef] = [null, null]
## Set by `from_data` when the entry was rejected; empty otherwise.
var error: String = ""


## Reads the value of a ship file's `loadout` key: an object with optional
## `primary` and `secondary` lists of weapon ids. On failure the returned
## loadout is empty and has `error` set, naming the field.
static func from_data(data: Variant) -> ShipLoadout:
	if typeof(data) != TYPE_DICTIONARY:
		return _failed("\"loadout\" must be an object")
	var entry: Dictionary = data
	for key: Variant in entry:
		if typeof(key) != TYPE_STRING or not KINDS.has(key):
			return _failed("unknown key \"loadout.%s\"" % str(key))
	var loadout: ShipLoadout = ShipLoadout.new()
	for kind: String in KINDS:
		if not entry.has(kind):
			continue
		if typeof(entry[kind]) != TYPE_ARRAY:
			return _failed("\"loadout.%s\" must be a list" % kind)
		var ids: Array = entry[kind]
		if ids.size() > SLOTS_PER_KIND:
			return _failed("\"loadout.%s\" has %d slots, at most %d" % [kind, ids.size(), SLOTS_PER_KIND])
		for slot: int in ids.size():
			var field: String = "loadout.%s[%d]" % [kind, slot]
			if typeof(ids[slot]) != TYPE_STRING:
				return _failed("\"%s\" must be a string" % field)
			var id: String = ids[slot]
			if id == "":
				continue
			var message: String = check_id(field, id)
			if message != "":
				return _failed(message)
			loadout.ids_of(kind)[slot] = id
	return loadout


## Empty when `id` is a valid weapon id: 1 to `ID_MAX_LENGTH` characters of
## a-z, 0-9 and _, the `RobotDef` rule, so it is always a safe file name.
static func check_id(field: String, id: String) -> String:
	if id.is_empty() or id.length() > ID_MAX_LENGTH:
		return "\"%s\" must be 1 to %d characters" % [field, ID_MAX_LENGTH]
	for i: int in id.length():
		var c: int = id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return "\"%s\" is \"%s\", must use only a-z, 0-9 and _" % [field, id]
	return ""


func ids_of(kind: String) -> Array[String]:
	return primary_ids if kind == "primary" else secondary_ids


func weapons_of(kind: String) -> Array[WeaponDef]:
	return primary_weapons if kind == "primary" else secondary_weapons


## Every distinct weapon id the loadout names, in slot order: the files the
## caller must read before `resolve`.
func weapon_ids() -> Array[String]:
	var ids: Array[String] = []
	for kind: String in KINDS:
		for id: String in ids_of(kind):
			if id != "" and not ids.has(id):
				ids.append(id)
	return ids


## Parses the weapon of every named slot from `texts`, a Dictionary from
## weapon id to the text of its data file. Returns "" on success, or a problem
## naming the slot; on failure no slot is resolved, so a half-armed ship
## cannot start a run.
func resolve(texts: Dictionary) -> String:
	var parsed: Dictionary[String, WeaponDef] = {}
	for kind: String in KINDS:
		var ids: Array[String] = ids_of(kind)
		for slot: int in SLOTS_PER_KIND:
			var id: String = ids[slot]
			if id == "" or parsed.has(id):
				continue
			var field: String = "loadout.%s[%d]" % [kind, slot]
			if not texts.has(id) or typeof(texts[id]) != TYPE_STRING:
				return "\"%s\" names weapon \"%s\", which has no data" % [field, id]
			var weapon: WeaponDef = WeaponDef.parse_json(texts[id])
			if weapon.error != "":
				return "\"%s\" weapon \"%s\": %s" % [field, id, weapon.error]
			parsed[id] = weapon
	for kind: String in KINDS:
		var ids: Array[String] = ids_of(kind)
		var weapons: Array[WeaponDef] = weapons_of(kind)
		for slot: int in SLOTS_PER_KIND:
			weapons[slot] = parsed[ids[slot]] if ids[slot] != "" else null
	return ""


## Sets slot `slot` of `kind` to weapon `weapon` with id `id`. Used when a
## replay is read, where each weapon arrives already parsed.
func set_slot(kind: String, slot: int, id: String, weapon: WeaponDef) -> void:
	ids_of(kind)[slot] = id
	weapons_of(kind)[slot] = weapon


## Whether any slot holds a resolved weapon.
func is_armed() -> bool:
	for weapon: WeaponDef in primary_weapons + secondary_weapons:
		if weapon != null:
			return true
	return false


## Puts the resolved weapons in `ship`'s slots, emptying the rest.
func equip(ship: ShipState) -> void:
	ship.primary_slots.assign(primary_weapons)
	ship.secondary_slots.assign(secondary_weapons)


static func _failed(message: String) -> ShipLoadout:
	var loadout: ShipLoadout = ShipLoadout.new()
	loadout.error = message
	return loadout
