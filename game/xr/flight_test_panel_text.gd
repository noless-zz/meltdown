class_name FlightTestPanelText
extends RefCounted

## The words of the flight test panel (CMF-4, ARC-4), from
## `res://xr/flight_test/panel.json`, so the owner can reword them without code:
##
##     {"instructions": {<manoeuvre>: <text>, ...}, "question": <text>,
##      "answers": <text>, "time_left": <text with {seconds}>,
##      "result": <text with {preset}>, "change_hint": <text>, "raise_m": <number>,
##      "answer_line": <object>}
##
## `answers` is the plain answer line, shown when `answer_line` is missing or
## rejected. `answer_line` is passed through unchecked: whether it is good
## depends on the answers file too, so `FlightTestAnswerLine` checks it and a
## bad one costs only the button names, not the rest of the panel (#764).
## `instructions` needs one non-empty text for every manoeuvre in
## `FlightTestPlan.MANOEUVRES` and no other key. `raise_m` is how far above the
## status panel the flight test panel sits.

const DEFAULT_FILE: String = "res://xr/flight_test/panel.json"
const TEXT_KEYS: Array[String] = ["question", "answers", "time_left", "result", "change_hint"]
const KEYS: Array[String] = ["instructions", "question", "answers", "time_left", "result", "change_hint", "raise_m"]
## Keys the file may leave out.
const OPTIONAL_KEYS: Array[String] = ["answer_line"]
## Each placeholder a text must hold.
const PLACEHOLDERS: Dictionary[String, String] = {"time_left": "{seconds}", "result": "{preset}"}
const RAISE_RANGE: Array[float] = [0.0, 0.3]
## Used when the file is missing or rejected, so the test still reads.
const FALLBACK: Dictionary = {
	"instructions": {
		"snap_yaw": "Turn left and right with the stick",
		"snap_pitch": "Look up and down with the stick",
		"smooth_yaw": "Turn left and right with the stick",
		"smooth_pitch": "Pitch up and down with the stick",
		"manual_roll": "Roll both ways",
	},
	"question": "How did that feel?",
	"answers": "Fine     Uneasy     Stop",
	"time_left": "{seconds} s",
	"result": "Comfort preset: {preset}",
	"change_hint": "Change it any time with X",
	"raise_m": 0.12,
	"answer_line": {
		"template": "{button} {answer}",
		"separator": "     ",
		"words": {"fine": "Fine", "uneasy": "Uneasy", "stop": "Stop"},
		"buttons": {
			"left_button_lower": "X", "left_button_upper": "Y",
			"right_button_lower": "A", "right_button_upper": "B",
			"left_stick_click": "Left stick", "right_stick_click": "Right stick",
		},
	},
}


## The texts with `raise_m` as a float, or a dictionary holding only
## `"error"`, which names the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not (KEYS.has(key) or OPTIONAL_KEYS.has(key)):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var instructions: Variant = _instructions(data["instructions"])
	if typeof(instructions) == TYPE_STRING:
		return _rejected(instructions)
	var out: Dictionary = {"instructions": instructions}
	for key: String in TEXT_KEYS:
		var value: Variant = data[key]
		if typeof(value) != TYPE_STRING or (value as String).strip_edges() == "":
			return _rejected("\"%s\" must be a non-empty string" % key)
		if PLACEHOLDERS.has(key) and not (value as String).contains(PLACEHOLDERS[key]):
			return _rejected("\"%s\" must hold %s" % [key, PLACEHOLDERS[key]])
		out[key] = value
	var raise: Variant = data["raise_m"]
	# A bool must not pass as 0 or 1.
	if typeof(raise) != TYPE_FLOAT and typeof(raise) != TYPE_INT:
		return _rejected("\"raise_m\" must be a number")
	if float(raise) < RAISE_RANGE[0] or float(raise) > RAISE_RANGE[1]:
		return _rejected("\"raise_m\" is %s, must be within %s..%s" % [raise, RAISE_RANGE[0], RAISE_RANGE[1]])
	out["raise_m"] = float(raise)
	for key: String in OPTIONAL_KEYS:
		if data.has(key):
			out[key] = data[key]
	return out


## Reads the file at `path`. A missing or rejected file gives `FALLBACK` with
## `"error"` added, naming the field, so the caller can report it.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {"error": "file not found"}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	if values.has("error"):
		var fallback: Dictionary = FALLBACK.duplicate(true)
		fallback["error"] = "%s: %s" % [path, values["error"]]
		return fallback
	return values


## The instruction texts, or a String naming the bad field.
static func _instructions(value: Variant) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "\"instructions\" must be an object of manoeuvre to text"
	var given: Dictionary = value
	for key: Variant in given:
		if typeof(key) != TYPE_STRING or not FlightTestPlan.MANOEUVRES.has(key):
			return "\"instructions\" has unknown manoeuvre \"%s\", must be one of %s" % [str(key),
					", ".join(PackedStringArray(FlightTestPlan.MANOEUVRES))]
	var out: Dictionary = {}
	for manoeuvre: String in FlightTestPlan.MANOEUVRES:
		if not given.has(manoeuvre):
			return "\"instructions\" is missing manoeuvre \"%s\"" % manoeuvre
		if typeof(given[manoeuvre]) != TYPE_STRING or (given[manoeuvre] as String).strip_edges() == "":
			return "\"instructions.%s\" must be a non-empty string" % manoeuvre
		out[manoeuvre] = given[manoeuvre]
	return out


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
