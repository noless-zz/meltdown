extends RefCounted

## Robots as data files (CMB-3, SLV-1, ARC-4, ARC-1, #188).

const DRONE: String = "res://data/robots/drone.json"
const GOOD: String = "{\"id\": \"drone\", \"hull\": 20.0, \"radius\": 0.8, \"max_speed\": 8.0, \"acceleration\": 16.0, \"turn_rate\": 120.0, \"movement\": \"hover\", \"weapon\": \"pulse_cannon\", \"salvage\": \"pulse_cannon\"}"


func test_drone_file_parses() -> String:
	if not FileAccess.file_exists(DRONE):
		return "missing %s" % DRONE
	var robot: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	if robot.error != "":
		return "drone.json rejected: %s" % robot.error
	if robot.id != "drone":
		return "id \"%s\" does not match the file name" % robot.id
	if robot.weapon != "pulse_cannon" or robot.salvage != "pulse_cannon":
		return "drone fires \"%s\" and drops \"%s\"" % [robot.weapon, robot.salvage]
	return ""


## The drone's weapon and salvage resolve to a weapon file that itself parses.
func test_drone_weapon_resolves() -> String:
	var robot: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string(DRONE))
	var path: String = robot.weapon_path()
	if path != "res://data/weapons/pulse_cannon.json" or not FileAccess.file_exists(path):
		return "weapon path \"%s\" does not resolve" % path
	if WeaponDef.parse_json(FileAccess.get_file_as_string(path)).error != "":
		return "the drone's weapon file does not parse"
	if not FileAccess.file_exists("%s/%s.json" % [RobotDef.WEAPONS_DIR, robot.salvage]):
		return "salvage \"%s\" does not resolve" % robot.salvage
	return ""


func test_good_text_sets_every_field() -> String:
	var text: String = GOOD.replace("\"hover\"", "\"strafe\"").replace("\"hull\": 20.0", "\"hull\": 35.5")
	var robot: RobotDef = RobotDef.parse_json(text)
	if robot.error != "":
		return "rejected: %s" % robot.error
	if robot.hull != 35.5 or robot.radius != 0.8 or robot.max_speed != 8.0:
		return "hull %f, radius %f, max speed %f" % [robot.hull, robot.radius, robot.max_speed]
	if robot.acceleration != 16.0 or robot.turn_rate != 120.0 or robot.movement != "strafe":
		return "acceleration, turn rate or movement not read"
	return ""


func test_every_movement_name_is_accepted() -> String:
	for name: String in RobotDef.MOVEMENTS:
		var robot: RobotDef = RobotDef.parse_json(GOOD.replace("\"hover\"", "\"%s\"" % name))
		if robot.error != "" or robot.movement != name:
			return "%s: \"%s\"" % [name, robot.error]
	return ""


func test_rejects_id() -> String:
	return _expect_error("id", GOOD.replace("\"drone\"", "\"Drone-1\""))


func test_rejects_empty_id() -> String:
	return _expect_error("id", GOOD.replace("\"drone\"", "\"\""))


func test_rejects_hull() -> String:
	return _expect_error("hull", GOOD.replace("\"hull\": 20.0", "\"hull\": 0.0"))


func test_rejects_radius() -> String:
	return _expect_error("radius", GOOD.replace("0.8", "50.0"))


func test_rejects_max_speed() -> String:
	return _expect_error("max_speed", GOOD.replace("8.0", "-1.0"))


func test_rejects_acceleration() -> String:
	return _expect_error("acceleration", GOOD.replace("16.0", "5000.0"))


func test_rejects_turn_rate() -> String:
	return _expect_error("turn_rate", GOOD.replace("120.0", "true"))


func test_rejects_unknown_movement() -> String:
	return _expect_error("movement", GOOD.replace("\"hover\"", "\"teleport\""))


func test_rejects_weapon() -> String:
	return _expect_error("weapon", GOOD.replace("\"weapon\": \"pulse_cannon\"", "\"weapon\": 3"))


func test_rejects_salvage() -> String:
	return _expect_error("salvage", GOOD.replace("\"salvage\": \"pulse_cannon\"", "\"salvage\": \"../ship\""))


func test_rejects_missing_unknown_and_broken() -> String:
	for key: String in RobotDef.KEYS:
		var data: Dictionary = JSON.parse_string(GOOD)
		data.erase(key)
		var missing: RobotDef = RobotDef.parse_json(JSON.stringify(data))
		if not missing.error.contains("missing key \"%s\"" % key):
			return "missing %s: \"%s\"" % [key, missing.error]
	var extra: RobotDef = RobotDef.parse_json(GOOD.replace("{", "{\"colour\": 1, "))
	if not extra.error.contains("colour"):
		return "unknown key: \"%s\"" % extra.error
	if RobotDef.parse_json("[1, 2]").error == "" or RobotDef.parse_json("{").error == "":
		return "non-object or broken JSON was accepted"
	return ""


## A rejected file leaves defaults, never a half-read robot.
func test_rejected_robot_has_defaults() -> String:
	var robot: RobotDef = RobotDef.parse_json(GOOD.replace("0.8", "50.0").replace("\"hull\": 20.0", "\"hull\": 99.0"))
	if robot.hull != RobotDef.new().hull:
		return "hull %f was kept from a rejected file" % robot.hull
	return ""


func test_hash_changes_with_every_value() -> String:
	var base: Dictionary = JSON.parse_string(GOOD)
	var base_hash: int = RobotDef.parse_json(GOOD).values_hash()
	if base_hash != RobotDef.parse_json(GOOD).values_hash():
		return "the same text gave two hashes"
	var changed: Dictionary = {
		"id": "drone_b", "hull": 21.0, "radius": 0.9, "max_speed": 9.0,
		"acceleration": 17.0, "turn_rate": 121.0, "movement": "chase",
		"weapon": "pulse_cannon_b", "salvage": "pulse_cannon_b",
	}
	for key: String in RobotDef.KEYS:
		if not changed.has(key):
			return "no changed value for %s" % key
		var data: Dictionary = base.duplicate()
		data[key] = changed[key]
		var robot: RobotDef = RobotDef.parse_json(JSON.stringify(data))
		if robot.error != "":
			return "%s: %s" % [key, robot.error]
		if robot.values_hash() == base_hash:
			return "changing %s left the hash unchanged" % key
	return ""


## The optional movement keys (#242): absent means today's constants.
func test_optional_keys_default_when_absent() -> String:
	var robot: RobotDef = RobotDef.parse_json(GOOD)
	if robot.error != "":
		return "rejected: %s" % robot.error
	if robot.standoff_radii != 4.0 or robot.strafe_min_distance != 10.0:
		return "stand-off %f, strafe min %f" % [robot.standoff_radii, robot.strafe_min_distance]
	if robot.strafe_max_distance != 20.0 or robot.strafe_radial_gain != 0.5:
		return "strafe max %f, gain %f" % [robot.strafe_max_distance, robot.strafe_radial_gain]
	return ""


## Every shipped robot file stays valid without the optional keys.
func test_shipped_robots_parse_with_defaults() -> String:
	var dir: String = "res://data/robots"
	var names: PackedStringArray = DirAccess.get_files_at(dir)
	var count: int = 0
	for name: String in names:
		if not name.ends_with(".json"):
			continue
		count += 1
		var robot: RobotDef = RobotDef.parse_json(FileAccess.get_file_as_string("%s/%s" % [dir, name]))
		if robot.error != "":
			return "%s rejected: %s" % [name, robot.error]
		var fresh: RobotDef = RobotDef.new()
		for key: String in RobotDef.OPTIONAL_KEYS:
			if robot.get(key) != fresh.get(key):
				return "%s: %s is %s, not the default" % [name, key, robot.get(key)]
	if count < 6:
		return "only %d robot files found" % count
	return ""


func test_optional_keys_are_read() -> String:
	var data: Dictionary = JSON.parse_string(GOOD)
	data["standoff_radii"] = 6.5
	data["strafe_min_distance"] = 7.0
	data["strafe_max_distance"] = 25.0
	data["strafe_radial_gain"] = 1.25
	var robot: RobotDef = RobotDef.parse_json(JSON.stringify(data))
	if robot.error != "":
		return "rejected: %s" % robot.error
	if robot.standoff_radii != 6.5 or robot.strafe_min_distance != 7.0:
		return "stand-off %f, strafe min %f" % [robot.standoff_radii, robot.strafe_min_distance]
	if robot.strafe_max_distance != 25.0 or robot.strafe_radial_gain != 1.25:
		return "strafe max %f, gain %f" % [robot.strafe_max_distance, robot.strafe_radial_gain]
	return ""


func test_optional_keys_reject_out_of_range_and_non_numbers() -> String:
	var bad: Dictionary = {
		"standoff_radii": [0.5, 51.0, "4"],
		"strafe_min_distance": [-1.0, 501.0, true],
		"strafe_max_distance": [-0.5, 600.0, null],
		"strafe_radial_gain": [-0.1, 10.5, [1]],
		"wake_range": [0.0, -2.0, 10000.5, "8"],
		"lose_target_seconds": [0.0, 60.5, "2"],
	}
	for key: String in RobotDef.OPTIONAL_KEYS:
		if not bad.has(key):
			return "no bad values for %s" % key
		for value: Variant in bad[key]:
			var data: Dictionary = JSON.parse_string(GOOD)
			data[key] = value
			if key == "strafe_min_distance":
				data["strafe_max_distance"] = 500.0
			var robot: RobotDef = RobotDef.parse_json(JSON.stringify(data))
			if robot.error == "" or not robot.error.contains("\"%s\"" % key):
				return "%s = %s: error was \"%s\"" % [key, str(value), robot.error]
			if typeof(value) != TYPE_FLOAT and not robot.error.contains("must be a number"):
				return "%s = %s: error was \"%s\"" % [key, str(value), robot.error]
	return ""


func test_rejects_strafe_min_above_max() -> String:
	var data: Dictionary = JSON.parse_string(GOOD)
	data["strafe_min_distance"] = 15.0
	data["strafe_max_distance"] = 12.0
	var robot: RobotDef = RobotDef.parse_json(JSON.stringify(data))
	if not robot.error.contains("strafe_min_distance") or not robot.error.contains("strafe_max_distance"):
		return "error was \"%s\"" % robot.error
	if robot.strafe_min_distance != RobotDef.new().strafe_min_distance:
		return "a rejected file kept strafe min %f" % robot.strafe_min_distance
	data["strafe_max_distance"] = 15.0
	if RobotDef.parse_json(JSON.stringify(data)).error != "":
		return "an empty band (min equal to max) was rejected"
	return ""


## A misspelt optional key is caught rather than silently defaulted.
func test_rejects_misspelt_optional_key() -> String:
	var robot: RobotDef = RobotDef.parse_json(GOOD.replace("{", "{\"standoff_radius\": 4.0, "))
	if not robot.error.contains("unknown key \"standoff_radius\""):
		return "error was \"%s\"" % robot.error
	return ""


func test_hash_changes_with_every_optional_value() -> String:
	var base_hash: int = RobotDef.parse_json(GOOD).values_hash()
	var changed: Dictionary = {
		"standoff_radii": 5.0, "strafe_min_distance": 11.0,
		"strafe_max_distance": 21.0, "strafe_radial_gain": 0.6, "wake_range": 8.0,
		"lose_target_seconds": 3.0,
	}
	for key: String in RobotDef.OPTIONAL_KEYS:
		var data: Dictionary = JSON.parse_string(GOOD)
		data[key] = changed[key]
		var robot: RobotDef = RobotDef.parse_json(JSON.stringify(data))
		if robot.error != "":
			return "%s: %s" % [key, robot.error]
		if robot.values_hash() == base_hash:
			return "changing %s left the hash unchanged" % key
	return ""


func _expect_error(field: String, text: String) -> String:
	var robot: RobotDef = RobotDef.parse_json(text)
	if robot.error == "" or not robot.error.contains(field):
		return "%s: error was \"%s\"" % [field, robot.error]
	return ""
