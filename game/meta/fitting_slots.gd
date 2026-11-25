class_name FittingSlots
extends RefCounted

## Slots of a `Fitting` by name ("primary[0]", "utility[1]", "shield", ...) and
## the one-item rule (CRF-3, CRF-4, #1336): a crafted upgrade is one item, so it
## sits in at most one slot at a time. `Fitting.check` refuses a fitting that
## names one upgrade twice; `move` takes an upgrade from the slot it is in to
## another in one step, so the hub never has to fit a second copy; and
## `without_doubles` repairs a fitting saved before the rule.
##
## Pure functions over a `Fitting`; nothing here checks crafting or kinds,
## which stays `Fitting.check`'s job.


## [kind, index] for a weapon or utility slot name, or [] when it names none.
## Part slots ("shield", "hull", "engine") have no index and give [].
static func parse(slot: String) -> Array:
	var open: int = slot.find("[")
	if open <= 0 or not slot.ends_with("]"):
		return []
	var kind: String = slot.substr(0, open)
	var number: String = slot.substr(open + 1, slot.length() - open - 2)
	if not Fitting.KEYS.has(kind) or not number.is_valid_int():
		return []
	var index: int = number.to_int()
	var most: int = Fitting.UTILITY_MAX if kind == Fitting.UTILITY else ShipLoadout.SLOTS_PER_KIND
	if index < 0 or index >= most or str(index) != number:
		return []
	return [kind, index]


## Every slot name of `fitting` that holds an upgrade, in slot order: primary,
## secondary, utility, then the part slots.
static func filled(fitting: Fitting) -> Array[String]:
	var names: Array[String] = []
	for kind: String in Fitting.KEYS:
		var ids: Array[String] = fitting.ids_of(kind)
		for index: int in ids.size():
			if ids[index] != "":
				names.append("%s[%d]" % [kind, index])
	for slot: String in Fitting.PART_KEYS:
		if fitting.parts[slot] != "":
			names.append(slot)
	return names


## The upgrade in slot `slot`, "" when it is empty or not a slot.
static func get_id(fitting: Fitting, slot: String) -> String:
	if Fitting.PART_KEYS.has(slot):
		return fitting.parts[slot]
	var parsed: Array = parse(slot)
	if parsed.is_empty():
		return ""
	var ids: Array[String] = fitting.ids_of(parsed[0])
	return ids[parsed[1]] if parsed[1] < ids.size() else ""


## The first slot holding upgrade `id`, or "" when it is not fitted.
static func slot_of(fitting: Fitting, id: String) -> String:
	if id == "":
		return ""
	for slot: String in filled(fitting):
		if get_id(fitting, slot) == id:
			return slot
	return ""


## Puts `id` in `slot` ("" empties it). The utility list stays only as long as
## its last used slot, as the fitting file lists it. False, with nothing
## changed, when `slot` names no slot of a fitting.
static func put(fitting: Fitting, slot: String, id: String) -> bool:
	if Fitting.PART_KEYS.has(slot):
		fitting.parts[slot] = id
		return true
	var parsed: Array = parse(slot)
	if parsed.is_empty():
		return false
	var ids: Array[String] = fitting.ids_of(parsed[0])
	while ids.size() <= parsed[1]:
		ids.append("")
	ids[parsed[1]] = id
	if parsed[0] == Fitting.UTILITY:
		while not ids.is_empty() and ids[ids.size() - 1] == "":
			ids.remove_at(ids.size() - 1)
	return true


## Takes upgrade `id` out of the slot it is in and puts it in `to_slot`, in one
## step. Returns "" on success (also when it is already there), otherwise the
## reason, with `fitting` unchanged. Whether the upgrade fits `to_slot` is
## `Fitting.check`'s to judge afterwards.
static func move(fitting: Fitting, id: String, to_slot: String) -> String:
	var from: String = slot_of(fitting, id)
	if from == "":
		return "\"%s\" is not fitted anywhere, so it cannot be moved" % id
	if not Fitting.PART_KEYS.has(to_slot) and parse(to_slot).is_empty():
		return "unknown slot \"%s\"" % to_slot
	if from == to_slot:
		return ""
	put(fitting, from, "")
	put(fitting, to_slot, id)
	return ""


## A copy of `fitting` in which an upgrade named in more than one slot stays
## only in the first (slot order as `filled`); each later slot is emptied and
## one line naming it is appended to `notes`. Never changes `fitting`.
static func without_doubles(fitting: Fitting, notes: Array[String] = []) -> Fitting:
	var kept: Fitting = copy(fitting)
	var seen: Dictionary[String, String] = {}
	for slot: String in filled(fitting):
		var id: String = get_id(fitting, slot)
		if seen.has(id):
			put(kept, slot, "")
			notes.append("%s emptied: \"%s\" is already fitted in %s" % [slot, id, seen[id]])
		else:
			seen[id] = slot
	return kept


static func copy(source: Fitting) -> Fitting:
	var result: Fitting = Fitting.new()
	result.primary = source.primary.duplicate()
	result.secondary = source.secondary.duplicate()
	result.utility = source.utility.duplicate()
	result.parts = source.parts.duplicate()
	return result
