class_name ComponentDef
extends RefCounted

## One component kind: a resource that destroyed robots drop and the player
## collects by flying through it, later spent on crafting (CRF-1, decision
## record 0008). Kinds are data so a new one is a file, not code (ARC-4).
## Parsed like `RobotDef`: the caller reads the file and hands its text over,
## because core never opens files; `ComponentList` adds the file name to errors.

## Name of the kind; matches the data file's name without `.json`. Lower case
## letters, digits and underscores, 1..64 characters.
var id: String = ""
## Name shown to the player, 1..64 characters.
var display_name: String = ""
## Depth band of the kind, 1..3: higher tiers come from deeper levels and
## riskier shafts (CRF-7).
var tier: int = 1
## Colour of the kind on the map and pickup, "#rrggbb". Kept as text because
## core never touches rendering; the view converts it.
var map_colour: String = "#ffffff"

## Every key of the data file; all are required and no others are allowed.
const KEYS: Array[String] = ["id", "display_name", "tier", "map_colour"]
const TIER_MIN: int = 1
const TIER_MAX: int = 3
const ID_MAX_LENGTH: int = 64
const NAME_MAX_LENGTH: int = 64

## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


## Parses the text of a component data file. A missing or unknown key is an
## error naming the key, so a typo cannot leave a kind half described. On
## failure the returned kind has `error` set and default values.
static func parse_json(text: String) -> ComponentDef:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _failed("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _failed("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _failed("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _failed("missing key \"%s\"" % key)
	var message: String = check_id("id", data["id"])
	if message == "":
		message = _check_name(data["display_name"])
	if message == "":
		message = _check_tier(data["tier"])
	if message == "":
		message = _check_colour(data["map_colour"])
	if message != "":
		return _failed(message)
	var kind: ComponentDef = ComponentDef.new()
	kind.id = data["id"]
	kind.display_name = data["display_name"]
	kind.tier = int(data["tier"])
	kind.map_colour = data["map_colour"]
	return kind


## Checks an id string the way every component reference must be written.
## Returns "" or the problem, naming `key`. Shared with `ComponentDrop`.
static func check_id(key: String, value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"%s\" must be a string" % key
	var text: String = value
	if text.is_empty() or text.length() > ID_MAX_LENGTH:
		return "key \"%s\" must be 1 to %d characters" % [key, ID_MAX_LENGTH]
	for i: int in text.length():
		var c: int = text.unicode_at(i)
		var ok: bool = (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95
		if not ok:
			return "key \"%s\" is \"%s\", must use only a-z, 0-9 and _" % [key, text]
	return ""


static func _check_name(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"display_name\" must be a string"
	var text: String = value
	if text.strip_edges().is_empty() or text.length() > NAME_MAX_LENGTH:
		return "key \"display_name\" must be 1 to %d characters" % NAME_MAX_LENGTH
	return ""


static func _check_tier(value: Variant) -> String:
	# JSON numbers arrive as floats. A bool must not pass as 0 or 1.
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return "key \"tier\" must be a number"
	var number: float = float(value)
	if number != floorf(number):
		return "key \"tier\" is %s, must be a whole number" % number
	if number < TIER_MIN or number > TIER_MAX:
		return "key \"tier\" is %s, must be %d to %d" % [number, TIER_MIN, TIER_MAX]
	return ""


static func _check_colour(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return "key \"map_colour\" must be a string"
	var text: String = value
	var ok: bool = text.length() == 7 and text.begins_with("#")
	for i: int in range(1, text.length()):
		var c: int = text.unicode_at(i)
		if not ((c >= 48 and c <= 57) or (c >= 97 and c <= 102)):
			ok = false
	if not ok:
		return "key \"map_colour\" is \"%s\", must be \"#rrggbb\" in lower case hex" % text
	return ""


static func _failed(message: String) -> ComponentDef:
	var kind: ComponentDef = ComponentDef.new()
	kind.error = message
	return kind
