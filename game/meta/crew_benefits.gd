class_name CrewBenefits
extends RefCounted

## Adds up what the profile's crew gives a run and applies it to a ship's data
## (CRW-1, CRW-3, #1041). Each role names one benefit; the crew's amounts are
## summed per stat and clamped to the stat's cap from the roles file, so a
## large crew widens options without trivialising early levels (CRW-3).
##
## Pure functions over plain data: the same crew and roles always give the
## same totals whatever order the crew is listed in (ARC-1). The shield goes
## into the ship's data (`apply_to_ship`); the salvage slots and the seconds
## before meltdown reach the simulation as a `CrewBonus` (`bonus`), installed
## by `RunLevelRules` before a run level's first tick (#1386); the map reveal
## is read by the map (#1393). A lost run never changes the crew, so nothing
## here touches run state (RUN-7).

## Benefit stat that raises the ship's `max_shield`.
const SHIELD_STAT: String = "shield_max"
## Ship data key the shield benefit adds to.
const SHIELD_KEY: String = "max_shield"
## Benefit stat that adds slots to the salvage hold.
const SALVAGE_STAT: String = "salvage_slots"
## Benefit stat that adds seconds to the meltdown countdown.
const MELTDOWN_STAT: String = "meltdown_seconds"


## Stat to summed amount for the profile's crew, each clamped to its cap in
## `roles`, keys sorted. An empty crew gives `{}`. A member whose role is
## unknown, or whose entry is malformed, is skipped; the reason from
## `CrewRoster.check` is appended to `problems` so the caller can report it
## instead of the run crashing.
static func totals(profile: Profile, roles: CrewRoles, problems: Array[String] = []) -> Dictionary:
	if roles == null or roles.error != "":
		problems.append("no crew roles to read%s" % ("" if roles == null else ": " + roles.error))
		return {}
	if profile == null:
		problems.append("no profile to read")
		return {}
	var reason: String = CrewRoster.check(profile, roles)
	if reason != "":
		problems.append(reason)
	var sums: Dictionary[String, int] = {}
	for entry: Variant in profile.crew:
		var role: String = _role_of(entry)
		if not roles.has_role(role):
			continue
		var stat: String = roles.benefit_stat(role)
		sums[stat] = sums.get(stat, 0) + roles.benefit_amount(role)
	var stats: Array[String] = []
	stats.assign(sums.keys())
	stats.sort()
	var result: Dictionary = {}
	for stat: String in stats:
		result[stat] = mini(sums[stat], roles.cap(stat))
	return result


## Copy of `ship_data` (the parsed ship file) with the crew's shield bonus
## added to its `max_shield`, kept inside `ShipTuning.RANGES`. Only the shield
## lives in the ship file; see `bonus` for the rest. `ship_data` is never edited.
static func apply_to_ship(ship_data: Dictionary, crew_totals: Dictionary) -> Dictionary:
	var ship: Dictionary = ship_data.duplicate(true)
	if not crew_totals.has(SHIELD_STAT) or not ship.has(SHIELD_KEY):
		return ship
	var bounds: Array = ShipTuning.RANGES[SHIELD_KEY]
	var raised: float = float(ship[SHIELD_KEY]) + float(crew_totals[SHIELD_STAT])
	ship[SHIELD_KEY] = clampf(raised, float(bounds[0]), float(bounds[1]))
	return ship


## The salvage slots and seconds before meltdown of `crew_totals` (already
## capped by `totals`) as the simulation's `CrewBonus`. Zero without either;
## a value core refuses comes back with `error` set and is not installed.
static func bonus(crew_totals: Dictionary) -> CrewBonus:
	return CrewBonus.of(int(crew_totals.get(SALVAGE_STAT, 0)), int(crew_totals.get(MELTDOWN_STAT, 0)))


## Role id of a crew entry, or "" when the entry has none.
static func _role_of(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return ""
	var member: Dictionary = entry
	var role: Variant = member.get(Profile.CREW_ROLE, "")
	return role if typeof(role) == TYPE_STRING else ""
