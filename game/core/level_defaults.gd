class_name LevelDefaults
extends RefCounted

## Values a level file may leave out, read from `res://data/level_defaults.json`
## (ARC-4): content is data, so the default exit is changed there, not here.
##
##     {"exit_radius": 4.0}
##
## `exit_radius` is metres, held as whole millimetres like every other length in
## a level file (ARC-2). Core opens no files (ARC-1), so the file is read by the
## level loader (`LevelSwitch`) and handed to `LevelDef.parse_json`.

const KEYS: Array[String] = ["exit_radius"]
## Only for callers that hand in no defaults: tests that build a level from a
## string, and replay reactor lines written before the exit existed. The game
## itself always reads the data file; a level loaded from it never sees this.
const FALLBACK_EXIT_RADIUS_MM: int = 4000

## Radius of the exit sphere around the start (RUN-3) for a level without
## `exit_radius`.
var exit_radius_mm: int = FALLBACK_EXIT_RADIUS_MM
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of the defaults file: one JSON object holding every key in
## `KEYS` and nothing else. On failure `error` is set, naming the problem.
static func parse_json(text: String) -> LevelDefaults:
	var defaults: LevelDefaults = LevelDefaults.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		defaults.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return defaults
	if typeof(json.data) != TYPE_DICTIONARY:
		defaults.error = "top level must be a JSON object"
		return defaults
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			defaults.error = "unknown key \"%s\"" % str(key)
			return defaults
	for key: String in KEYS:
		if not data.has(key):
			defaults.error = "missing key \"%s\"" % key
			return defaults
	var read: Array[int] = []
	defaults.error = ReactorState.read_radius_mm(data["exit_radius"], "exit_radius", read)
	if defaults.error == "":
		defaults.exit_radius_mm = read[0]
	return defaults
