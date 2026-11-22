extends RefCounted

## Cockpit files may declare instruments that read `ShipGauges` (#1216,
## ARC-4): a valid list parses, every kind of bad entry is rejected naming the
## file and the field, and the shipped files declare none yet.

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


func test_shipped_cockpits_declare_no_instruments_yet() -> String:
	for file: String in DirAccess.get_files_at(DIR):
		if not file.ends_with(".json"):
			continue
		var spec: CockpitSpec = CockpitSpec.load_file(DIR + file)
		if spec.error != "":
			return spec.error
		if not spec.instruments.is_empty():
			return "%s declares %d instruments; none is drawn until M6" % [file, spec.instruments.size()]
	return ""
