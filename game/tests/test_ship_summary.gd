extends RefCounted

## The ship summary (#1357, CRF-4, CRW-1, CRW-3, ARC-4): stock, current and the
## sources of every attribute parts and crew can change, summed for stock,
## fitted, crew and both, and equal to what `RunStartShip.build` flies.

const Fixtures := preload("res://tests/test_run_start_ship.gd")


static func _part_stats() -> Dictionary:
	return HubPartInfo.load_shipped().parts


static func _summary(fitting: Fitting, profile: Profile, roles: CrewRoles = Fixtures._roles()) -> Array[Dictionary]:
	return ShipSummary.of(Fixtures._ship_data(), fitting, Fixtures._tree(), profile, roles, _part_stats())


static func _row(rows: Array[Dictionary], stat: String) -> Dictionary:
	for row: Dictionary in rows:
		if row["stat"] == stat:
			return row
	return {}


static func _parts_fitting(parts: Dictionary) -> Fitting:
	var fitting: Fitting = Fitting.new()
	for slot: String in parts:
		fitting.parts[slot] = parts[slot]
	return fitting


## "" when the row's sources add up to its difference from stock.
static func _adds_up(row: Dictionary) -> String:
	var sum: float = 0.0
	for source: Dictionary in row["sources"]:
		sum += float(source["change"])
	if not is_equal_approx(float(row["stock"]) + sum, float(row["current"])):
		return "%s: stock %s + sources %s is not current %s" % [row["stat"], row["stock"], sum, row["current"]]
	return ""


func test_attributes_come_from_the_part_files_and_the_roles() -> String:
	var stats: Dictionary = _part_stats()
	var roles: CrewRoles = Fixtures._roles()
	var listed: Array[String] = ShipSummary.attributes(stats, roles)
	for part: Variant in stats:
		for stat: Variant in stats[part]:
			if not listed.has(str(stat)):
				return "%s of %s is not listed: %s" % [stat, part, listed]
	for role: String in roles.ids:
		var stat: String = roles.benefit_stat(role)
		if not listed.has(ShipSummary.CREW_SHIP_KEYS.get(stat, stat)):
			return "crew stat %s is not listed: %s" % [stat, listed]
	var crew_only: bool = false
	for stat: String in listed:
		if listed.count(stat) != 1:
			return "%s listed twice" % stat
		if crew_only and ShipTuning.KEYS.has(stat):
			return "ship number %s comes after a crew stat: %s" % [stat, listed]
		crew_only = crew_only or not ShipTuning.KEYS.has(stat)
	# A new stat in the data needs no code: one made-up part file is enough.
	var made_up: Array[String] = ShipSummary.attributes({"x": {"max_energy": 1.2}}, null)
	return "" if made_up == (["max_energy"] as Array[String]) else "made-up part lists %s" % [made_up]


func test_the_stock_ship_has_no_sources() -> String:
	var rows: Array[Dictionary] = _summary(Fitting.new(), Profile.new())
	if rows.is_empty():
		return "no rows"
	var ship: Dictionary = Fixtures._ship_data()
	for row: Dictionary in rows:
		var stock: float = float(ship[row["stat"]]) if row["ship"] else 0.0
		if not (row["sources"] as Array).is_empty() or row["stock"] != stock or row["current"] != stock:
			return "stock row %s" % row
	return ""


func test_fitted_parts_add_up_by_name() -> String:
	var profile: Profile = Fixtures._profile(["tuned_thrusters", "shield_capacitor", "lattice_shield"] as Array[String])
	var rows: Array[Dictionary] = _summary(_parts_fitting({"engine": "tuned_thrusters", "shield": "lattice_shield"}), profile)
	var speed: Dictionary = _row(rows, "max_speed")
	if not is_equal_approx(speed["current"], 22.0) or speed["stock"] != 20.0:
		return "speed row %s" % speed
	var source: Dictionary = speed["sources"][0]
	if source["kind"] != ShipSummary.KIND_PART or source["name"] != "Tuned Thrusters" or not is_equal_approx(source["change"], 2.0):
		return "speed source %s" % source
	if not is_equal_approx(_row(rows, "acceleration")["current"], 46.0) or not is_equal_approx(_row(rows, "max_shield")["current"], 57.5):
		return "thrust %s, shield %s" % [_row(rows, "acceleration"), _row(rows, "max_shield")]
	for row: Dictionary in rows:
		var problem: String = _adds_up(row)
		if problem != "":
			return problem
	return "" if (_row(rows, "max_hull")["sources"] as Array).is_empty() else "an unfitted hull has sources"


func test_crew_adds_up_by_role_and_cap() -> String:
	var profile: Profile = Fixtures._profile([] as Array[String],
		["shield_tech", "shield_tech", "cargo_rigger"] as Array[String])
	var rows: Array[Dictionary] = _summary(Fitting.new(), profile)
	var shield: Dictionary = _row(rows, "max_shield")
	if shield["current"] != 65.0 or shield["stock"] != 50.0:  # Two at 10 each, capped at 15.
		return "shield row %s" % shield
	var source: Dictionary = shield["sources"][0]
	if source["kind"] != ShipSummary.KIND_CREW or source["name"] != "Shield Technician" or source["count"] != 2 or source["change"] != 15.0:
		return "shield source %s" % source
	var slots: Dictionary = _row(rows, "salvage_slots")
	if slots["ship"] or slots["stock"] != 0.0 or slots["current"] != 1.0 or (slots["sources"] as Array).size() != 1:
		return "salvage row %s" % slots
	return "" if _row(rows, "meltdown_seconds")["current"] == 0.0 else "no reactor hand, yet %s" % _row(rows, "meltdown_seconds")


func test_parts_and_crew_both_count() -> String:
	var profile: Profile = Fixtures._profile(["shield_capacitor", "lattice_shield"] as Array[String],
		["shield_tech", "shield_tech"] as Array[String])
	var shield: Dictionary = _row(_summary(_parts_fitting({"shield": "lattice_shield"}), profile), "max_shield")
	if not is_equal_approx(shield["current"], 72.5) or (shield["sources"] as Array).size() != 2:
		return "shield row %s" % shield  # 50 x 1.15 = 57.5, then +15 crew.
	return _adds_up(shield)


func test_current_is_what_the_run_flies() -> String:
	var crafted: Array[String] = ["tuned_thrusters", "vectored_thrusters", "torsion_drive", "layered_plating",
		"ribbed_frame", "fused_bulkhead", "shield_capacitor", "lattice_shield", "glass_core_shield"]
	var profile: Profile = Fixtures._profile(crafted, ["shield_tech", "reactor_hand", "shield_tech"] as Array[String])
	var fitting: Fitting = _parts_fitting({"engine": "torsion_drive", "hull": "fused_bulkhead", "shield": "glass_core_shield"})
	var flown: Dictionary = RunStartShip.build(Fixtures._ship_data(), fitting, Fixtures._tree(), profile, Fixtures._roles())
	for row: Dictionary in _summary(fitting, profile):
		if row["ship"] and not is_equal_approx(float(flown[row["stat"]]), row["current"]):
			return "%s: summary %s, run flies %s" % [row["stat"], row["current"], flown[row["stat"]]]
	return ""


func test_a_refused_fitting_counts_as_stock() -> String:
	var rows: Array[Dictionary] = _summary(_parts_fitting({"engine": "tuned_thrusters"}), Profile.new())  # Not crafted.
	return "" if _row(rows, "max_speed")["current"] == 20.0 else "speed %s" % _row(rows, "max_speed")


func test_changes_lists_only_what_differs() -> String:
	var profile: Profile = Fixtures._profile(["tuned_thrusters"] as Array[String])
	var before: Array[Dictionary] = _summary(Fitting.new(), profile)
	var after: Array[Dictionary] = _summary(_parts_fitting({"engine": "tuned_thrusters"}), profile)
	var changes: Array[Dictionary] = ShipSummary.changes(before, after)
	if changes.size() != 2 or changes[0]["stat"] != "max_speed" or changes[1]["stat"] != "acceleration":
		return "changes %s" % [changes]
	if changes[0]["before"] != 20.0 or not is_equal_approx(changes[0]["after"], 22.0):
		return "speed change %s" % changes[0]
	return "" if ShipSummary.changes(before, before).is_empty() else "a summary differs from itself"
