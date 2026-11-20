class_name FlightTestAnswers
extends RefCounted

## Which button gives which flight test answer (CMF-4, ARC-4), from
## `res://xr/flight_test/answers.json`, so the owner can move them without code:
##
##     {"fine": <button>, "uneasy": <button>, "stop": <button>}
##
## Every answer in `PresetRecommender.ANSWERS` needs one button from
## `ThumbstickMapping.BUTTONS`, and no two answers may share one. Physical
## buttons, not flight actions: they do not swap in left-handed mode, so A, B
## and Y stay where the panel's words put them.

const DEFAULT_FILE: String = "res://xr/flight_test/answers.json"
## Used when the file is missing or rejected: A fine, B uneasy, Y stop.
const DEFAULTS: Dictionary[String, String] = {
	PresetRecommender.FINE: "right_button_lower",
	PresetRecommender.UNEASY: "right_button_upper",
	PresetRecommender.STOP: "left_button_upper",
}

## Answer -> button name.
var buttons: Dictionary[String, String] = DEFAULTS.duplicate()
## Why the file was rejected, naming the field; empty when it was read.
var error: String = ""


## Reads `path`. A missing or rejected file keeps `DEFAULTS`, sets `error` and
## pushes a warning, so a broken file never stops the test from being answered.
static func load_file(path: String = DEFAULT_FILE) -> FlightTestAnswers:
	var answers: FlightTestAnswers = FlightTestAnswers.new()
	var problem: String = "file not found"
	if FileAccess.file_exists(path):
		problem = answers._parse(FileAccess.get_file_as_string(path))
	if problem != "":
		answers.buttons = DEFAULTS.duplicate()
		answers.error = "%s: %s" % [path, problem]
		push_warning("Meltdown: flight test answers use the defaults; %s" % answers.error)
	return answers


## The answer whose button is down in `buttons` and was not in `before`, or ""
## for none. When two go down on one frame the more cautious answer wins.
func pressed_answer(now: Dictionary, before: Dictionary) -> String:
	for answer: String in [PresetRecommender.STOP, PresetRecommender.UNEASY, PresetRecommender.FINE]:
		var button: String = buttons[answer]
		if bool(now.get(button, false)) and not bool(before.get(button, false)):
			return answer
	return ""


## True while any answer button is down in `now`.
func any_held(now: Dictionary) -> bool:
	for answer: String in buttons:
		if bool(now.get(buttons[answer], false)):
			return true
	return false


## Fills `buttons` from `text`; returns the problem, naming the field, or "".
func _parse(text: String) -> String:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
	if typeof(json.data) != TYPE_DICTIONARY:
		return "top level must be a JSON object"
	var data: Dictionary = json.data
	for key: Variant in data:
		if not PresetRecommender.ANSWERS.has(str(key)):
			return "unknown answer \"%s\", must be one of %s" % [str(key),
					", ".join(PackedStringArray(PresetRecommender.ANSWERS))]
	var read: Dictionary[String, String] = {}
	for answer: String in PresetRecommender.ANSWERS:
		if not data.has(answer):
			return "missing answer \"%s\"" % answer
		var value: Variant = data[answer]
		if typeof(value) != TYPE_STRING or not ThumbstickMapping.BUTTONS.has(value):
			return "\"%s\" is %s, must be one of %s" % [answer, JSON.stringify(value),
					", ".join(PackedStringArray(ThumbstickMapping.BUTTONS))]
		if read.values().has(value):
			return "\"%s\" uses %s, which another answer already uses" % [answer, value]
		read[answer] = value
	buttons = read
	return ""
