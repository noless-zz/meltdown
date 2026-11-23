class_name LevelWallMaterial
extends RefCounted

## Parses `res://view/level_wall_material.json`, the physically based surface
## of the mine walls per theme (GFX-2, ARC-4, #1292), and hands its values to
## the wall shader. `LevelLook` keeps the tints, plating, grid and fog the owner
## tuned; this file only adds what lies on top: albedo, roughness, metallic and
## normal worked out from noise in `level_wall.gdshader`, so there are no
## images (ARC-5) and no UVs (the noise is triplanar in world space).
##
##     {"default_theme": "<name>",
##      "themes": {"<name>": {
##        "noise_scale_m": 0.25..10, "albedo_noise": 0..0.8,
##        "roughness_noise": 0..0.5, "metallic": 0..1, "metal_share": 0..1,
##        "metal_roughness": 0.2..1, "normal_strength": 0..1.5,
##        "bevel_strength": 0..1.5, "bevel_width_m": 0.01..0.25,
##        "triplanar_sharpness": 1..16}}}
##
## What each key does:
## - `noise_scale_m`: size of the largest blotch of wear; two finer octaves
##   sit under it.
## - `albedo_noise`: how far the colour strays around the `LevelLook` tint.
## - `roughness_noise`: how far roughness strays around `LevelLook.roughness`.
## - `metal_share` of the plates are bare metal (chosen per plate), with
##   `metallic` and `metal_roughness`; the rest stay rock (metallic 0).
## - `normal_strength`: how deeply the noise dents the surface for the light.
## - `bevel_strength` and `bevel_width_m`: each plate's edge is chamfered for
##   the light, so seams read as cut edges rather than painted lines (#1292,
##   the owner's note on thin-looking walls).
## - `triplanar_sharpness`: how hard the three projections blend on a slanted
##   face; boxes are axis-aligned, so only slanted faces see it.
##
## A missing key takes its value from `NEUTRAL`, which draws the walls exactly
## as before this file (no noise, no metal, flat normals). A missing or
## rejected file, or an unknown theme, gives `NEUTRAL` for every key.

const DEFAULT_FILE: String = "res://view/level_wall_material.json"

## Inclusive ranges of the per-theme keys.
const RANGES: Dictionary[String, Array] = {
	"noise_scale_m": [0.25, 10.0],
	"albedo_noise": [0.0, 0.8],
	"roughness_noise": [0.0, 0.5],
	"metallic": [0.0, 1.0],
	"metal_share": [0.0, 1.0],
	"metal_roughness": [0.2, 1.0],
	"normal_strength": [0.0, 1.5],
	"bevel_strength": [0.0, 1.5],
	"bevel_width_m": [0.01, 0.25],
	"triplanar_sharpness": [1.0, 16.0],
}

## Values that draw the walls as they were before this file (the current look).
const NEUTRAL: Dictionary = {
	"noise_scale_m": 1.0,
	"albedo_noise": 0.0,
	"roughness_noise": 0.0,
	"metallic": 0.0,
	"metal_share": 0.0,
	"metal_roughness": 0.5,
	"normal_strength": 0.0,
	"bevel_strength": 0.0,
	"bevel_width_m": 0.05,
	"triplanar_sharpness": 4.0,
}

## The shader uniform each key sets.
const UNIFORMS: Dictionary[String, String] = {
	"noise_scale_m": "noise_scale",
	"albedo_noise": "albedo_noise",
	"roughness_noise": "roughness_noise",
	"metallic": "metallic_value",
	"metal_share": "metal_share",
	"metal_roughness": "metal_roughness",
	"normal_strength": "normal_strength",
	"bevel_strength": "bevel_strength",
	"bevel_width_m": "bevel_width",
	"triplanar_sharpness": "triplanar_sharpness",
}


## Parses the text of a material file. Returns {"default_theme": String,
## "themes": {name: values}} with every key of every theme filled in (missing
## ones from `NEUTRAL`), or a dictionary holding only `"error"` naming the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	for key: Variant in data:
		if key != "default_theme" and key != "themes":
			return _rejected("unknown key \"%s\"" % str(key))
	if typeof(data.get("themes")) != TYPE_DICTIONARY or (data["themes"] as Dictionary).is_empty():
		return _rejected("\"themes\" must be an object with at least one theme")
	var themes: Dictionary = {}
	for name: Variant in data["themes"]:
		var raw: Variant = data["themes"][name]
		if typeof(raw) != TYPE_DICTIONARY:
			return _rejected("theme \"%s\" must be an object" % str(name))
		var values: Variant = _parse_theme(raw, str(name))
		if typeof(values) == TYPE_STRING:
			return _rejected(values)
		themes[str(name)] = values
	var default_theme: Variant = data.get("default_theme")
	if typeof(default_theme) != TYPE_STRING or not themes.has(default_theme):
		return _rejected("\"default_theme\" must name one of the themes")
	return {"default_theme": default_theme, "themes": themes}


## The values of `theme` (or the default theme when empty) in the file at
## `path`, or `NEUTRAL` after a warning naming the problem.
static func load_theme(theme: String = "", path: String = DEFAULT_FILE) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("wall material falls back to the flat look: %s: file not found" % path)
		return NEUTRAL
	var parsed: Dictionary = parse(FileAccess.get_file_as_string(path))
	if parsed.has("error"):
		push_warning("wall material falls back to the flat look: %s: %s" % [path, parsed["error"]])
		return NEUTRAL
	var name: String = theme if theme != "" else String(parsed["default_theme"])
	if not (parsed["themes"] as Dictionary).has(name):
		push_warning("wall material falls back to the flat look: %s has no theme \"%s\"" % [path, name])
		return NEUTRAL
	return parsed["themes"][name]


## Sets the wall shader's surface uniforms on `material` from `values`.
static func apply(material: ShaderMaterial, values: Dictionary) -> void:
	for key: String in UNIFORMS:
		material.set_shader_parameter(UNIFORMS[key], float(values.get(key, NEUTRAL[key])))


## One theme's values, every key filled, or a String naming the bad field.
static func _parse_theme(raw: Dictionary, name: String) -> Variant:
	var values: Dictionary = NEUTRAL.duplicate()
	for key: Variant in raw:
		var field: String = "themes.%s.%s" % [name, str(key)]
		if typeof(key) != TYPE_STRING or not RANGES.has(key):
			return "unknown key \"%s\"" % field
		var value: Variant = raw[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return "\"%s\" must be a number" % field
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return "\"%s\" is %s, must be within %s..%s" % [field, value, bounds[0], bounds[1]]
		values[key] = float(value)
	return values


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
