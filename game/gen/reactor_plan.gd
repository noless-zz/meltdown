class_name ReactorPlan
extends RefCounted

## The reactor a generated level gets (#356, RUN-2, ARC-4), read from
## `data/gen/reactor.json`:
##
##     {"radius": 2.5, "hull": 400, "meltdown_seconds": 90, "min_hops": 2}
##
## Everything but `min_hops` has the keys and checks of a level's `reactor`
## (optional countdown scaling keys included), and is parsed by `ReactorState`
## so there is one parser. The position is not in the file: the generator picks
## it. `exit_radius` is not either: a level sets that at its top level.
## `min_hops` is how many joins the reactor's module must at least be from the
## first module. The caller hands over the file's text, because `gen/` never
## opens files.

## Keys of a level's reactor the file must not hold.
const FORBIDDEN_KEYS: Array[String] = ["position", "exit_radius"]

## The reactor at the origin, full hull; `GeneratedLevel` copies and moves it.
var reactor: ReactorState = ReactorState.new()
## Fewest joins between the first module and the reactor's module.
var min_hops: int = 1
## Set by `parse_json` when the text was rejected; empty otherwise.
var error: String = ""


static func parse_json(text: String) -> ReactorPlan:
	var plan: ReactorPlan = ReactorPlan.new()
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		plan.error = "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return plan
	if typeof(json.data) != TYPE_DICTIONARY:
		plan.error = "top level must be a JSON object"
		return plan
	plan.error = plan._read(json.data)
	return plan


func _read(data: Dictionary) -> String:
	for key: String in FORBIDDEN_KEYS:
		if data.has(key):
			return "unknown key \"%s\"" % key
	if not data.has("min_hops"):
		return "missing key \"min_hops\""
	var hops: Variant = data["min_hops"]
	# JSON numbers arrive as floats; a whole number is all that is accepted.
	if typeof(hops) != TYPE_FLOAT and typeof(hops) != TYPE_INT \
			or not is_finite(float(hops)) or float(hops) != floorf(float(hops)) or float(hops) < 1.0:
		return "min_hops must be a whole number, at least 1"
	min_hops = int(hops)
	var rest: Dictionary = data.duplicate()
	rest.erase("min_hops")
	rest["position"] = [0, 0, 0]
	var read: ReactorState = ReactorState.parse(rest)
	if read.error != "":
		return read.error
	reactor = read
	return ""
