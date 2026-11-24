class_name HubModel
extends RefCounted

## What the hub lists and what its actions do (CRW-2, CRF-3, CRF-4, CRW-1, #1033),
## with no scene: five pages (crew, stats, store, craft, fit) in the order of
## `data/hub/hub.json`, and the craft, fit and launch actions.
##
## The actions change only the profile and fitting this model was given; they
## never write simulation state (MP-2). Saving them is the caller's job, through
## `ProfileStore` and `FittingStore`. Every refusal is the reason `Crafting` or
## `Fitting` gave, unchanged, so the hub and the tests read the same words.
##
## A suspended run (RUN-8, #949) is handed in as its `RunSave` through
## `set_waiting`; the model opens no save file itself (#1106). Starting a new run
## while one waits is allowed: the caller discards the waiting save.

## `resume`'s reason when no suspended run waits.
const NO_RUN_WAITING: String = "no suspended run is waiting"

var config: HubConfig
var profile: Profile
var tree: UpgradeTree
var fitting: Fitting
var roles: CrewRoles
var components: ComponentList
## The parsed ship file; read only.
var ship_data: Dictionary = {}
## The suspended run waiting to resume, or null; read only.
var waiting_run: RunSave = null
## The part files' numbers the Workbench shows (#1317); empty until the caller
## sets the shipped ones, and then upgrades show no numbers.
var parts: HubPartInfo = HubPartInfo.new()


static func create(p_config: HubConfig, p_profile: Profile, p_roles: CrewRoles, p_components: ComponentList,
		p_tree: UpgradeTree, p_fitting: Fitting, p_ship_data: Dictionary) -> HubModel:
	var model: HubModel = HubModel.new()
	model.config = p_config
	model.profile = p_profile
	model.roles = p_roles
	model.components = p_components
	model.tree = p_tree
	model.fitting = p_fitting
	# A copy, so nothing the hub does can reach the caller's ship data.
	model.ship_data = p_ship_data.duplicate(true)
	return model


## Page ids in the file's order.
func pages() -> Array[String]:
	return config.pages.duplicate()


func page_title(id: String) -> String:
	return config.title(id)


## Each crew member in the order they joined: `id`, `role`, `role_name`, and the
## benefit's `stat` and `amount`. A role the roles file does not know keeps its
## id with an empty name, stat "" and amount 0, so the hub can still list it.
func crew() -> Array[Dictionary]:
	var members: Array[Dictionary] = []
	for member: Dictionary in profile.crew:
		var role: String = member[Profile.CREW_ROLE]
		members.append({
			"id": member[Profile.CREW_ID],
			"role": role,
			"role_name": roles.role_name(role),
			"stat": roles.benefit_stat(role),
			"amount": roles.benefit_amount(role),
		})
	return members


## The profile's seven lifetime counters (#1095), keyed as `ProfileStats.KEYS`
## and in that order. A profile read from a file older than version 3 has no
## stats on disk; `Profile` gives it zeros, and so does a missing stats object.
func stats() -> Dictionary:
	if profile.stats == null:
		return ProfileStats.new().to_dict()
	return profile.stats.to_dict()


## Banked components, tier first then id: `id`, `name`, `tier`, `count`. A kind
## no component file describes shows its id as the name and tier 0.
func store() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for id: String in profile.banked:
		var kind: ComponentDef = components.get_kind(id)
		rows.append({
			"id": id,
			"name": kind.display_name if kind != null else id,
			"tier": kind.tier if kind != null else 0,
			"count": profile.banked[id],
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["tier"] != b["tier"]:
			return a["tier"] < b["tier"]
		return a["id"] < b["id"])
	return rows


## Upgrades that can be crafted now, as `Crafting.available` orders them.
func craftable() -> Array[String]:
	return Crafting.available(profile, tree)


## Upgrades neither crafted nor craftable, each `{"id", "reason"}` with the
## reason from `UpgradeTree.missing`, in the same order as `craftable`.
func locked() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for upgrade: UpgradeDef in ordered_upgrades():
		if profile.crafted.has(upgrade.id):
			continue
		var reason: String = tree.missing(upgrade.id, profile.crafted, profile.banked)
		if reason != "":
			rows.append({"id": upgrade.id, "reason": reason})
	return rows


## Upgrades already crafted, in the same order as `craftable`.
func crafted() -> Array[String]:
	var ids: Array[String] = []
	for upgrade: UpgradeDef in ordered_upgrades():
		if profile.crafted.has(upgrade.id):
			ids.append(upgrade.id)
	return ids


## Every weapon slot, then each utility slot the ship has, then the shield,
## hull and engine part slots (#1094): `slot` (as `fit` takes it), `kind`,
## `index`, the fitted `upgrade` ("" for none, which for a part slot means the
## ship's stock numbers) and the ship file's `part` in that slot ("" for none;
## always "" for a part slot, whose stock is numbers, not a part id).
func fit_slots() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var base: Dictionary = {}
	if typeof(ship_data.get(ShipTuning.LOADOUT_KEY)) == TYPE_DICTIONARY:
		base = ship_data[ShipTuning.LOADOUT_KEY]
	var counts: Dictionary[String, int] = {
		Fitting.PRIMARY: ShipLoadout.SLOTS_PER_KIND,
		Fitting.SECONDARY: ShipLoadout.SLOTS_PER_KIND,
		Fitting.UTILITY: int(ship_data.get(ShipTuning.UTILITY_SLOTS_KEY, 0)),
	}
	for kind: String in Fitting.KEYS:
		var parts: Array = base.get(kind, []) if typeof(base.get(kind)) == TYPE_ARRAY else []
		var ids: Array[String] = fitting.ids_of(kind)
		for index: int in counts[kind]:
			rows.append({
				"slot": "%s[%d]" % [kind, index],
				"kind": kind,
				"index": index,
				"upgrade": ids[index] if index < ids.size() else "",
				"part": str(parts[index]) if index < parts.size() else "",
			})
	for kind: String in Fitting.PART_KEYS:
		rows.append({"slot": kind, "kind": kind, "index": 0, "upgrade": fitting.parts[kind], "part": ""})
	return rows


## Crafts upgrade `id`. Returns `Crafting.craft`'s reason unchanged, "" on success.
func craft(id: String) -> String:
	return Crafting.craft(profile, tree, id)


## Puts upgrade `id` in `slot` ("primary[0]", "utility[1]", ..., or a part
## slot "shield", "hull", "engine"), or empties it when `id` is "" (a part slot
## then goes back to stock). Returns `Fitting.check`'s reason unchanged and
## leaves the fitting as it was on a refusal; "" on success, keeping every other
## slot, parts included. A slot name that is not one of the fitting's slots is
## refused before the check.
func fit(slot: String, id: String) -> String:
	var candidate: Fitting = _copy(fitting)
	if Fitting.PART_KEYS.has(slot):
		candidate.parts[slot] = id
		return _take(candidate)
	var parsed: Array = _parse_slot(slot)
	if parsed.is_empty():
		return "unknown slot \"%s\"" % slot
	var kind: String = parsed[0]
	var index: int = parsed[1]
	var ids: Array[String] = candidate.ids_of(kind)
	while ids.size() <= index:
		ids.append("")
	ids[index] = id
	if kind == Fitting.UTILITY:
		# The fitting file lists utility slots up to the last used one.
		while not ids.is_empty() and ids[ids.size() - 1] == "":
			ids.remove_at(ids.size() - 1)
	return _take(candidate)


## Tells the model which suspended run waits (`RunSaveStore`'s save), or null for none.
func set_waiting(save: RunSave) -> void:
	waiting_run = save


## Whether a suspended run waits to be resumed.
func run_waits() -> bool:
	return waiting_run != null


## The waiting run's `level` (the 1-based depth it resumes on) and `seed`, or {}.
func waiting() -> Dictionary:
	if waiting_run == null:
		return {}
	return {"level": waiting_run.next_level, "seed": waiting_run.run_seed}


## `{"resume": true}` when a suspended run waits; otherwise `NO_RUN_WAITING`.
## The caller resumes it through `RunResume`; the model changes nothing.
func resume() -> Variant:
	if waiting_run == null:
		return NO_RUN_WAITING
	return {"resume": true}


## Why the current fitting cannot start a run, or "" (`Fitting.check`).
func launch_check() -> String:
	return Fitting.check(fitting, tree, profile.crafted, ship_data)


## The starting loadout section from `Fitting.loadout`, or {} when
## `launch_check` refuses the fitting.
func launch() -> Dictionary:
	if launch_check() != "":
		return {}
	return Fitting.loadout(fitting, tree, ship_data)


## Copies `candidate` into the fitting when `Fitting.check` passes it; returns
## the check's reason unchanged.
func _take(candidate: Fitting) -> String:
	var reason: String = Fitting.check(candidate, tree, profile.crafted, ship_data)
	if reason != "":
		return reason
	fitting.primary = candidate.primary
	fitting.secondary = candidate.secondary
	fitting.utility = candidate.utility
	fitting.parts = candidate.parts
	return ""


## The tree's upgrades ordered as `Crafting.available` orders them.
func ordered_upgrades() -> Array[UpgradeDef]:
	var ordered: Array[UpgradeDef] = tree.upgrades.duplicate()
	ordered.sort_custom(Crafting._before)
	return ordered


## [kind, index] for a slot name, or [] when it names no fitting slot.
static func _parse_slot(slot: String) -> Array:
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


static func _copy(source: Fitting) -> Fitting:
	var copy: Fitting = Fitting.new()
	copy.primary = source.primary.duplicate()
	copy.secondary = source.secondary.duplicate()
	copy.utility = source.utility.duplicate()
	copy.parts = source.parts.duplicate()
	return copy
