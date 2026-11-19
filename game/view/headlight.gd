class_name Headlight
extends SpotLight3D

## The ship's headlight (CMB-5, GFX-4, #609): a spot light fixed to the ship,
## shining along the nose (the light's own -Z), and the one light in the game
## that casts shadows. On by default; switching it off is CMB-5's later work.
##
## The look lives in `res://view/headlight_look.json` (ARC-4):
##
##     {"color": [r, g, b], "energy": 0..16, "range_m": 5..100,
##      "angle_deg": 10..80, "attenuation": 0..2,
##      "offset_m": [right, up, back]}
##
## `offset_m` is where the lamp sits from the ship's centre, in the ship's own
## axes. A lamp exactly at the eye throws every shadow straight behind what
## casts it, where the eye cannot see it; a little below and ahead, shadows
## show and give the shapes depth. Each part stays within half a metre, inside
## the ship's 1 m radius, so the lamp is never outside a wall the ship touches.
##
## The view only reads the ship's pose through where its node is placed; it
## never writes simulation state (MP-2).

const NODE_NAME: String = "Headlight"
const DEFAULT_FILE: String = "res://view/headlight_look.json"

const KEYS: Array[String] = ["color", "energy", "range_m", "angle_deg", "attenuation", "offset_m"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"energy": [0.0, 16.0],
	"range_m": [5.0, 100.0],
	# Narrower than 10 degrees is a laser; wider than 80 lights the cockpit glass.
	"angle_deg": [10.0, 80.0],
	"attenuation": [0.0, 2.0],
}
const OFFSET_LIMIT_M: float = 0.5

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"color": Color(1.0, 0.95, 0.85),
	"energy": 6.0,
	"range_m": 45.0,
	"angle_deg": 32.0,
	"attenuation": 0.8,
	"offset_m": Vector3(0.0, -0.25, -0.3),
}

## Set when the last look file was rejected; empty otherwise.
var look_error: String = ""

var _look: Dictionary = FALLBACK


func _init() -> void:
	name = NODE_NAME
	load_look()


## Parses the text of a look file. Returns the look with the colour as
## `Color`, the offset as `Vector3` and numbers as floats, or a dictionary
## holding only `"error"`, which names the field.
static func parse_look(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in KEYS:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	var color: Variant = _triple(data, "color", 0.0, 1.0)
	if color is String:
		return _rejected(color)
	look["color"] = Color((color as Vector3).x, (color as Vector3).y, (color as Vector3).z)
	var offset: Variant = _triple(data, "offset_m", -OFFSET_LIMIT_M, OFFSET_LIMIT_M)
	if offset is String:
		return _rejected(offset)
	look["offset_m"] = offset
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	return look


## Applies the look file at `path` to this light. A missing or rejected file
## leaves the fallback look, sets `look_error` and pushes a warning naming the
## field. Returns `look_error`.
func load_look(path: String = DEFAULT_FILE) -> String:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse_look(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	_look = FALLBACK
	look_error = ""
	if values.has("error"):
		look_error = "%s: %s" % [path, values["error"]]
		push_warning("Headlight uses the fallback look; %s" % look_error)
	else:
		_look = values
	_apply()
	return look_error


## The look in use.
func look() -> Dictionary:
	return _look


## Puts the lamp on the ship whose centre and axes, in the parent's space,
## are `ship_frame`: at the look's offset, shining along the ship's nose.
func place(ship_frame: Transform3D) -> void:
	transform = ship_frame * Transform3D(Basis.IDENTITY, _look["offset_m"])


func _apply() -> void:
	light_color = _look["color"]
	light_energy = float(_look["energy"])
	spot_range = float(_look["range_m"])
	spot_angle = float(_look["angle_deg"])
	spot_attenuation = float(_look["attenuation"])
	shadow_enabled = true
	visible = true


## `data[key]` as a Vector3 when it is three numbers within `low..high`, or a
## message naming `key`.
static func _triple(data: Dictionary, key: String, low: float, high: float) -> Variant:
	var parts: Variant = data[key]
	if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
		return "\"%s\" must be three numbers" % key
	for part: Variant in parts:
		if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
			return "\"%s\" must hold numbers" % key
		if float(part) < low or float(part) > high:
			return "\"%s\" has %s, must be within %s..%s" % [key, part, low, high]
	return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
