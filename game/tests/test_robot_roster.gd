extends RefCounted

## The robot roster as a whole: six or more types, every file valid, every
## reference resolving, no two types alike (CMB-3, SLV-1, ARC-4, #206).

const ROBOTS_DIR: String = "res://data/robots"
const MIN_TYPES: int = 6
## Fields in which two robot types must differ in at least `MIN_DIFFERENCES`.
const COMPARED: Array[String] = ["movement", "max_speed", "turn_rate", "hull", "radius"]
const MIN_DIFFERENCES: int = 2
const MIN_WEAPONS: int = 3


func test_every_robot_file_parses() -> String:
	var names: PackedStringArray = _robot_files()
	if names.is_empty():
		return "no robot files in %s" % ROBOTS_DIR
	for file: String in names:
		var robot: RobotDef = _load(file)
		if robot.error != "":
			return "%s rejected: %s" % [file, robot.error]
	return ""


func test_at_least_six_types() -> String:
	var count: int = _robot_files().size()
	if count < MIN_TYPES:
		return "%d robot files, need at least %d" % [count, MIN_TYPES]
	return ""


func test_ids_match_file_names_and_are_unique() -> String:
	var seen: Dictionary = {}
	for file: String in _robot_files():
		var robot: RobotDef = _load(file)
		if robot.id != file.get_basename():
			return "%s has id \"%s\"" % [file, robot.id]
		if seen.has(robot.id):
			return "id \"%s\" appears twice" % robot.id
		seen[robot.id] = true
	return ""


## Every weapon a robot fires is a robot weapon file and every part it drops a
## ship weapon file, and each parses (SLV-1, #612).
func test_weapon_and_salvage_resolve() -> String:
	for file: String in _robot_files():
		var robot: RobotDef = _load(file)
		for path: String in [robot.weapon_path(), "%s/%s.json" % [RobotDef.WEAPONS_DIR, robot.salvage]]:
			if not FileAccess.file_exists(path):
				return "%s: %s does not exist" % [file, path]
			var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(path))
			if weapon.error != "":
				return "%s: %s" % [path, weapon.error]
	return ""


func test_every_weapon_file_parses() -> String:
	for file: String in DirAccess.get_files_at(RobotDef.WEAPONS_DIR):
		if file.get_extension() != "json":
			continue
		var path: String = "%s/%s" % [RobotDef.WEAPONS_DIR, file]
		var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(path))
		if weapon.error != "":
			return "%s rejected: %s" % [file, weapon.error]
	return ""


func test_every_movement_is_used() -> String:
	var used: Dictionary = {}
	for file: String in _robot_files():
		used[_load(file).movement] = true
	for name: String in RobotDef.MOVEMENTS:
		if not used.has(name):
			return "no robot uses movement \"%s\"" % name
	return ""


func test_attacks_differ() -> String:
	var weapons: Dictionary = {}
	for file: String in _robot_files():
		weapons[_load(file).weapon] = true
	if weapons.size() < MIN_WEAPONS:
		return "%d different weapons across the roster, need %d" % [weapons.size(), MIN_WEAPONS]
	return ""


## Every pair differs in at least two of the compared fields, so no type is a
## copy of another with one number nudged.
func test_no_two_robots_alike() -> String:
	var robots: Array[RobotDef] = []
	for file: String in _robot_files():
		robots.append(_load(file))
	for i: int in robots.size():
		for j: int in range(i + 1, robots.size()):
			var differences: int = _differences(robots[i], robots[j])
			if differences < MIN_DIFFERENCES:
				return "%s and %s differ in only %d of %s" % [robots[i].id, robots[j].id, differences, COMPARED]
	return ""


## The comparison itself: a copy with one field changed counts as alike.
func test_near_copy_counts_as_alike() -> String:
	var a: RobotDef = _load("drone.json")
	var b: RobotDef = _load("drone.json")
	b.hull += 1.0
	if _differences(a, b) != 1:
		return "one changed field counted as %d differences" % _differences(a, b)
	b.movement = "chase"
	if _differences(a, b) != 2:
		return "two changed fields counted as %d differences" % _differences(a, b)
	return ""


func _differences(a: RobotDef, b: RobotDef) -> int:
	var count: int = 0
	for field: String in COMPARED:
		if a.get(field) != b.get(field):
			count += 1
	return count


func _robot_files() -> PackedStringArray:
	var names: PackedStringArray = []
	for file: String in DirAccess.get_files_at(ROBOTS_DIR):
		if file.get_extension() == "json":
			names.append(file)
	names.sort()
	return names


func _load(file: String) -> RobotDef:
	return RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s" % [ROBOTS_DIR, file]))
