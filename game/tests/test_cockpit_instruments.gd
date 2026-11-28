extends RefCounted

## Cockpit files may declare instruments that read `ShipGauges` (#1216,
## ARC-4): a valid list parses, every kind of bad entry is rejected naming the
## file and the field, and since #1461 every shipped file declares hull,
## shield and energy with their looks.

const DIR: String = "res://xr/cockpits/"
const ENTRY: String = '{"id": "hull_dial", "gauge": "hull", "yaw_deg": -20, "pitch_deg": -30}'


## A shipped cockpit file's text with its `instruments` replaced by `list`.
static func _with(list: String) -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "guided.json"))
	data.erase(CockpitInstrument.LIST_KEY)
	var text: String = JSON.stringify(data)
	return text.substr(0, text.length() - 1) + ', "%s": %s}' % [CockpitInstrument.LIST_KEY, list]


func test_a_valid_list_parses_every_gauge() -> String:
	var entries: PackedStringArray = []
	for gauge: String in ShipGauges.NAMES:
		entries.append('{"id": "%s_gauge", "gauge": "%s", "yaw_deg": 10.5, "pitch_deg": -25}' % [gauge, gauge])
	var spec: CockpitSpec = CockpitSpec.parse_json(_with("[%s]" % ", ".join(entries)))
	if spec.error != "":
		return "a valid list was rejected: %s" % spec.error
	if spec.instruments.size() != ShipGauges.NAMES.size():
		return "%d instruments parsed" % spec.instruments.size()
	var first: CockpitInstrument = spec.instruments[0]
	if first.id != "hull_gauge" or first.gauge != ShipGauges.HULL \
			or not is_equal_approx(first.yaw_deg, 10.5) or not is_equal_approx(first.pitch_deg, -25.0):
		return "the first instrument reads %s %s %s %s" % [first.id, first.gauge, first.yaw_deg, first.pitch_deg]
	return ""


func test_no_list_and_an_empty_list_both_give_no_instruments() -> String:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIR + "guided.json"))
	data.erase(CockpitInstrument.LIST_KEY)
	var without: CockpitSpec = CockpitSpec.parse_json(JSON.stringify(data))
	var empty: CockpitSpec = CockpitSpec.parse_json(_with("[]"))
	if without.error != "" or empty.error != "":
		return "rejected: %s / %s" % [without.error, empty.error]
	if not without.instruments.is_empty() or not empty.instruments.is_empty():
		return "instruments appeared from nothing"
	return ""


func test_each_kind_of_bad_list_is_rejected_naming_the_field() -> String:
	var bad: Dictionary = {
		'{"id": "x"}': "must be a list",
		'[3]': "instruments[0] must be an object",
		'[{"id": "a", "gauge": "speed", "yaw_deg": 0, "pitch_deg": 0}]': "instruments[0].gauge",
		'[{"gauge": "hull", "yaw_deg": 0, "pitch_deg": 0}]': "instruments[0].id is missing",
		'[{"id": "a", "yaw_deg": 0, "pitch_deg": 0}]': "instruments[0].gauge is missing",
		'[{"id": "a", "gauge": "hull", "pitch_deg": 0}]': "instruments[0].yaw_deg is missing",
		'[{"id": "a", "gauge": "hull", "yaw_deg": 0}]': "instruments[0].pitch_deg is missing",
		'[{"id": "", "gauge": "hull", "yaw_deg": 0, "pitch_deg": 0}]': "instruments[0].id",
		'[{"id": "a", "gauge": "hull", "yaw_deg": true, "pitch_deg": 0}]': "instruments[0].yaw_deg",
		'[{"id": "a", "gauge": "hull", "yaw_deg": 0, "pitch_deg": 95}]': "instruments[0].pitch_deg",
		'[{"id": "a", "gauge": "hull", "yaw_deg": 0, "pitch_deg": 0, "size": 2}]': "unknown key \"size\"",
		'[%s, %s]' % [ENTRY, ENTRY]: "instruments[1].id \"hull_dial\" is used twice",
	}
	for list: String in bad:
		var spec: CockpitSpec = CockpitSpec.parse_json(_with(list))
		if not spec.error.contains(bad[list]):
			return "%s gives '%s', not an error naming %s" % [list, spec.error, bad[list]]
	return ""


func test_a_rejected_file_names_the_file() -> String:
	var path: String = "user://test_cockpit_instruments_bad.json"
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(_with('[{"id": "a", "gauge": "fuel", "yaw_deg": 0, "pitch_deg": 0}]'))
	file.close()
	var spec: CockpitSpec = CockpitSpec.load_file(path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if not spec.error.begins_with(path) or not spec.error.contains("instruments[0].gauge"):
		return "the error reads '%s'" % spec.error
	return ""


func test_each_bad_look_key_is_rejected_naming_the_field() -> String:
	var start: String = '{"id": "a", "gauge": "hull", "yaw_deg": 0, "pitch_deg": -34, '
	var bad: Dictionary = {
		'"distance_m": 0.2}': "instruments[0].distance_m is 0.2",
		'"distance_m": "near"}': "instruments[0].distance_m must be a number",
		'"size_m": [0.05]}': "instruments[0].size_m must be an array of two numbers",
		'"size_m": [0.05, 0.5]}': "instruments[0].size_m has 0.5",
		'"label": 7}': "instruments[0].label must be a text",
		'"label": "HULL INTEGRITY NOW"}': "instruments[0].label must be a text of at most",
		'"color": [1, 0]}': "instruments[0].color must be an array of three numbers",
		'"low_color": [1, 2, 0]}': "instruments[0].low_color has 2",
		'"low_below": 1.5}': "instruments[0].low_below is 1.5",
		'"low_pulse_s": 0.5}': "instruments[0].low_pulse_s is 0.5",
		'"low_pulse_min": 0.2}': "instruments[0].low_pulse_min is 0.2",
		'"low_pulse_min": false}': "instruments[0].low_pulse_min must be a number",
	}
	for tail: String in bad:
		var spec: CockpitSpec = CockpitSpec.parse_json(_with("[%s%s]" % [start, tail]))
		if not spec.error.contains(bad[tail]):
			return "%s gives '%s', not an error naming %s" % [tail, spec.error, bad[tail]]
	return ""


func test_an_instrument_behind_the_shell_is_rejected() -> String:
	# guided.json's shell is 0.55 m from the eye.
	var spec: CockpitSpec = CockpitSpec.parse_json(_with(
		'[{"id": "a", "gauge": "hull", "yaw_deg": 0, "pitch_deg": -34, "distance_m": 0.6}]'))
	if not spec.error.contains("instruments[0].distance_m is 0.6, not nearer than frame_distance_m"):
		return "the error reads '%s'" % spec.error
	return ""


func test_the_look_keys_parse_with_defaults_for_the_rest() -> String:
	var spec: CockpitSpec = CockpitSpec.parse_json(_with('[%s, %s]' % [ENTRY,
		'{"id": "e", "gauge": "energy", "yaw_deg": 20, "pitch_deg": -30, "distance_m": 0.4, "size_m": [0.07, 0.03], "label": "ENERGY", "color": [0, 1, 0], "low_color": [1, 0, 0], "low_below": 0.2, "low_pulse_s": 2, "low_pulse_min": 0.8}']))
	if spec.error != "":
		return spec.error
	var plain: CockpitInstrument = spec.instruments[0]
	var full: CockpitInstrument = spec.instruments[1]
	var defaults: CockpitInstrument = CockpitInstrument.new()
	if plain.distance_m != defaults.distance_m or plain.size_m != defaults.size_m or plain.label != "" \
			or plain.low_below != defaults.low_below or plain.color != defaults.color:
		return "an entry without look keys did not take the defaults"
	if not is_equal_approx(full.distance_m, 0.4) or not full.size_m.is_equal_approx(Vector2(0.07, 0.03)) \
			or full.label != "ENERGY" or full.color != Color(0, 1, 0) or full.low_color != Color(1, 0, 0) \
			or not is_equal_approx(full.low_below, 0.2) or not is_equal_approx(full.low_pulse_s, 2.0) \
			or not is_equal_approx(full.low_pulse_min, 0.8):
		return "the look keys read %s %s %s" % [full.distance_m, full.size_m, full.label]
	return ""


func test_shipped_cockpits_declare_hull_shield_and_energy() -> String:
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var spec: CockpitSpec = CockpitSpec.load_file(DIR + file)
		if spec.error != "":
			return spec.error
		var gauges: PackedStringArray = []
		for instrument: CockpitInstrument in spec.instruments:
			gauges.append(instrument.gauge)
		if ", ".join(gauges) != "hull, shield, energy":
			return "%s declares instruments for %s" % [file, gauges]
	return ""
