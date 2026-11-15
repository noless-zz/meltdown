class_name FlightTestPlan
extends RefCounted

## The first-launch flight test as data (CMF-4, ARC-4): an ordered list of
## segments from the most to the least comfort intervention. After each one
## the player says how it felt, and `PresetRecommender` turns the answers into
## a preset. Segment lengths are guesses for the owner to tune in
## `res://xr/flight_test/plan.json`; the rules below keep any tuning valid.

const DEFAULT_FILE: String = "res://xr/flight_test/plan.json"
## CMF-4 promises a two-minute test.
const MAX_TOTAL_S: float = 120.0
## Longest single segment, seconds. Long enough for any manoeuvre, short
## enough that one typo cannot eat the whole test.
const MAX_SEGMENT_S: float = 60.0
const MIN_PRESET: int = 1
const MAX_PRESET: int = 4

## Manoeuvres the flying code knows. The preset of the segment decides whether
## a smooth turn is capped (2) or full (3 and 4).
const MANOEUVRES: Array[String] = [
	"snap_yaw", "snap_pitch", "smooth_yaw", "smooth_pitch", "manual_roll",
]
## Every key of one segment object.
const SEGMENT_KEYS: Array[String] = ["id", "preset", "duration_s", "manoeuvre"]

## Set when the text was rejected; empty otherwise.
var error: String = ""
## The segments in the order they are flown. Empty when rejected.
var segments: Array[FlightTestSegment] = []


## Parses the text of a plan file: one JSON object with a single key
## `segments`, a non-empty array of segment objects. On failure the returned
## plan has `error` set, naming the segment and field, and no segments.
static func parse_json(text: String) -> FlightTestPlan:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if key != "segments":
			return _rejected("unknown key \"%s\"" % str(key))
	if not data.has("segments"):
		return _rejected("missing key \"segments\"")
	if typeof(data["segments"]) != TYPE_ARRAY or (data["segments"] as Array).is_empty():
		return _rejected("\"segments\" must be a non-empty array")
	var plan: FlightTestPlan = FlightTestPlan.new()
	var ids: Array[String] = []
	var total_s: float = 0.0
	var previous_preset: int = MIN_PRESET
	var index: int = 0
	for entry: Variant in data["segments"]:
		var segment_error: String = _check_segment(entry)
		if segment_error != "":
			return _rejected("segment %d: %s" % [index, segment_error])
		var raw: Dictionary = entry
		var segment: FlightTestSegment = FlightTestSegment.new(
			raw["id"], int(raw["preset"]), float(raw["duration_s"]), raw["manoeuvre"])
		if ids.has(segment.id):
			return _rejected("segment %d: \"id\" \"%s\" is used twice" % [index, segment.id])
		# The recommendation reads "the last fine segment", which only means
		# "the most motion tolerated" while the presets never go back down.
		if segment.preset < previous_preset:
			return _rejected("segment %d: \"preset\" %d is below the previous segment's %d" % [index, segment.preset, previous_preset])
		ids.append(segment.id)
		previous_preset = segment.preset
		total_s += segment.duration_s
		plan.segments.append(segment)
		index += 1
	if total_s > MAX_TOTAL_S:
		return _rejected("segments last %s s in total, must be at most %s s" % [total_s, MAX_TOTAL_S])
	return plan


## Reads and parses the file at `path`. A missing file is rejected like bad text.
static func load_file(path: String = DEFAULT_FILE) -> FlightTestPlan:
	if not FileAccess.file_exists(path):
		return _rejected("file %s not found" % path)
	var plan: FlightTestPlan = parse_json(FileAccess.get_file_as_string(path))
	if plan.error != "":
		plan.error = "%s: %s" % [path, plan.error]
	return plan


## Total flying time of the plan, seconds.
func total_duration_s() -> float:
	var total: float = 0.0
	for segment: FlightTestSegment in segments:
		total += segment.duration_s
	return total


## Empty when `entry` is a valid segment object; otherwise names the field.
static func _check_segment(entry: Variant) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "must be a JSON object"
	var raw: Dictionary = entry
	for key: Variant in raw:
		if typeof(key) != TYPE_STRING or not SEGMENT_KEYS.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in SEGMENT_KEYS:
		if not raw.has(key):
			return "missing key \"%s\"" % key
	if typeof(raw["id"]) != TYPE_STRING or (raw["id"] as String).strip_edges() == "":
		return "\"id\" must be a non-empty string"
	var preset: Variant = raw["preset"]
	# JSON numbers arrive as floats; a bool must not pass as 0 or 1.
	if typeof(preset) != TYPE_FLOAT and typeof(preset) != TYPE_INT:
		return "\"preset\" must be a number"
	if float(preset) != floorf(float(preset)) or float(preset) < MIN_PRESET or float(preset) > MAX_PRESET:
		return "\"preset\" is %s, must be a whole number within %d..%d" % [preset, MIN_PRESET, MAX_PRESET]
	var seconds: Variant = raw["duration_s"]
	if typeof(seconds) != TYPE_FLOAT and typeof(seconds) != TYPE_INT:
		return "\"duration_s\" must be a number"
	if not float(seconds) > 0.0 or float(seconds) > MAX_SEGMENT_S:
		return "\"duration_s\" is %s, must be above 0 and at most %s" % [seconds, MAX_SEGMENT_S]
	if typeof(raw["manoeuvre"]) != TYPE_STRING or not MANOEUVRES.has(raw["manoeuvre"]):
		return "\"manoeuvre\" is \"%s\", must be one of %s" % [str(raw["manoeuvre"]), ", ".join(PackedStringArray(MANOEUVRES))]
	return ""


static func _rejected(message: String) -> FlightTestPlan:
	var plan: FlightTestPlan = FlightTestPlan.new()
	plan.error = message
	return plan
