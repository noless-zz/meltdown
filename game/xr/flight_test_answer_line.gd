class_name FlightTestAnswerLine
extends RefCounted

## Builds the flight test panel's answer line (#764, CMF-4, ARC-4) from the
## `answer_line` object of `res://xr/flight_test/panel.json` and the buttons in
## `res://xr/flight_test/answers.json`, so the line names the button that gives
## each answer and a remapped answers file changes the panel too:
##
##     {"template": "{button} {answer}", "separator": "     ",
##      "words": {"fine": <text>, "uneasy": <text>, "stop": <text>},
##      "buttons": {<button from ThumbstickMapping.BUTTONS>: <name>, ...}}
##
## The button names are the letters printed on the Quest 3 Touch controllers,
## not flight actions, because `FlightTestAnswers` reads physical buttons that
## do not swap in left-handed mode. Answers are listed in
## `PresetRecommender.ANSWERS` order.

const TEMPLATE_HOLDS: Array[String] = ["{button}", "{answer}"]
const KEYS: Array[String] = ["template", "separator", "words", "buttons"]


## `{"line": <text>}`, or `{"error": <text naming the field>}`. `spec` is the
## parsed `answer_line` object; `buttons` maps answer -> button name.
static func build(spec: Variant, buttons: Dictionary[String, String]) -> Dictionary:
	if typeof(spec) != TYPE_DICTIONARY:
		return _rejected("\"answer_line\" must be an object")
	var given: Dictionary = spec
	for key: Variant in given:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("\"answer_line\" has unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not given.has(key):
			return _rejected("\"answer_line\" is missing \"%s\"" % key)
	var template: Variant = given["template"]
	if typeof(template) != TYPE_STRING:
		return _rejected("\"answer_line.template\" must be a string")
	for placeholder: String in TEMPLATE_HOLDS:
		if not (template as String).contains(placeholder):
			return _rejected("\"answer_line.template\" must hold %s" % placeholder)
	var separator: Variant = given["separator"]
	if typeof(separator) != TYPE_STRING or (separator as String) == "":
		return _rejected("\"answer_line.separator\" must be a non-empty string")
	if typeof(given["words"]) != TYPE_DICTIONARY:
		return _rejected("\"answer_line.words\" must be an object of answer to text")
	if typeof(given["buttons"]) != TYPE_DICTIONARY:
		return _rejected("\"answer_line.buttons\" must be an object of button to name")
	var words: Dictionary = given["words"]
	var names: Dictionary = given["buttons"]
	var parts: PackedStringArray = []
	for answer: String in PresetRecommender.ANSWERS:
		var word: Variant = words.get(answer)
		if typeof(word) != TYPE_STRING or (word as String).strip_edges() == "":
			return _rejected("\"answer_line.words.%s\" must be a non-empty string" % answer)
		var button: String = buttons.get(answer, "")
		var button_name: Variant = names.get(button)
		if typeof(button_name) != TYPE_STRING or (button_name as String).strip_edges() == "":
			return _rejected("\"answer_line.buttons.%s\" must name the button for %s" % [button, answer])
		parts.append((template as String).replace("{button}", button_name).replace("{answer}", word))
	return {"line": (separator as String).join(parts)}


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
