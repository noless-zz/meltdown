extends RefCounted

## Ship tuning as a JSON data file (ARC-4, ARC-5) for the flight values of
## FLT-1 to FLT-3.

const DEFAULT_SHIP: String = "res://data/ships/default_ship.json"
const FORWARD: Vector3 = Vector3(0.0, 0.0, -1.0)


func _default_text() -> String:
	return FileAccess.get_file_as_string(DEFAULT_SHIP)


## The default data as a Dictionary, to build variants of it.
func _default_data() -> Dictionary:
	return JSON.parse_string(_default_text()) as Dictionary


## Flies ahead for `ticks` ticks, turning gently and boosting now and then.
func _fly(ship: ShipState, ticks: int) -> void:
	for i: int in ticks:
		ship.step(FORWARD, Vector3(0.1, 0.0, 0.0), i % 120 < 30)


func test_keys_match_the_typed_fields() -> String:
	var tuning: ShipTuning = ShipTuning.new()
	var ship: ShipState = ShipState.new()
	var fields: Array[String] = []
	for property: Dictionary in tuning.get_script().get_script_property_list():
		if property["type"] == TYPE_FLOAT:
			fields.append(property["name"])
	for key: String in ShipTuning.KEYS:
		if not fields.has(key):
			return "key %s is not a float field of ShipTuning" % key
		if typeof(ship.get(key)) != TYPE_FLOAT:
			return "key %s is not a float field of ShipState" % key
	for field: String in fields:
		if not ShipTuning.KEYS.has(field):
			return "field %s is missing from ShipTuning.KEYS" % field
	return ""


func test_defaults_equal_ship_state_defaults() -> String:
	var tuning: ShipTuning = ShipTuning.new()
	var ship: ShipState = ShipState.new()
	for key: String in ShipTuning.KEYS:
		if tuning.get(key) != ship.get(key):
			return "%s: tuning %s, ship %s" % [key, tuning.get(key), ship.get(key)]
	return ""


func test_data_file_parses_and_matches_the_defaults() -> String:
	if not FileAccess.file_exists(DEFAULT_SHIP):
		return "%s is missing" % DEFAULT_SHIP
	var tuning: ShipTuning = ShipTuning.parse_json(_default_text())
	if tuning.error != "":
		return "default file rejected: %s" % tuning.error
	var defaults: ShipTuning = ShipTuning.new()
	for key: String in ShipTuning.KEYS:
		if tuning.get(key) != defaults.get(key):
			return "%s: file %s, default %s" % [key, tuning.get(key), defaults.get(key)]
	return ""


func test_default_tuning_leaves_flight_unchanged() -> String:
	var plain: ShipState = ShipState.new()
	var tuned: ShipState = ShipState.new()
	ShipTuning.parse_json(_default_text()).apply_to(tuned)
	_fly(plain, 600)
	_fly(tuned, 600)
	if plain.state_hash() != tuned.state_hash():
		return "default tuning changed the flight"
	return ""


func test_invalid_json_is_rejected() -> String:
	for text: String in ["", "{", "{\"max_speed\": }", "not json"]:
		if ShipTuning.parse_json(text).error == "":
			return "accepted %s" % JSON.stringify(text)
	return ""


func test_non_object_is_rejected() -> String:
	for text: String in ["[]", "20", "\"ship\"", "null"]:
		if ShipTuning.parse_json(text).error == "":
			return "accepted %s" % text
	return ""


func test_missing_key_is_rejected() -> String:
	for key: String in ShipTuning.KEYS:
		var data: Dictionary = _default_data()
		data.erase(key)
		var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
		if tuning.error.find(key) < 0:
			return "missing %s gave error \"%s\"" % [key, tuning.error]
	return ""


func test_unknown_key_is_rejected() -> String:
	var data: Dictionary = _default_data()
	data["max_sped"] = 30.0
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error.find("max_sped") < 0:
		return "unknown key gave error \"%s\"" % tuning.error
	return ""


func test_wrong_type_is_rejected() -> String:
	for value: Variant in ["20", true, null, [20.0], {"value": 20.0}]:
		var data: Dictionary = _default_data()
		data["max_speed"] = value
		var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
		if tuning.error.find("max_speed") < 0:
			return "max_speed = %s gave error \"%s\"" % [JSON.stringify(value), tuning.error]
	return ""


func test_rejected_text_leaves_default_values() -> String:
	var data: Dictionary = _default_data()
	data["max_speed"] = 50.0
	data["radius"] = "big"
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error == "":
		return "bad radius was accepted"
	if tuning.max_speed != ShipTuning.new().max_speed:
		return "a rejected file still set max_speed to %f" % tuning.max_speed
	return ""


func test_other_max_speed_changes_the_speed_reached() -> String:
	var data: Dictionary = _default_data()
	data["max_speed"] = 10.0
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error != "":
		return "variant rejected: %s" % tuning.error
	var plain: ShipState = ShipState.new()
	var slow: ShipState = ShipState.new()
	tuning.apply_to(slow)
	for i: int in 300:
		plain.step(FORWARD, Vector3.ZERO)
		slow.step(FORWARD, Vector3.ZERO)
	var plain_speed: float = plain.velocity.length()
	var slow_speed: float = slow.velocity.length()
	if absf(slow_speed - 10.0) > 0.01:
		return "tuned ship reached %f m/s, expected 10" % slow_speed
	if plain_speed <= slow_speed + 1.0:
		return "default ship reached %f m/s, not above the tuned %f" % [plain_speed, slow_speed]
	return ""


func test_apply_fills_energy_and_hull_to_new_maxima() -> String:
	var data: Dictionary = _default_data()
	data["max_energy"] = 60.0
	data["max_hull"] = 150.0
	var ship: ShipState = ShipState.new()
	ship.energy = 3.0
	ship.hull = 40.0
	ship.afterburner_locked = true
	ShipTuning.parse_json(JSON.stringify(data)).apply_to(ship)
	if ship.energy != 60.0 or ship.hull != 150.0 or ship.afterburner_locked:
		return "energy %f, hull %f, locked %s" % [ship.energy, ship.hull, ship.afterburner_locked]
	return ""


func test_same_text_twice_gives_identical_hashes() -> String:
	var data: Dictionary = _default_data()
	data["max_speed"] = 27.5
	data["damping"] = 1.25
	data["afterburner_drain"] = 40.0
	var text: String = JSON.stringify(data)
	var hashes: Array[int] = []
	for run: int in 2:
		var sim: Sim = Sim.new(7, 1, BoxBounds.new(Vector3(-15, -15, -200), Vector3(15, 15, 15)))
		ShipTuning.parse_json(text).apply_to(sim.ships[0])
		var input: ShipInput = ShipInput.from_floats(FORWARD, Vector3(0.3, 0.2, 0.0), true)
		for i: int in 900:
			sim.step([input] as Array[ShipInput])
		hashes.append(sim.state_hash())
	if hashes[0] != hashes[1]:
		return "hashes differ: %d and %d" % hashes
	return ""
