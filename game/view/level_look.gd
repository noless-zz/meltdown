class_name LevelLook
extends RefCounted

## Parses `res://view/level_look.json`, the look of a mine's inside (GFX-4,
## LGT-1, ARC-4), and builds the wall materials and the environment from it.
## Shared by `LevelView` (G2 and generated mines) and `TestTunnel`, so every
## level reads the same way. Kept apart from `LevelView` so the node stays small.
##
##     {"wall_color": [r, g, b], "floor_color": [r, g, b],
##      "ceiling_color": [r, g, b], "roughness": 0..1,
##      "edge_color": [r, g, b], "edge_energy": 0..1, "edge_width_m": 0.02..1,
##      "grid_spacing_m": 0.5..20, "grid_line_width_m": 0.01..0.5,
##      "grid_line_factor": 0..4,
##      "plate_floor_m", "plate_wall_m", "plate_ceiling_m": 0.25..10,
##      "plate_floor_aspect", "plate_wall_aspect", "plate_ceiling_aspect": 1..8,
##      "plate_floor_stagger", "plate_wall_stagger", "plate_ceiling_stagger": 0..0.5,
##      "plate_seam_m": 0.005..0.2, "plate_contrast": 0..0.25,
##      "fog_color": [r, g, b], "fog_density": 0..0.2,
##      "ambient_color": [r, g, b], "ambient_energy": 0..0.3}
##
## Why each part is there (#609: the owner could not read the space):
## - Floor, ceiling and walls take different tints by which way they face, so
##   up and down read at a glance in a six-degrees-of-freedom ship.
## - A world-space grid of lines on every wall (`level_wall.gdshader`) gives
##   the eye something to converge on; a flat colour has no depth cue. The
##   lines are the tint times `grid_line_factor`, so above 1 they catch the
##   headlight brighter than the panel between them.
## - Under the grid every surface is plated (#660): panels `plate_<kind>_m`
##   high and `plate_<kind>_aspect` times as long, each row shifted by
##   `plate_<kind>_stagger` of a panel, with dark seams `plate_seam_m` wide.
##   Floor, wall and ceiling get different panels, chosen in the shader from
##   the face normal by the same rule as `surface_class`, so the kind of
##   surface reads from the pattern as well as the tint. `plate_contrast` is
##   how far a panel's tone strays and how dark a seam is; it is capped low so
##   the pattern does not flicker or pull the eye on the gentle comfort
##   presets 1 and 2, and the shader fades it out where panels get too small
##   on screen to draw without shimmer.
## - Exponential fog in a near-black colour darkens far walls more than near
##   ones, the cheapest depth cue there is. It is worked out in the wall
##   shader, not the environment, so it costs only on the walls (see
##   `level_wall.gdshader`); edge strips, robots and the cockpit are not fogged.
## - Ambient stays low so the mine is dark until the headlight, weapons or
##   flares light it (LGT-1); the range caps it.

const DEFAULT_FILE: String = "res://view/level_look.json"
const WALL_SHADER: String = "res://view/level_wall.gdshader"

const COLOR_KEYS: Array[String] = ["wall_color", "floor_color", "ceiling_color", "edge_color",
	"fog_color", "ambient_color"]
## Inclusive ranges of the number keys.
const RANGES: Dictionary[String, Array] = {
	"roughness": [0.0, 1.0],
	# Edge energy stays at or below 1 so the strips outline the mine, not light it.
	"edge_energy": [0.0, 1.0],
	"edge_width_m": [0.02, 1.0],
	"grid_spacing_m": [0.5, 20.0],
	"grid_line_width_m": [0.01, 0.5],
	"grid_line_factor": [0.0, 4.0],
	"plate_floor_m": [0.25, 10.0],
	"plate_wall_m": [0.25, 10.0],
	"plate_ceiling_m": [0.25, 10.0],
	"plate_floor_aspect": [1.0, 8.0],
	"plate_wall_aspect": [1.0, 8.0],
	"plate_ceiling_aspect": [1.0, 8.0],
	# Half a panel is the largest shift that is not the same as a smaller one.
	"plate_floor_stagger": [0.0, 0.5],
	"plate_wall_stagger": [0.0, 0.5],
	"plate_ceiling_stagger": [0.0, 0.5],
	"plate_seam_m": [0.005, 0.2],
	# A seam is darkened by twice this, so 0.25 is already half dark.
	"plate_contrast": [0.0, 0.25],
	# 0.2 per metre already hides a wall 15 m away; more would blind the pilot.
	"fog_density": [0.0, 0.2],
	"ambient_energy": [0.0, 0.3],
}

const FLOOR: String = "floor"
const CEILING: String = "ceiling"
const WALL: String = "wall"
## Surface classes in the order `LevelView` draws them.
const CLASSES: Array[String] = [FLOOR, CEILING, WALL]
## Surface classes in the order the wall shader's per-kind vectors hold them.
const SHADER_KINDS: Array[String] = [FLOOR, WALL, CEILING]
## A face whose normal points up (or down) more than this is a floor (or a
## ceiling): steeper than 45 degrees. The wall shader uses the same value.
const FLOOR_MIN_UP: float = 0.7071
## A seam may take at most this share of the smallest panel, so panels stay panels.
const SEAM_MAX_SHARE: float = 0.25

## Look used when the file is missing or rejected; matches the shipped file.
const FALLBACK: Dictionary = {
	"wall_color": Color(0.16, 0.15, 0.14),
	"floor_color": Color(0.22, 0.19, 0.15),
	"ceiling_color": Color(0.1, 0.11, 0.13),
	"roughness": 0.9,
	"edge_color": Color(0.25, 0.45, 0.6),
	"edge_energy": 0.4,
	"edge_width_m": 0.15,
	"grid_spacing_m": 2.0,
	"grid_line_width_m": 0.06,
	"grid_line_factor": 2.2,
	"plate_floor_m": 1.0,
	"plate_wall_m": 1.0,
	"plate_ceiling_m": 0.5,
	"plate_floor_aspect": 1.0,
	"plate_wall_aspect": 2.0,
	"plate_ceiling_aspect": 4.0,
	"plate_floor_stagger": 0.0,
	"plate_wall_stagger": 0.5,
	"plate_ceiling_stagger": 0.0,
	"plate_seam_m": 0.03,
	"plate_contrast": 0.12,
	"fog_color": Color(0.01, 0.012, 0.016),
	"fog_density": 0.035,
	"ambient_color": Color(0.25, 0.27, 0.3),
	"ambient_energy": 0.12,
}


## All keys a look file must hold, colours first.
static func keys() -> Array[String]:
	var all: Array[String] = COLOR_KEYS.duplicate()
	for key: String in RANGES:
		all.append(key)
	return all


## Parses the text of a look file. Returns the look with colours as `Color`
## and numbers as floats, or a dictionary holding only `"error"`, which names
## the field.
static func parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	if json.parse(text) != OK:
		return _rejected("invalid JSON at line %d: %s" % [json.get_error_line(), json.get_error_message()])
	if typeof(json.data) != TYPE_DICTIONARY:
		return _rejected("top level must be a JSON object")
	var data: Dictionary = json.data
	var all: Array[String] = keys()
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not all.has(key):
			return _rejected("unknown key \"%s\"" % str(key))
	for key: String in all:
		if not data.has(key):
			return _rejected("missing key \"%s\"" % key)
	var look: Dictionary = {}
	for key: String in COLOR_KEYS:
		var parts: Variant = data[key]
		if typeof(parts) != TYPE_ARRAY or (parts as Array).size() != 3:
			return _rejected("\"%s\" must be [red, green, blue]" % key)
		for part: Variant in parts:
			if typeof(part) != TYPE_FLOAT and typeof(part) != TYPE_INT:
				return _rejected("\"%s\" must hold numbers" % key)
			if float(part) < 0.0 or float(part) > 1.0:
				return _rejected("\"%s\" has %s, must be within 0..1" % [key, part])
		look[key] = Color(float(parts[0]), float(parts[1]), float(parts[2]))
	for key: String in RANGES:
		var value: Variant = data[key]
		# A bool must not pass as 0 or 1.
		if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
			return _rejected("\"%s\" must be a number" % key)
		var bounds: Array = RANGES[key]
		if float(value) < float(bounds[0]) or float(value) > float(bounds[1]):
			return _rejected("\"%s\" is %s, must be within %s..%s" % [key, value, bounds[0], bounds[1]])
		look[key] = float(value)
	for kind: String in SHADER_KINDS:
		var plate_key: String = "plate_%s_m" % kind
		if float(look["plate_seam_m"]) > float(look[plate_key]) * SEAM_MAX_SHARE:
			return _rejected("\"plate_seam_m\" is %s, must be at most %s of \"%s\" (%s)"
					% [look["plate_seam_m"], SEAM_MAX_SHARE, plate_key, look[plate_key]])
	return look


## The look in the file at `path`, or one holding only `"error"` naming the
## path and the field.
static func load_file(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = {}
	if FileAccess.file_exists(path):
		values = parse(FileAccess.get_file_as_string(path))
	else:
		values = _rejected("file not found")
	if values.has("error"):
		return _rejected("%s: %s" % [path, values["error"]])
	return values


## The look in the shipped file, or the fallback after a warning naming the
## field. For views that have no way to show the error themselves.
static func load_or_fallback(path: String = DEFAULT_FILE) -> Dictionary:
	var values: Dictionary = load_file(path)
	if values.has("error"):
		push_warning("level look falls back: %s" % values["error"])
		return FALLBACK
	return values


## Which kind of surface a wall whose normal points into the space along
## `normal` is: a floor faces up, a ceiling faces down, anything steeper than
## 45 degrees is a wall.
static func surface_class(normal: Vector3) -> String:
	var unit: Vector3 = normal.normalized()
	if unit.y > FLOOR_MIN_UP:
		return FLOOR
	if unit.y < -FLOOR_MIN_UP:
		return CEILING
	return WALL


## The tint of a surface facing along `normal`, from `look`.
static func tint_for(look: Dictionary, normal: Vector3) -> Color:
	return look["%s_color" % surface_class(normal)]


## A lit material in `tint` with `look`'s plating, world-space grid and
## distance fog. One per surface class; walls of every level share the shader.
## Every material carries the plating of all three kinds, since the shader
## picks one per face from its normal.
static func wall_material(look: Dictionary, tint: Color) -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = load(WALL_SHADER) as Shader
	material.set_shader_parameter("tint", tint)
	material.set_shader_parameter("roughness_value", float(look["roughness"]))
	material.set_shader_parameter("grid_spacing", float(look["grid_spacing_m"]))
	material.set_shader_parameter("line_width", float(look["grid_line_width_m"]))
	material.set_shader_parameter("line_factor", float(look["grid_line_factor"]))
	material.set_shader_parameter("plate_size", plate_vector(look, "m"))
	material.set_shader_parameter("plate_aspect", plate_vector(look, "aspect"))
	material.set_shader_parameter("plate_stagger", plate_vector(look, "stagger"))
	material.set_shader_parameter("seam_width", float(look["plate_seam_m"]))
	material.set_shader_parameter("plate_contrast", float(look["plate_contrast"]))
	material.set_shader_parameter("floor_min_up", FLOOR_MIN_UP)
	material.set_shader_parameter("fog_color", look["fog_color"])
	material.set_shader_parameter("fog_density", float(look["fog_density"]))
	return material


## One plating value per kind, in `SHADER_KINDS` order: `part` is "m",
## "aspect" or "stagger".
static func plate_vector(look: Dictionary, part: String) -> Vector3:
	var values: Array[float] = []
	for kind: String in SHADER_KINDS:
		values.append(float(look["plate_%s_%s" % [kind, part]]))
	return Vector3(values[0], values[1], values[2])


## The environment every level is drawn in: dark background in the fog's
## colour and low ambient light. Fog is the walls' own (`wall_material`).
static func environment(look: Dictionary) -> Environment:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = look["fog_color"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = look["ambient_color"]
	env.ambient_light_energy = float(look["ambient_energy"])
	env.fog_enabled = false
	return env


## A `WorldEnvironment` node named `node_name` holding `environment(look)`.
static func world_environment(look: Dictionary, node_name: String) -> WorldEnvironment:
	var world: WorldEnvironment = WorldEnvironment.new()
	world.name = node_name
	world.environment = environment(look)
	return world


static func _rejected(message: String) -> Dictionary:
	return {"error": message}
