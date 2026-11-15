extends RefCounted

## Range checks on ship tuning read from a data file (ARC-4, FLT-1 to FLT-3):
## a file can never put the simulation into a nonsense state.

const DEFAULT_SHIP: String = "res://data/ships/default_ship.json"


func _default_data() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_SHIP)) as Dictionary


## A bound as a number; a String bound is resolved against `data`.
func _resolve(bound: Variant, data: Dictionary) -> float:
	if typeof(bound) == TYPE_STRING:
		return float(data[bound])
	return float(bound)


## Error of parsing the default data with `changes` applied.
func _error_with(changes: Dictionary) -> String:
	var data: Dictionary = _default_data()
	for key: Variant in changes:
		data[key] = changes[key]
	return ShipTuning.parse_json(JSON.stringify(data)).error


## Empty when `error` names `key` in quotes, otherwise a failure message.
func _names(error: String, key: String, what: String) -> String:
	if error.find("\"%s\"" % key) < 0:
		return "%s gave error \"%s\", which does not name %s" % [what, error, key]
	return ""


func test_every_key_has_a_range() -> String:
	for key: String in ShipTuning.KEYS:
		if not ShipTuning.RANGES.has(key):
			return "%s has no range" % key
		var range_pair: Array = ShipTuning.RANGES[key]
		if range_pair.size() != 2:
			return "%s range is not [minimum, maximum]" % key
		for bound: Variant in range_pair:
			if typeof(bound) == TYPE_STRING and not ShipTuning.KEYS.has(bound):
				return "%s bound names unknown key %s" % [key, bound]
	for key: Variant in ShipTuning.RANGES:
		if not ShipTuning.KEYS.has(key):
			return "range for unknown key %s" % key
	return ""


func test_defaults_lie_inside_their_ranges() -> String:
	var defaults: ShipTuning = ShipTuning.new()
	for key: String in ShipTuning.KEYS:
		var message: String = defaults._range_error(key)
		if message != "":
			return "default out of range: %s" % message
	return ""


func test_shipped_file_passes_the_range_checks() -> String:
	var tuning: ShipTuning = ShipTuning.parse_json(FileAccess.get_file_as_string(DEFAULT_SHIP))
	if tuning.error != "":
		return "default ship file rejected: %s" % tuning.error
	return ""


func test_value_below_each_minimum_is_rejected_by_name() -> String:
	for key: String in ShipTuning.KEYS:
		var low: float = _resolve(ShipTuning.RANGES[key][0], _default_data())
		var value: float = low - 0.05
		var failure: String = _names(_error_with({key: value}), key, "%s = %s" % [key, value])
		if failure != "":
			return failure
	return ""


func test_value_above_each_maximum_is_rejected_by_name() -> String:
	for key: String in ShipTuning.KEYS:
		var high: float = _resolve(ShipTuning.RANGES[key][1], _default_data())
		var value: float = high + 0.05
		var failure: String = _names(_error_with({key: value}), key, "%s = %s" % [key, value])
		if failure != "":
			return failure
	return ""


## Values exactly at each bound are accepted and kept. Where another key's
## bound depends on the one under test, that key is moved along with it.
func test_values_at_each_bound_are_accepted() -> String:
	for side: int in 2:
		for key: String in ShipTuning.KEYS:
			var data: Dictionary = _default_data()
			var value: float = _resolve(ShipTuning.RANGES[key][side], data)
			data[key] = value
			if key == "max_speed" and side == 1:
				data["afterburner_max_speed"] = value
			if key == "max_energy" and side == 0:
				data["afterburner_restart_energy"] = value
			var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
			if tuning.error != "":
				return "%s = %s at its bound rejected: %s" % [key, value, tuning.error]
			if tuning.get(key) != value:
				return "%s = %s at its bound read as %s" % [key, value, tuning.get(key)]
	return ""


func test_negative_speeds_are_rejected() -> String:
	for key: String in ["max_speed", "afterburner_max_speed", "wall_damage_min_speed"]:
		var failure: String = _names(_error_with({key: -5.0}), key, "%s = -5" % key)
		if failure != "":
			return failure
	return ""


func test_max_speed_above_afterburner_max_speed_is_rejected() -> String:
	var error: String = _error_with({"max_speed": 40.0, "afterburner_max_speed": 35.0})
	return _names(error, "afterburner_max_speed", "max_speed 40 with afterburner 35")


func test_restart_energy_above_max_energy_is_rejected() -> String:
	var error: String = _error_with({"max_energy": 50.0, "afterburner_restart_energy": 60.0})
	return _names(error, "afterburner_restart_energy", "restart 60 with pool 50")


func test_wall_restitution_outside_zero_to_one_is_rejected() -> String:
	for value: float in [-0.1, 1.5]:
		var failure: String = _names(_error_with({"wall_restitution": value}),
				"wall_restitution", "wall_restitution = %s" % value)
		if failure != "":
			return failure
	return ""


func test_radius_of_zero_or_less_is_rejected() -> String:
	for value: float in [0.0, -1.0]:
		var failure: String = _names(_error_with({"radius": value}), "radius", "radius = %s" % value)
		if failure != "":
			return failure
	return ""


func test_out_of_range_file_keeps_the_defaults() -> String:
	var data: Dictionary = _default_data()
	data["max_speed"] = 25.0
	data["wall_restitution"] = 2.0
	var tuning: ShipTuning = ShipTuning.parse_json(JSON.stringify(data))
	if tuning.error == "":
		return "wall_restitution 2 was accepted"
	var defaults: ShipTuning = ShipTuning.new()
	for key: String in ShipTuning.KEYS:
		if tuning.get(key) != defaults.get(key):
			return "a rejected file still set %s to %s" % [key, tuning.get(key)]
	return ""
