class_name ShipSummary
extends RefCounted

## The ship at a glance for the home base (CRF-3, CRF-4, CRW-1, CRW-2, #1357):
## every attribute that fitted parts or crew can change, each with its stock
## value (the ship file), its current value (what the next run flies) and the
## sources that make up the difference. Fitted modules and weapons change no
## attribute numbers (`ShipPartDef.STAT_KEYS` gives modules none), so they add
## no row.
##
## The attribute list comes from the data (ARC-4): every number any part file
## multiplies, then every crew benefit stat, so a new part stat or crew role
## needs no code here. The current values are worked out the way
## `RunStartShip.build` works them out (parts by `ShipPartDef.apply`, then the
## crew by `CrewBenefits.apply_to_ship`), and a test holds the two equal.
## Pure over plain data: reads no file and changes nothing (ARC-1, MP-2).

const KIND_PART: String = "part"
const KIND_CREW: String = "crew"
## Crew benefit stat to the ship file number it raises; a stat not listed has
## no ship number, so its stock is 0 and its value is the crew's total.
const CREW_SHIP_KEYS: Dictionary[String, String] = {CrewBenefits.SHIELD_STAT: CrewBenefits.SHIELD_KEY}


## The attributes in the order a summary lists them: the ship file numbers any
## part in `part_stats` (part id to its `stats` object) or any crew role can
## change, in `ShipTuning.KEYS` order, then the crew stats with no ship number,
## sorted.
static func attributes(part_stats: Dictionary, roles: CrewRoles) -> Array[String]:
	var changed: Dictionary[String, bool] = {}
	for part: Variant in part_stats:
		if typeof(part_stats[part]) == TYPE_DICTIONARY:
			for stat: Variant in part_stats[part]:
				changed[str(stat)] = true
	var crew_only: Array[String] = []
	if roles != null and roles.error == "":
		for role: String in roles.ids:
			var stat: String = roles.benefit_stat(role)
			if CREW_SHIP_KEYS.has(stat):
				changed[CREW_SHIP_KEYS[stat]] = true
			elif not crew_only.has(stat):
				crew_only.append(stat)
	crew_only.sort()
	var out: Array[String] = []
	for key: String in ShipTuning.KEYS:
		if changed.has(key):
			out.append(key)
	out.append_array(crew_only)
	return out


## One row per attribute (`attributes` order): `stat`, `ship` (true for a ship
## file number), `stock`, `current` and `sources`, each source `{"kind": "part",
## "name": <upgrade name>, "change"}` or `{"kind": "crew", "name": <role name>,
## "count", "change"}`, where `change` is what it adds. A part's change is
## taken in the order `ShipPartDef.apply` multiplies, before the final clamp.
## A fitting that `Fitting.check` refuses counts as empty, as the run drops it.
## A null `fitting`, `profile` or `roles` leaves that part out.
static func of(ship_data: Dictionary, fitting: Fitting, tree: UpgradeTree, profile: Profile, roles: CrewRoles,
		part_stats: Dictionary) -> Array[Dictionary]:
	var sources: Dictionary[String, Array] = {}
	var parts: Array[ShipPartDef] = _fitted_parts(ship_data, fitting, tree, profile, part_stats)
	var stepped: Dictionary = ship_data.duplicate(true)
	for part: ShipPartDef in parts:  # Already in id order, as `ShipPartDef.apply` takes them.
		for stat: String in part.stats:
			if not _is_number(stepped.get(stat)):
				continue
			var before: float = float(stepped[stat])
			stepped[stat] = before * part.stats[stat]
			_add(sources, stat, {"kind": KIND_PART, "name": part.display_name, "change": float(stepped[stat]) - before})
	var current: Dictionary = ShipPartDef.apply(ship_data, parts)
	var totals: Dictionary = {}
	if profile != null and roles != null and roles.error == "":
		totals = CrewBenefits.totals(profile, roles)
		current = CrewBenefits.apply_to_ship(current, totals)
		for group: Dictionary in CrewGroups.of(profile, roles):
			if roles.has_role(group["role"]) and int(group["total"]) != 0:
				_add(sources, CREW_SHIP_KEYS.get(group["stat"], group["stat"]), {"kind": KIND_CREW,
					"name": group["role_name"], "count": group["count"], "change": float(group["total"])})
	var rows: Array[Dictionary] = []
	for stat: String in attributes(part_stats, roles):
		var ship: bool = ShipTuning.KEYS.has(stat)
		var stock: float = float(ship_data.get(stat, 0.0)) if ship else 0.0
		rows.append({
			"stat": stat,
			"ship": ship,
			"stock": stock,
			"current": float(current.get(stat, stock)) if ship else float(totals.get(stat, 0)),
			"sources": sources.get(stat, []),
		})
	return rows


## The attributes whose current value differs between two summaries of the
## same attributes, as `{"stat", "ship", "before", "after"}` in `before`'s order.
static func changes(before: Array[Dictionary], after: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i: int in mini(before.size(), after.size()):
		var was: float = float(before[i]["current"])
		var now: float = float(after[i]["current"])
		if before[i]["stat"] == after[i]["stat"] and not is_equal_approx(was, now):
			out.append({"stat": before[i]["stat"], "ship": before[i]["ship"], "before": was, "after": now})
	return out


## The fitting's shield, hull and engine parts as `ShipPartDef`s in id order,
## named after the upgrades that grant them; none when the fitting is refused.
static func _fitted_parts(ship_data: Dictionary, fitting: Fitting, tree: UpgradeTree, profile: Profile,
		part_stats: Dictionary) -> Array[ShipPartDef]:
	var parts: Array[ShipPartDef] = []
	if fitting == null or fitting.is_empty() or tree == null or tree.error != "":
		return parts
	var crafted: Array[String] = [] if profile == null else profile.crafted
	if Fitting.check(fitting, tree, crafted, ship_data) != "":
		return parts
	for id: String in fitting.part_ids():
		var upgrade: UpgradeDef = tree.get_upgrade(id)
		if typeof(part_stats.get(upgrade.grants)) != TYPE_DICTIONARY:
			continue
		var part: ShipPartDef = ShipPartDef.new()
		part.id = upgrade.grants
		part.display_name = upgrade.display_name
		var stats: Dictionary = part_stats[upgrade.grants]
		for stat: Variant in stats:
			if _is_number(stats[stat]):
				part.stats[str(stat)] = float(stats[stat])
		parts.append(part)
	parts.sort_custom(func(a: ShipPartDef, b: ShipPartDef) -> bool: return a.id < b.id)
	return parts


static func _add(sources: Dictionary[String, Array], stat: String, source: Dictionary) -> void:
	if not sources.has(stat):
		sources[stat] = []
	sources[stat].append(source)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT
