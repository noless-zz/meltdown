class_name ShaftPanelLook
extends RefCounted

## Parses `res://xr/shaft_panel.json`, the words, thresholds, colours and
## placement of the shaft panel shown between a run's levels (#990, RUN-1,
## CRF-7, ARC-4):
##
##     {"title_text": "...", "prompt_xr": "...", "prompt_flat": "...",
##      "mark_text": "...", "detail_text": "... {robots} ... {alarm} ... {reward} ...",
##      "rewards": [{"tier": 1..3, "min_share": 0..1, "text": "..."}, ...],
##      "title_color": [r, g, b], "text_color": [r, g, b], "highlight_color": [r, g, b],
##      "title_position_m": [x, y, z], "entry_step_m": 0.05..0.3,
##      "title_font_size": 16..256, "label_font_size": 16..256,
##      "detail_font_size": 16..256, "pixel_size": 0.0001..0.002}
##
## A shaft's risk reads as its multipliers with one decimal, `{robots}` and
## `{alarm}`. Its reward reads as the text of the first `rewards` entry whose
## tier holds at least `min_share` of the shaft's three tier weights, so the
## thresholds are data too. The last entry must have `min_share` 0, so every
## shaft gets a reward text. `mark_text` goes before the highlighted shaft.
## The title sits at `title_position_m` (from the eye point, forward as -z);
## each shaft and then the prompt sit `entry_step_m` lower than the line above.

const DEFAULT_FILE: String = "res://xr/shaft_panel.json"
const TEXT_KEYS: Array[String] = ["title_text", "prompt_xr", "prompt_flat", "mark_text", "detail_text"]
const COLOR_KEYS: Array[String] = ["title_color", "text_color", "highlight_color"]
const MARKS: Array[String] = ["{robots}", "{alarm}", "{reward}"]
const RANGES: Dictionary[String, Array] = {
	"entry_step_m": [0.05, 0.3],
	"title_font_size": [16.0, 256.0],
	"label_font_size": [16.0, 256.0],
	"detail_font_size": [16.0, 256.0],
	"pixel_size": [0.0001, 0.002],
}
const SIDE_LIMIT_M: float = 0.5
const NEAR_M: float = 0.5
const FAR_M: float = 3.0

## Used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"title_text": "CHOOSE A SHAFT",
	"prompt_xr": "Stick: choose    A: fly",
	"prompt_flat": "Up / Down: choose    Shift: fly",
	"mark_text": "> ",
	"detail_text": "robots x{robots}, alarm x{alarm}: {reward}",
	"rewards": [
		{"tier": 3, "min_share": 0.4, "text": "rare finds"},
		{"tier": 2, "min_share": 0.35, "text": "richer finds"},
		{"tier": 1, "min_share": 0.0, "text": "common finds"},
	],
	"title_color": Color(0.85, 0.95, 1.0),
	"text_color": Color(0.6, 0.7, 0.8),
	"highlight_color": Color(0.35, 1.0, 0.45),
	"title_position_m": Vector3(0.0, 0.3, -1.5),
	"entry_step_m": 0.14,
	"title_font_size": 72.0,
	"label_font_size": 48.0,
	"detail_font_size": 36.0,
	"pixel_size": 0.001,
}


## The look in `path`, or `FALLBACK` with a warning naming the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("The shaft panel uses built-in words; %s: file not found" % path)
		return FALLBACK
	var look: Dictionary = parse(FileAccess.get_file_as_string(path))
	if look.has("error"):
		push_warning("The shaft panel uses built-in words; %s: %s" % [path, look["error"]])
		return FALLBACK
	return look


## The detail line of a shaft with `risk` ({"robot_count", "alarm"}) and tier
## `weights`.
static func detail_line(look: Dictionary, risk: Dictionary, weights: Array) -> String:
	return (look["detail_text"] as String).replace("{robots}", "%.1f" % float(risk["robot_count"])) \
		.replace("{alarm}", "%.1f" % float(risk["alarm"])).replace("{reward}", reward_text(look, weights))


## The reward words for tier `weights` (tiers 1..3): the first rule met.
static func reward_text(look: Dictionary, weights: Array) -> String:
	var total: float = 0.0
	for weight: Variant in weights:
		total += float(weight)
	for rule: Dictionary in look["rewards"]:
		var index: int = int(rule["tier"]) - 1
		var share: float = float(weights[index]) / total if total > 0.0 and index < weights.size() else 0.0
		if share >= float(rule["min_share"]):
			return rule["text"]
	return ""


## The look with colours as `Color`, the title place as `Vector3` and numbers
## as floats, or a dictionary holding only `"error"`, naming the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return {"error": "invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()]}
	if typeof(json.data) != TYPE_DICTIONARY:
		return {"error": "top level must be a JSON object"}
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not FALLBACK.has(key):
			return {"error": "unknown key \"%s\"" % str(key)}
	for key: String in FALLBACK:
		if not data.has(key):
			return {"error": "missing key \"%s\"" % key}
	var look: Dictionary = {}
	for key: String in TEXT_KEYS:
		if typeof(data[key]) != TYPE_STRING or (key != "mark_text" and (data[key] as String).strip_edges() == ""):
			return {"error": "\"%s\" must be a text%s" % [key, "" if key == "mark_text" else " that is not empty"]}
		look[key] = data[key]
	for mark: String in MARKS:
		if not (look["detail_text"] as String).contains(mark):
			return {"error": "\"detail_text\" must contain %s" % mark}
	for key: String in COLOR_KEYS:
		var parts: Array = _three_numbers(data[key])
		if parts.is_empty() or parts.min() < 0.0 or parts.max() > 1.0:
			return {"error": "\"%s\" must be [red, green, blue], each within 0..1" % key}
		look[key] = Color(parts[0], parts[1], parts[2])
	var at: Array = _three_numbers(data["title_position_m"])
	if at.is_empty() or absf(at[0]) > SIDE_LIMIT_M or absf(at[1]) > SIDE_LIMIT_M or -at[2] < NEAR_M \
			or -at[2] > FAR_M:
		return {"error": "\"title_position_m\" must be [x, y, z] within %s m to the side and %s..%s m in front" % [
			SIDE_LIMIT_M, NEAR_M, FAR_M]}
	look["title_position_m"] = Vector3(at[0], at[1], at[2])
	for key: String in RANGES:
		var value: Variant = data[key]
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:  # A bool must not pass as 0 or 1.
			return {"error": "\"%s\" must be a number" % key}
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return {"error": "\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]]}
		look[key] = float(value)
	var rewards: Variant = _parse_rewards(data["rewards"])
	if typeof(rewards) == TYPE_STRING:
		return {"error": rewards}
	look["rewards"] = rewards
	return look


## The reward rules as [{"tier": int, "min_share": float, "text": String}], or
## the problem as a String.
static func _parse_rewards(value: Variant) -> Variant:
	if typeof(value) != TYPE_ARRAY or (value as Array).is_empty():
		return "\"rewards\" must be a list of rules that is not empty"
	var rules: Array = []
	for i: int in (value as Array).size():
		var rule: Variant = value[i]
		var where: String = "rewards[%d]" % i
		if typeof(rule) != TYPE_DICTIONARY or (rule as Dictionary).size() != 3 or not rule.has("tier") \
				or not rule.has("min_share") or not rule.has("text"):
			return "%s must be {\"tier\", \"min_share\", \"text\"}" % where
		var tier: Variant = rule["tier"]
		if (typeof(tier) != TYPE_INT and typeof(tier) != TYPE_FLOAT) or float(tier) != floorf(float(tier)) \
				or int(tier) < 1 or int(tier) > ShaftOffer.TIERS:
			return "%s.tier must be a whole number within 1..%d" % [where, ShaftOffer.TIERS]
		var share: Variant = rule["min_share"]
		if (typeof(share) != TYPE_INT and typeof(share) != TYPE_FLOAT) or float(share) < 0.0 or float(share) > 1.0:
			return "%s.min_share must be a number within 0..1" % where
		if typeof(rule["text"]) != TYPE_STRING or (rule["text"] as String).strip_edges() == "":
			return "%s.text must be a text that is not empty" % where
		rules.append({"tier": int(tier), "min_share": float(share), "text": rule["text"]})
	if float(rules[-1]["min_share"]) != 0.0:
		return "rewards[%d].min_share must be 0, so every shaft gets a reward text" % (rules.size() - 1)
	return rules


static func _three_numbers(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 3:
		return []
	var result: Array = []
	for part: Variant in value:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return []
		result.append(float(part))
	return result
