extends RefCounted

## Crew benefits summed with a cap per stat, and the shield bonus applied to
## the ship's data (CRW-1, CRW-3, #1041).

const SHIP_FILE: String = "res://data/ships/default_ship.json"
## A fixed copy of the roles, so the numbers below do not move when the
## shipped roles file is tuned.
const ROLES_TEXT: String = """{"roles": [
	{"id": "surveyor", "name": "Surveyor", "weight": 30, "benefit": {"stat": "map_reveal", "amount": 1}},
	{"id": "shield_tech", "name": "Shield Technician", "weight": 25, "benefit": {"stat": "shield_max", "amount": 5}},
	{"id": "cargo_rigger", "name": "Cargo Rigger", "weight": 25, "benefit": {"stat": "salvage_slots", "amount": 1}},
	{"id": "reactor_hand", "name": "Reactor Hand", "weight": 20, "benefit": {"stat": "meltdown_seconds", "amount": 5}}
], "caps": {"map_reveal": 1, "meltdown_seconds": 20, "salvage_slots": 2, "shield_max": 25}}"""


func _roles() -> CrewRoles:
	return CrewRoles.parse_json(ROLES_TEXT)


func _profile(role_ids: Array[String]) -> Profile:
	var profile: Profile = Profile.new()
	for i: int in role_ids.size():
		profile.crew.append({Profile.CREW_ID: "crew-%d" % (i + 1), Profile.CREW_ROLE: role_ids[i]})
	return profile


func _ship_data() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHIP_FILE))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _ship_hash(ship_data: Dictionary) -> int:
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(ship_data))
	if tuning.error != "":
		return -1
	var ship: ShipState = ShipState.new()
	tuning.apply_to(ship)
	ship.apply_damage(30.0)
	return ship.state_hash()


func _repeat(role: String, count: int) -> Array[String]:
	var ids: Array[String] = []
	for i: int in count:
		ids.append(role)
	return ids


func test_roles_fixture_loads() -> String:
	return _roles().error


func test_no_crew_keeps_the_ship_state_hash() -> String:
	var problems: Array[String] = []
	var crew_totals: Dictionary = CrewBenefits.totals(_profile([]), _roles(), problems)
	if crew_totals != {} or not problems.is_empty():
		return "empty crew gave %s %s" % [str(crew_totals), str(problems)]
	var base: Dictionary = _ship_data()
	var applied: Dictionary = CrewBenefits.apply_to_ship(base, crew_totals)
	if applied != base:
		return "empty totals changed the ship data"
	if _ship_hash(applied) != _ship_hash(base) or _ship_hash(base) == -1:
		return "empty totals changed the state hash"
	return ""


func test_two_shield_technicians_add_ten() -> String:
	var crew_totals: Dictionary = CrewBenefits.totals(_profile(_repeat("shield_tech", 2)), _roles())
	if crew_totals != {"shield_max": 10}:
		return "totals %s" % str(crew_totals)
	var base: Dictionary = _ship_data()
	var applied: Dictionary = CrewBenefits.apply_to_ship(base, crew_totals)
	if not is_equal_approx(float(applied["max_shield"]), float(base["max_shield"]) + 10.0):
		return "max_shield %s from %s" % [applied["max_shield"], base["max_shield"]]
	if ShipTuning.parse_json(JSON.stringify(applied)).error != "":
		return "applied data no longer parses"
	if _ship_hash(applied) == _ship_hash(base):
		return "a bigger shield did not change the damaged ship's hash"
	return ""


func test_six_shield_technicians_add_only_the_cap() -> String:
	var crew_totals: Dictionary = CrewBenefits.totals(_profile(_repeat("shield_tech", 6)), _roles())
	if crew_totals != {"shield_max": 25}:
		return "totals %s" % str(crew_totals)
	return ""


func test_totals_sum_each_stat_with_sorted_keys() -> String:
	var ids: Array[String] = ["reactor_hand", "surveyor", "surveyor", "cargo_rigger", "shield_tech", "reactor_hand"]
	var crew_totals: Dictionary = CrewBenefits.totals(_profile(ids), _roles())
	var expected: Dictionary = {"map_reveal": 1, "meltdown_seconds": 10, "salvage_slots": 1, "shield_max": 5}
	if crew_totals != expected:
		return "totals %s" % str(crew_totals)
	if crew_totals.keys() != ["map_reveal", "meltdown_seconds", "salvage_slots", "shield_max"]:
		return "keys not sorted: %s" % str(crew_totals.keys())
	return ""


func test_crew_order_does_not_change_the_result() -> String:
	var ids: Array[String] = ["shield_tech", "surveyor", "reactor_hand", "shield_tech", "cargo_rigger", "reactor_hand"]
	var first: Dictionary = CrewBenefits.totals(_profile(ids), _roles())
	var reversed: Array[String] = ids.duplicate()
	reversed.reverse()
	var second: Dictionary = CrewBenefits.totals(_profile(reversed), _roles())
	if first != second or first.keys() != second.keys():
		return "%s vs %s" % [str(first), str(second)]
	var base: Dictionary = _ship_data()
	if CrewBenefits.apply_to_ship(base, first) != CrewBenefits.apply_to_ship(base, second):
		return "applied ships differ"
	return ""


func test_bad_caps_key_is_an_error_naming_it() -> String:
	var bad: CrewRoles = CrewRoles.parse_json(ROLES_TEXT.replace("\"map_reveal\": 1, \"meltdown", "\"map_reveel\": 1, \"meltdown"))
	if not bad.error.contains("\"map_reveel\""):
		return "bad caps key gave \"%s\"" % bad.error
	var problems: Array[String] = []
	if CrewBenefits.totals(_profile(["shield_tech"]), bad, problems) != {} or problems.is_empty():
		return "rejected roles still gave totals"
	return ""


func test_unknown_role_is_reported_and_skipped() -> String:
	var problems: Array[String] = []
	var profile: Profile = _profile(["shield_tech", "dowser", "shield_tech"])
	var crew_totals: Dictionary = CrewBenefits.totals(profile, _roles(), problems)
	if crew_totals != {"shield_max": 10}:
		return "totals %s" % str(crew_totals)
	if problems.size() != 1 or problems[0] != CrewRoster.check(profile, _roles()) or not problems[0].contains("\"dowser\""):
		return "problems %s" % str(problems)
	return ""


func test_apply_never_edits_its_argument() -> String:
	var base: Dictionary = _ship_data()
	var before: Dictionary = base.duplicate(true)
	var applied: Dictionary = CrewBenefits.apply_to_ship(base, {"shield_max": 25, "map_reveal": 1})
	if base != before:
		return "argument edited"
	if applied.size() != base.size() or applied["max_speed"] != base["max_speed"]:
		return "other keys changed"
	return ""


func test_shield_stays_inside_its_range() -> String:
	var base: Dictionary = _ship_data()
	base["max_shield"] = 9990.0
	var applied: Dictionary = CrewBenefits.apply_to_ship(base, {"shield_max": 25})
	if float(applied["max_shield"]) != float(ShipTuning.RANGES["max_shield"][1]):
		return "max_shield %s" % applied["max_shield"]
	return ""
