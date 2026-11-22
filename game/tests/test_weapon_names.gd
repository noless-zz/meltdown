extends RefCounted

## Weapon files name their weapon for the status panel (#1210, PLT-2, ARC-4):
## an optional `name` key that the simulation never reads, so it moves no hash.

const WEAPON_DIR: String = "res://data/weapons/"
const BASE: String = '{"fire_interval_ticks": 10, "projectile_speed": 120.0, "lifetime": 1.5, ' \
	+ '"damage": 8.0, "energy_cost": 2.0%s}'


func test_every_shipped_weapon_has_a_readable_name() -> String:
	var seen: Array[String] = []
	for file: String in DirAccess.get_files_at(WEAPON_DIR):
		if not file.ends_with(".json"):
			continue
		var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(WEAPON_DIR + file))
		if weapon.error != "":
			return "%s: %s" % [file, weapon.error]
		if weapon.name.is_empty() or weapon.name == file.get_basename():
			return "%s is named '%s'" % [file, weapon.name]
		if seen.has(weapon.name):
			return "two weapons are named %s" % weapon.name
		seen.append(weapon.name)
	if seen.size() < 2:
		return "only %d weapon files found" % seen.size()
	return ""


func test_a_name_is_optional_and_moves_no_hash() -> String:
	var plain: WeaponDef = WeaponDef.parse_json(BASE % "")
	var named: WeaponDef = WeaponDef.parse_json(BASE % ', "name": "  Test Gun "')
	if plain.error != "" or named.error != "":
		return "rejected: %s / %s" % [plain.error, named.error]
	if plain.name != "" or named.name != "Test Gun":
		return "names read '%s' and '%s'" % [plain.name, named.name]
	if plain.values_hash() != named.values_hash():
		return "a name changed the weapon's hash"
	if ReplayLines.weapon_data(named).has("name"):
		return "the replay's weapon lines carry the name"
	return ""


func test_a_bad_name_is_rejected_naming_the_key() -> String:
	for bad: String in ['""', '"   "', "3", "true", '"%s"' % "x".repeat(WeaponDef.MAX_NAME_LENGTH + 1)]:
		var weapon: WeaponDef = WeaponDef.parse_json(BASE % (', "name": %s' % bad))
		if not weapon.error.contains("\"name\""):
			return "name %s gives '%s', not an error naming the key" % [bad, weapon.error]
	return ""
