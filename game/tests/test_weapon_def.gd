extends RefCounted

## Weapons as data files (CMB-1, ARC-4, #94).

const PULSE_CANNON: String = "res://data/weapons/pulse_cannon.json"
const GOOD: String = "{\"fire_interval_ticks\": 10, \"projectile_speed\": 120.0, \"lifetime\": 1.5, \"damage\": 8.0, \"energy_cost\": 2.0}"


func test_pulse_cannon_file_parses() -> String:
	if not FileAccess.file_exists(PULSE_CANNON):
		return "missing %s" % PULSE_CANNON
	var weapon: WeaponDef = WeaponDef.parse_json(FileAccess.get_file_as_string(PULSE_CANNON))
	if weapon.error != "":
		return "pulse_cannon.json rejected: %s" % weapon.error
	if weapon.fire_interval_ticks < 1 or weapon.projectile_speed <= 0.0 or weapon.lifetime <= 0.0:
		return "pulse_cannon.json parsed to nonsense values"
	return ""


func test_good_text_sets_every_field() -> String:
	var weapon: WeaponDef = WeaponDef.parse_json(GOOD.replace("120.0", "95.5").replace(": 10,", ": 7,"))
	if weapon.error != "":
		return "rejected: %s" % weapon.error
	if weapon.fire_interval_ticks != 7 or weapon.projectile_speed != 95.5:
		return "interval %d, speed %f" % [weapon.fire_interval_ticks, weapon.projectile_speed]
	if weapon.lifetime != 1.5 or weapon.damage != 8.0 or weapon.energy_cost != 2.0:
		return "lifetime, damage or energy cost not read"
	return ""


## Each bad file is rejected with a message naming the field at fault.
func test_bad_files_are_rejected_naming_the_field() -> String:
	var cases: Dictionary[String, String] = {
		"fire_interval_ticks": GOOD.replace(": 10,", ": 0,"),
		"projectile_speed": GOOD.replace("120.0", "5000.0"),
		"lifetime": GOOD.replace("1.5", "0.0"),
		"damage": GOOD.replace("8.0", "-1.0"),
		"energy_cost": GOOD.replace("2.0}", "true}"),
	}
	for field: String in cases:
		var weapon: WeaponDef = WeaponDef.parse_json(cases[field])
		if weapon.error == "" or not weapon.error.contains(field):
			return "%s: error was \"%s\"" % [field, weapon.error]
	var fractional: WeaponDef = WeaponDef.parse_json(GOOD.replace(": 10,", ": 2.5,"))
	if not fractional.error.contains("whole number"):
		return "a fractional interval was accepted: \"%s\"" % fractional.error
	var missing: WeaponDef = WeaponDef.parse_json("{\"fire_interval_ticks\": 10}")
	if not missing.error.contains("missing key"):
		return "missing keys: \"%s\"" % missing.error
	var extra: WeaponDef = WeaponDef.parse_json(GOOD.replace("{", "{\"colour\": 1, "))
	if not extra.error.contains("colour"):
		return "unknown key: \"%s\"" % extra.error
	if WeaponDef.parse_json("[1, 2]").error == "" or WeaponDef.parse_json("{").error == "":
		return "non-object or broken JSON was accepted"
	return ""


func test_lifetime_ticks_round_to_the_tick() -> String:
	var weapon: WeaponDef = WeaponDef.new()
	weapon.lifetime = 1.5
	if weapon.lifetime_ticks() != 90:
		return "1.5 s gave %d ticks" % weapon.lifetime_ticks()
	weapon.lifetime = 0.001
	if weapon.lifetime_ticks() != 1:
		return "a tiny lifetime gave %d ticks" % weapon.lifetime_ticks()
	return ""
