class_name HubIconParts
extends RefCounted

## Reads one icon of `res://data/hub/icons.json` (#1365, CRW-2, GFX-2, ARC-4):
##
##     {"color": [r, g, b], "parts": [{"shape": "rect"|"disc"|"ring"|"tri",
##      "size": [w, h], "at": [x, y], "turn_deg": n (optional),
##      "color": [r, g, b] (optional)}, ...]}
##
## An icon is a few flat shapes on a square one unit across, centred on 0, so
## the same icon draws at any size. `color` is the icon's own colour: the one
## told apart from the others in its group, and the colour of every part that
## names none. A part's own colour is for detail (a dark slot, a pale head).
## Parts are drawn in file order, a later part over an earlier one. Drawn from
## data, so a new icon is an entry in the file and nothing is copied from
## anywhere (NAM-3).

const SHAPES: Array[String] = ["rect", "disc", "ring", "tri"]
const KEYS: Array[String] = ["color", "parts"]
const PART_KEYS: Array[String] = ["shape", "size", "at", "turn_deg", "color"]
const MAX_PARTS: int = 8
## The icon's square runs from -HALF to HALF; a turned part may lean a little
## past it at a corner, never further than this.
const HALF: float = 0.5
const SLACK: float = 0.06


## {"color": Color, "parts": [{"shape", "size": Vector2, "at": Vector2,
## "turn_deg": float, "color": Color}]}, or {"error": ...} naming `where`.
static func parse(where: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "%s must be {\"color\", \"parts\"}" % where}
	var data: Dictionary = value
	for key: Variant in data:
		if not KEYS.has(key):
			return {"error": "%s has an unknown key \"%s\"" % [where, str(key)]}
	var color: Variant = color_of(data.get("color"))
	if color == null:
		return {"error": "%s.color must be [red, green, blue], each within 0..1" % where}
	var parts: Variant = data.get("parts")
	if typeof(parts) != TYPE_ARRAY or (parts as Array).is_empty() or (parts as Array).size() > MAX_PARTS:
		return {"error": "%s.parts must be a list of 1..%d parts" % [where, MAX_PARTS]}
	var read: Array[Dictionary] = []
	for i: int in (parts as Array).size():
		var part: Variant = _part(parts[i], color)
		if typeof(part) == TYPE_STRING:
			return {"error": "%s.parts[%d] %s" % [where, i, part]}
		read.append(part)
	return {"color": color, "parts": read}


static func _part(value: Variant, icon_color: Color) -> Variant:
	if typeof(value) != TYPE_DICTIONARY:
		return "must be an object"
	var part: Dictionary = value
	for key: Variant in part:
		if not PART_KEYS.has(key):
			return "has an unknown key \"%s\"" % str(key)
	if not SHAPES.has(part.get("shape")):
		return "shape must be one of %s" % [SHAPES]
	var size: Array = numbers(part.get("size"), 2)
	var at: Array = numbers(part.get("at"), 2)
	if size.is_empty() or size.min() <= 0.0 or at.is_empty():
		return "needs size (each above 0) and at, each as two numbers"
	var turn: Variant = part.get("turn_deg", 0.0)
	if not is_number(turn) or absf(float(turn)) > 360.0:
		return "turn_deg must be a number within -360..360"
	var color: Variant = color_of(part["color"]) if part.has("color") else icon_color
	if color == null:
		return "color must be [red, green, blue], each within 0..1"
	var turned: bool = fmod(absf(float(turn)), 180.0) != 0.0
	for axis: int in 2:
		var reach: float = 0.5 * (maxf(size[0], size[1]) if turned else float(size[axis]))
		if absf(at[axis]) + reach > HALF + (SLACK if turned else 0.0):
			return "reaches past the icon's square"
	return {"shape": part["shape"], "size": Vector2(size[0], size[1]), "at": Vector2(at[0], at[1]),
		"turn_deg": float(turn), "color": color}


static func color_of(value: Variant) -> Variant:
	var parts: Array = numbers(value, 3)
	if parts.is_empty() or parts.min() < 0.0 or parts.max() > 1.0:
		return null
	return Color(parts[0], parts[1], parts[2])


static func numbers(value: Variant, count: int) -> Array:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return []
	var result: Array = []
	for part: Variant in value:
		if not is_number(part):
			return []
		result.append(float(part))
	return result


## A bool must not pass as 0 or 1.
static func is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
