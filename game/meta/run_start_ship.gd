class_name RunStartShip
extends RefCounted

## The ship a run starts with: the ship file, the pilot's fitting and the crew's
## benefits combined in one pure step (CRF-4, CMB-1, CRW-1, #1054). The run
## start and the hub's launch both call `build`, so they always fly the same ship.
##
## A bad save never blocks a run: a fitting that no longer checks out (for
## example after a data change) is dropped with a note and the ship file's own
## loadout flies instead, and crew problems are noted and skipped. Pure over
## plain data, so the same inputs give the same dictionary, key order included
## (ARC-1, ARC-2).


## Copy of `ship_data` (the parsed ship file) with its `loadout` section from
## `Fitting.loadout` and the crew's totals applied by `CrewBenefits.apply_to_ship`.
## A null `fitting`, `profile` or `roles` leaves that part out; without a
## profile nothing counts as crafted, so a non-empty fitting is then refused.
## Reasons for anything left out are appended to `notes`. `ship_data` is never
## changed.
static func build(ship_data: Dictionary, fitting: Fitting, tree: UpgradeTree, profile: Profile, roles: CrewRoles, notes: Array[String] = []) -> Dictionary:
	var ship: Dictionary = ship_data.duplicate(true)
	if fitting != null and not fitting.is_empty():
		var reason: String = _fitting_reason(fitting, tree, profile, ship_data)
		if reason == "":
			ship[ShipTuning.LOADOUT_KEY] = Fitting.loadout(fitting, tree, ship_data)
		else:
			notes.append("fitting ignored, the ship file's loadout flies: %s" % reason)
	if profile != null and roles != null:
		var problems: Array[String] = []
		var crew_totals: Dictionary = CrewBenefits.totals(profile, roles, problems)
		for problem: String in problems:
			notes.append("crew: %s" % problem)
		ship = CrewBenefits.apply_to_ship(ship, crew_totals)
	return ship


## Why `fitting` cannot start a run on this ship, or "".
static func _fitting_reason(fitting: Fitting, tree: UpgradeTree, profile: Profile, ship_data: Dictionary) -> String:
	if tree == null or tree.error != "":
		return "no upgrade tree to read%s" % ("" if tree == null else ": " + tree.error)
	var crafted: Array[String] = [] if profile == null else profile.crafted
	return Fitting.check(fitting, tree, crafted, ship_data)
