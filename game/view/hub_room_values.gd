class_name HubRoomValues
extends RefCounted

## Checks and converts the plain JSON values of the home base room file
## (`HubRoomSpec`, #1298), kept apart so the spec stays small.


static func is_number(value: Variant, low: float, high: float) -> bool:
	if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
		return false
	return float(value) >= low and float(value) <= high


## True for a list of `count` numbers, each within low..high.
static func is_vector(value: Variant, count: int, low: float, high: float) -> bool:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != count:
		return false
	for part: Variant in value:
		if not is_number(part, low, high):
			return false
	return true


static func vector3(value: Variant) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))


static func color(value: Variant) -> Color:
	return Color(float(value[0]), float(value[1]), float(value[2]))


## The material in `raw` with `defaults` for missing keys, as
## {"color": Color, "metallic", "roughness", "emission": Color, "emission_energy",
## "wear", "edge", "panel_m"}, or a String naming what is wrong.
static func material(raw: Variant, defaults: Dictionary) -> Variant:
	if typeof(raw) != TYPE_DICTIONARY:
		return "must be an object"
	var data: Dictionary = defaults.duplicate(true)
	data.merge(raw, true)
	for key: Variant in data:
		if key != "color" and not defaults.has(key):
			return "unknown key \"%s\"" % str(key)
	for key: String in ["color", "emission"]:
		if not is_vector(data.get(key), 3, 0.0, 1.0):
			return "\"%s\" must be [red, green, blue], each 0..1" % key
	for key: String in ["metallic", "roughness"]:
		if not is_number(data[key], 0.0, 1.0):
			return "\"%s\" must be 0..1" % key
	if not is_number(data["emission_energy"], 0.0, 8.0):
		return "\"emission_energy\" must be 0..8"
	for key: String in ["wear", "edge"]:
		if not is_number(data[key], 0.0, 1.0):
			return "\"%s\" must be 0..1" % key
	if not is_number(data["panel_m"], 0.0, 4.0):
		return "\"panel_m\" must be 0..4 metres (0 for no seams)"
	return {"color": color(data["color"]), "metallic": float(data["metallic"]),
		"roughness": float(data["roughness"]), "emission": color(data["emission"]),
		"emission_energy": float(data["emission_energy"]), "wear": float(data["wear"]),
		"edge": float(data["edge"]), "panel_m": float(data["panel_m"])}
