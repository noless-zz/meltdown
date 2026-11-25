class_name Fitting
extends RefCounted

## Which crafted upgrade goes in which slot of the ship a run starts with
## (CRF-4, CMB-1, #1012). Crafting makes an upgrade available for good; the
## fitting picks which crafted upgrades the next run carries. `loadout` turns
## the ship file's own loadout plus this fitting into the `loadout` section
## `ShipLoadout.from_data` reads, so an empty fitting is exactly the ship file.
##
## What fits where, today:
## - A `weapon` upgrade fits a primary slot. Secondary slots refuse every
##   upgrade: the simulation has no secondary weapons yet (decision record 0004),
##   so no weapon upgrade is of the secondary kind.
## - A `module` upgrade fits a utility slot, and only once core knows its module
##   (`ShipLoadout.UTILITY_MODULE_KINDS`), since the run would reject it otherwise.
## - A `shield`, `hull` or `engine` upgrade fits only the part slot of its own
##   kind, one each, held in `parts`. These slots are separate from the weapon
##   and utility slots, so defence and engine upgrades never compete with
##   modules for space; `RunStartShip` applies their part files to the ship's
##   numbers. Weapon, secondary and utility slots refuse them.
## - One crafted upgrade is one item (#1336): `check` refuses a fitting that
##   names it in two slots; `move` shifts it from one slot to another.

const PRIMARY: String = "primary"
const SECONDARY: String = "secondary"
const UTILITY: String = "utility"
## Slot kinds held as lists of upgrade ids (weapons and modules).
const KEYS: Array[String] = [PRIMARY, SECONDARY, UTILITY]
## Key of the part slots in the JSON text. A text without it (written before part
## slots existed) reads with every part slot empty.
const PARTS: String = "parts"
## Part slot names, one slot each; each takes only upgrades of the same kind.
const PART_KEYS: Array[String] = ["shield", "hull", "engine"]
## Most utility slots a fitting can name, as `ShipTuning.UTILITY_SLOTS_MAX`.
const UTILITY_MAX: int = ShipTuning.UTILITY_SLOTS_MAX

## Upgrade id per slot, "" when the ship file's own choice stays.
var primary: Array[String] = ["", ""]
var secondary: Array[String] = ["", ""]
## Upgrade id per utility slot, in slot order; may be shorter than the ship's
## slot count.
var utility: Array[String] = []
## Upgrade id per part slot (`PART_KEYS`), "" when empty.
var parts: Dictionary[String, String] = {"shield": "", "hull": "", "engine": ""}
## Set by `parse_json` when the text was rejected; the fitting is then empty.
var error: String = ""


## Returns "" when `fitting` can start a run on the ship of `ship_data` (the
## parsed ship file), otherwise one reason naming the slot. Changes nothing.
static func check(fitting: Fitting, tree: UpgradeTree, crafted: Array[String], ship_data: Dictionary) -> String:
	var utility_slots: int = int(ship_data.get(ShipTuning.UTILITY_SLOTS_KEY, 0))
	var seen: Dictionary[String, String] = {}
	for kind: String in KEYS:
		var ids: Array[String] = fitting.ids_of(kind)
		for slot: int in ids.size():
			var id: String = ids[slot]
			if id == "":
				continue
			var field: String = "%s[%d]" % [kind, slot]
			if kind == UTILITY and slot >= utility_slots:
				return "%s does not exist: the ship has %d utility slots" % [field, utility_slots]
			if not tree.has_upgrade(id):
				return "%s: unknown upgrade \"%s\"" % [field, id]
			if not crafted.has(id):
				return "%s: \"%s\" is not crafted" % [field, id]
			if seen.has(id):
				return "%s: \"%s\" is already fitted in %s" % [field, id, seen[id]]
			seen[id] = field
			var reason: String = _slot_reason(kind, tree.get_upgrade(id))
			if reason != "":
				return "%s: %s" % [field, reason]
	for slot: String in PART_KEYS:
		var id: String = fitting.parts[slot]
		if id == "":
			continue
		if not tree.has_upgrade(id):
			return "%s: unknown upgrade \"%s\"" % [slot, id]
		if not crafted.has(id):
			return "%s: \"%s\" is not crafted" % [slot, id]
		var upgrade: UpgradeDef = tree.get_upgrade(id)
		if upgrade.kind != slot:
			return "%s: \"%s\" is kind %s, only %s upgrades fit the %s slot" % [slot, id, upgrade.kind, slot, slot]
	return ""


## The ship file's `loadout` section with each fitted slot replaced by its
## upgrade's `grants`. Expects `check` to have passed. Never changes `ship_data`.
static func loadout(fitting: Fitting, tree: UpgradeTree, ship_data: Dictionary) -> Dictionary:
	var base: Dictionary = {}
	if typeof(ship_data.get(ShipTuning.LOADOUT_KEY)) == TYPE_DICTIONARY:
		base = ship_data[ShipTuning.LOADOUT_KEY].duplicate(true)
	if fitting.is_empty():
		return base
	for kind: String in [PRIMARY, SECONDARY]:
		var ids: Array[String] = fitting.ids_of(kind)
		if not ids.any(func(id: String) -> bool: return id != ""):
			continue
		var slots: Array = base.get(kind, []).duplicate()
		for slot: int in ids.size():
			if ids[slot] == "":
				continue
			while slots.size() <= slot:
				slots.append("")
			slots[slot] = tree.get_upgrade(ids[slot]).grants
		base[kind] = slots
	if fitting.utility.any(func(id: String) -> bool: return id != ""):
		# The ship file lists its modules without gaps; a fitted slot replaces the
		# module in that slot, and empty slots are dropped again afterwards.
		var modules: Array = base.get(UTILITY, []).duplicate()
		for slot: int in fitting.utility.size():
			if fitting.utility[slot] == "":
				continue
			while modules.size() <= slot:
				modules.append("")
			modules[slot] = tree.get_upgrade(fitting.utility[slot]).grants
		base[UTILITY] = modules.filter(func(id: Variant) -> bool: return str(id) != "")
	return base


func ids_of(kind: String) -> Array[String]:
	if kind == PRIMARY:
		return primary
	if kind == SECONDARY:
		return secondary
	return utility


## The fitted part upgrade ids in `PART_KEYS` order, empty slots left out.
func part_ids() -> Array[String]:
	var ids: Array[String] = []
	for slot: String in PART_KEYS:
		if parts[slot] != "":
			ids.append(parts[slot])
	return ids


## The slot holding upgrade `id` ("primary[1]", "shield", ...), or "" (#1336).
func slot_of(id: String) -> String:
	return FittingSlots.slot_of(self, id)


## Moves upgrade `id` from the slot it is in to `to_slot` in one step, since one
## crafted upgrade is one item (#1336). "" on success, else the reason with
## nothing changed; `check` still judges whether it fits there.
func move(id: String, to_slot: String) -> String:
	return FittingSlots.move(self, id, to_slot)


## True when no slot names an upgrade.
func is_empty() -> bool:
	for kind: String in KEYS:
		for id: String in ids_of(kind):
			if id != "":
				return false
	return part_ids().is_empty()


## JSON text with sorted keys, so an unchanged fitting writes the same bytes.
func to_json() -> String:
	var data: Dictionary = {
		PRIMARY: primary.duplicate(),
		SECONDARY: secondary.duplicate(),
		UTILITY: utility.duplicate(),
		PARTS: parts.duplicate(),
	}
	return JSON.stringify(data, "\t", true) + "\n"


## Reads the text `to_json` writes. A rejected text gives an empty fitting with
## `error` set, naming the key; never a crash.
static func parse_json(text: String) -> Fitting:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or key == PARTS):
			return _rejected("unknown key \"%s\"" % str(key))
	var fitting: Fitting = Fitting.new()
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
		var most: int = UTILITY_MAX if key == UTILITY else ShipLoadout.SLOTS_PER_KIND
		var problem: String = _read_ids(key, data[key], most, fitting.ids_of(key))
		if problem != "":
			return _rejected(problem)
	if data.has(PARTS):
		var problem: String = _read_parts(data[PARTS], fitting.parts)
		if problem != "":
			return _rejected(problem)
	return fitting


## Fills `into` from `value`, a list of at most `most` upgrade ids or "".
## Weapon slots keep their fixed size; a shorter list leaves the rest empty.
static func _read_ids(key: String, value: Variant, most: int, into: Array[String]) -> String:
	if typeof(value) != TYPE_ARRAY:
		return "key \"%s\" must be a list" % key
	var ids: Array = value
	if ids.size() > most:
		return "key \"%s\" has %d slots, at most %d" % [key, ids.size(), most]
	for slot: int in ids.size():
		if typeof(ids[slot]) != TYPE_STRING:
			return "key \"%s[%d]\" must be a string" % [key, slot]
		var id: String = ids[slot]
		if id != "":
			var message: String = ShipLoadout.check_id("%s[%d]" % [key, slot], id)
			if message != "":
				return "key %s" % message
		if key == UTILITY:
			into.append(id)
		else:
			into[slot] = id
	return ""


## Fills `into` from `value`, an object of part slot to upgrade id or "". A
## missing slot stays empty.
static func _read_parts(value: Variant, into: Dictionary[String, String]) -> String:
	if typeof(value) != TYPE_DICTIONARY:
		return "key \"%s\" must be an object" % PARTS
	var slots: Dictionary = value
	for slot: Variant in slots:
		if typeof(slot) != TYPE_STRING or not PART_KEYS.has(slot):
			return "key \"%s\" has unknown slot \"%s\"" % [PARTS, str(slot)]
		if typeof(slots[slot]) != TYPE_STRING:
			return "key \"%s.%s\" must be a string" % [PARTS, slot]
		var id: String = slots[slot]
		if id != "":
			var message: String = ShipLoadout.check_id("%s.%s" % [PARTS, slot], id)
			if message != "":
				return "key %s" % message
		into[slot] = id
	return ""


## Why `upgrade` cannot go in a slot of `kind`, or "".
static func _slot_reason(kind: String, upgrade: UpgradeDef) -> String:
	if PART_KEYS.has(upgrade.kind):
		return "\"%s\" is kind %s, it fits only the %s slot" % [upgrade.id, upgrade.kind, upgrade.kind]
	if kind == SECONDARY:
		return "\"%s\" cannot go in a secondary slot: there are no secondary weapons yet" % upgrade.id
	if kind == PRIMARY and upgrade.kind != "weapon":
		return "\"%s\" is a %s, only a weapon fits a primary slot" % [upgrade.id, upgrade.kind]
	if kind == UTILITY and upgrade.kind != "module":
		return "\"%s\" is a %s, only a module fits a utility slot" % [upgrade.id, upgrade.kind]
	if kind == UTILITY and not ShipLoadout.UTILITY_MODULE_KINDS.has(upgrade.grants):
		return "\"%s\" grants module \"%s\", which the simulation does not know yet, not fittable yet" % [upgrade.id, upgrade.grants]
	return ""


static func _rejected(reason: String) -> Fitting:
	var fitting: Fitting = Fitting.new()
	fitting.error = reason
	return fitting
