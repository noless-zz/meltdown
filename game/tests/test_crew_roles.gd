extends RefCounted

## Crew roles as data (CRW-1, ARC-4, #964): the shipped file loads, every bad
## entry fails naming the role and key, and a seeded pick is stable and
## follows the weights (ARC-2).

const ROLE_A: String = "{\"id\": \"alpha\", \"name\": \"Alpha\", \"weight\": 3, \"benefit\": {\"stat\": \"shield_max\", \"amount\": 5}}"
const ROLE_B: String = "{\"id\": \"beta\", \"name\": \"Beta\", \"weight\": 1, \"benefit\": {\"stat\": \"map_reveal\", \"amount\": 1}}"
## Words from the original games that must never name a role (NAM-3).
const BANNED: Array[String] = ["descent", "pyro", "ptmc", "vertigo", "guide", "thief", "dravis", "samindhi", "defender", "phoenix"]


const CAPS: String = "{\"map_reveal\": 1, \"meltdown_seconds\": 20, \"salvage_slots\": 2, \"shield_max\": 25}"


func _text(roles: Array[String], caps: String = CAPS) -> String:
	return "{\"roles\": [%s], \"caps\": %s}" % [", ".join(roles), caps]


func _shipped() -> CrewRoles:
	return CrewRoles.parse_json(FileAccess.get_file_as_string(CrewRoles.ROLES_FILE))


func test_shipped_file_loads_with_four_or_more_roles() -> String:
	var roles: CrewRoles = _shipped()
	if roles.error != "":
		return roles.error
	if roles.ids.size() < 4:
		return "only %d roles shipped" % roles.ids.size()
	for id: String in roles.ids:
		if roles.weight(id) <= 0 or roles.benefit_amount(id) <= 0:
			return "%s has no weight or amount" % id
		if roles.benefit_amount(id) > CrewRoles.STAT_MAX[roles.benefit_stat(id)]:
			return "%s gives more than its stat's cap" % id
	return ""


func test_shipped_names_avoid_the_original_games() -> String:
	var text: String = FileAccess.get_file_as_string(CrewRoles.ROLES_FILE).to_lower()
	for word: String in BANNED:
		if text.contains(word):
			return "roles file contains \"%s\"" % word
	return ""


func test_good_text_sets_every_field() -> String:
	var roles: CrewRoles = CrewRoles.parse_json(_text([ROLE_A, ROLE_B]))
	if roles.error != "":
		return roles.error
	if roles.ids != ["alpha", "beta"] or roles.total_weight() != 4:
		return "ids %s total %d" % [str(roles.ids), roles.total_weight()]
	if roles.role_name("alpha") != "Alpha" or roles.weight("alpha") != 3:
		return "alpha name or weight not read"
	if roles.benefit_stat("beta") != "map_reveal" or roles.benefit_amount("beta") != 1:
		return "beta benefit not read"
	if roles.has_role("gamma") or roles.role_name("gamma") != "" or roles.benefit_amount("gamma") != 0:
		return "unknown id answered"
	return ""


func test_bad_values_name_the_role_and_key() -> String:
	var cases: Dictionary = {
		"\"weight\": 3": ["\"weight\": 0", "\"weight\": -2", "\"weight\": 1.5", "\"weight\": true", "\"weight\": \"3\""],
		"\"name\": \"Alpha\"": ["\"name\": \"\"", "\"name\": \"  \"", "\"name\": 4"],
		"\"stat\": \"shield_max\"": ["\"stat\": \"hull_max\"", "\"stat\": 2"],
		"\"amount\": 5": ["\"amount\": 0", "\"amount\": 11", "\"amount\": 2.5"],
	}
	var keys: Dictionary = {"\"weight\": 3": "weight", "\"name\": \"Alpha\"": "name", "\"stat\": \"shield_max\"": "stat", "\"amount\": 5": "amount"}
	for good: String in cases:
		for bad: String in cases[good]:
			var role: String = ROLE_A.replace(good, bad)
			if role == ROLE_A:
				return "case %s did not change the text" % bad
			var roles: CrewRoles = CrewRoles.parse_json(_text([ROLE_B, role]))
			if not roles.error.begins_with("role \"alpha\":") or not roles.error.contains("\"%s\"" % keys[good]):
				return "%s gave \"%s\"" % [bad, roles.error]
			if not roles.ids.is_empty():
				return "rejected file kept roles"
	return ""


func test_missing_and_unknown_keys_name_the_role_and_key() -> String:
	for key: String in CrewRoles.ROLE_KEYS:
		var json: JSON = JSON.new()
		json.parse(ROLE_A)
		var data: Dictionary = json.data
		data.erase(key)
		var roles: CrewRoles = CrewRoles.parse_json(_text([JSON.stringify(data)]))
		var who: String = "role 1" if key == "id" else "role \"alpha\""
		if roles.error != "%s: missing key \"%s\"" % [who, key]:
			return "missing %s gave \"%s\"" % [key, roles.error]
	var no_amount: CrewRoles = CrewRoles.parse_json(_text([ROLE_A.replace(", \"amount\": 5", "")]))
	if no_amount.error != "role \"alpha\": key \"benefit\" is missing key \"amount\"":
		return "missing amount gave \"%s\"" % no_amount.error
	var extra: CrewRoles = CrewRoles.parse_json(_text([ROLE_A.replace("}}", "}, \"wieght\": 2}")]))
	if extra.error != "role \"alpha\": unknown key \"wieght\"":
		return "unknown key gave \"%s\"" % extra.error
	return ""


func test_duplicate_id_and_broken_files_fail() -> String:
	var twice: CrewRoles = CrewRoles.parse_json(_text([ROLE_A, ROLE_B, ROLE_A]))
	if not twice.error.begins_with("role \"alpha\":") or not twice.error.contains("\"id\""):
		return "duplicate gave \"%s\"" % twice.error
	var no_caps: String = "{\"roles\": [%s]}" % ROLE_A
	for text: String in ["[]", "{}", "{\"roles\": []}", "{\"roles\": [3]}", "{\"roles\": [], \"x\": 1}", "{", no_caps]:
		var roles: CrewRoles = CrewRoles.parse_json(text)
		if roles.error == "" or not roles.ids.is_empty():
			return "%s was accepted" % text
	return ""


func test_same_seed_gives_same_role() -> String:
	var roles: CrewRoles = _shipped()
	var again: CrewRoles = _shipped()
	for role_seed: int in [0, 1, 42, -7, 123456789]:
		var id: String = roles.pick(role_seed)
		if not roles.has_role(id):
			return "seed %d picked \"%s\"" % [role_seed, id]
		if again.pick(role_seed) != id or roles.pick(role_seed) != id:
			return "seed %d picked differently" % role_seed
	return ""


func test_pick_does_not_move_the_global_stream() -> String:
	seed(99)
	var expected: int = randi()
	seed(99)
	_shipped().pick(5)
	if randi() != expected:
		return "pick used the global generator"
	return ""


func test_shares_follow_weights_over_ten_thousand_seeds() -> String:
	var roles: CrewRoles = _shipped()
	var counts: Dictionary[String, int] = {}
	for role_seed: int in 10000:
		var id: String = roles.pick(role_seed)
		counts[id] = counts.get(id, 0) + 1
	for id: String in roles.ids:
		var share: float = float(counts.get(id, 0)) / 10000.0
		var wanted: float = float(roles.weight(id)) / float(roles.total_weight())
		if absf(share - wanted) > 0.02:
			return "%s share %.4f, weight share %.4f" % [id, share, wanted]
	return ""


func test_new_role_is_added_by_text_alone() -> String:
	var roles: CrewRoles = CrewRoles.parse_json(_text([ROLE_A, ROLE_B.replace("beta", "gamma")]))
	if roles.error != "" or not roles.has_role("gamma"):
		return "new role not read: %s" % roles.error
	return ""


func test_shipped_caps_cover_every_stat() -> String:
	var roles: CrewRoles = _shipped()
	for stat: String in CrewRoles.STAT_MAX:
		if roles.cap(stat) < 1:
			return "%s has cap %d" % [stat, roles.cap(stat)]
	if str(roles.caps().keys()) != str(["map_reveal", "meltdown_seconds", "salvage_slots", "shield_max"]):
		return "caps keys %s" % str(roles.caps().keys())
	return ""


func test_bad_caps_name_the_key() -> String:
	var cases: Dictionary = {
		"{\"map_reveal\": 1, \"meltdown_seconds\": 20, \"salvage_slots\": 2}": "caps: missing key \"shield_max\"",
		"{\"map_reveal\": 1, \"meltdown_seconds\": 20, \"salvage_slots\": 2, \"shield_max\": 25, \"hull_max\": 3}": "\"hull_max\"",
		"{\"map_reveal\": 0, \"meltdown_seconds\": 20, \"salvage_slots\": 2, \"shield_max\": 25}": "\"map_reveal\" is 0",
		"{\"map_reveal\": 1, \"meltdown_seconds\": 2.5, \"salvage_slots\": 2, \"shield_max\": 25}": "\"meltdown_seconds\"",
		"[1]": "key \"caps\" must be a JSON object",
	}
	for caps: String in cases:
		var roles: CrewRoles = CrewRoles.parse_json(_text([ROLE_A], caps))
		if not roles.error.contains(cases[caps]):
			return "%s gave \"%s\"" % [caps, roles.error]
		if not roles.ids.is_empty() or roles.cap("shield_max") != 0:
			return "rejected file kept roles or caps"
	return ""
