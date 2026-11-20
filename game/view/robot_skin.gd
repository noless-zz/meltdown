class_name RobotSkin
extends RefCounted

## A robot type's surface pattern, accent colour and face plate (#661, GFX-2,
## CMB-3), drawn by `robot_skin.gdshader`. Parses the optional `skin` object of
## a `robot_look.json` entry and keeps the shader's uniforms in one place, so
## `RobotView` stays small and a new type needs data, not code (ARC-4).
##
##     "skin": {"pattern": "rings", "accent_color": [r, g, b], "scale": 3.0,
##              "width": 0.3, "face_color": [r, g, b], "face_depth": 0.4}
##
## `pattern` is one of `PATTERNS`. `scale` is pattern cells per unit of the
## robot's drawn size, `width` the share of a cell a line covers. The face
## plate covers the robot where it lies more than `face_depth` (in units of its
## drawn size) ahead of its centre along `FACE_AXIS`, the robot's forward.

const SHADER: Shader = preload("res://view/robot_skin.gdshader")
## Index order matches the shader's `pattern` uniform.
const PATTERNS: Array[String] = ["plain", "rings", "chevrons", "checks", "bands", "stripes", "grid", "dots"]
const KEYS: Array[String] = ["pattern", "accent_color", "scale", "width", "face_color", "face_depth"]
const REQUIRED_KEYS: Array[String] = ["pattern", "accent_color"]
const RANGES: Dictionary[String, Array] = {
	"scale": [0.5, 12.0],
	"width": [0.05, 0.9],
	"face_depth": [0.0, 4.0],
}
## A robot's forward in its own frame: `RobotState.forward()` is its -z.
const FACE_AXIS: Vector3 = Vector3(0.0, 0.0, -1.0)
## No face plate: deeper than any part reaches.
const NO_FACE: float = 4.0
const PLAIN: Dictionary = {
	"pattern": "plain", "accent_color": Color(0.2, 0.2, 0.2), "scale": 3.0, "width": 0.3,
	"face_color": Color(1.0, 1.0, 1.0), "face_depth": NO_FACE,
}


## The skin in `value` with colours as `Color`, or a dictionary holding only
## `"error"`, which names the field.
static func parse(field: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "\"%s\" must be an object" % field}
	var data: Dictionary = value
	for key: Variant in data:
		if typeof(key) != TYPE_STRING or not KEYS.has(key):
			return {"error": "\"%s\" has unknown key \"%s\"" % [field, str(key)]}
	for key: String in REQUIRED_KEYS:
		if not data.has(key):
			return {"error": "\"%s\" is missing key \"%s\"" % [field, key]}
	if typeof(data["pattern"]) != TYPE_STRING or not PATTERNS.has(data["pattern"]):
		return {"error": "\"%s.pattern\" is %s, must be one of %s" % [field, JSON.stringify(data["pattern"]),
				", ".join(PackedStringArray(PATTERNS))]}
	var skin: Dictionary = PLAIN.duplicate()
	skin["pattern"] = data["pattern"]
	for key: String in ["accent_color", "face_color"]:
		if not data.has(key):
			continue
		var error: String = RobotLook._color("%s.%s" % [field, key], data[key])
		if error != "":
			return {"error": error}
		skin[key] = RobotLook._to_color(data[key])
	for key: String in RANGES:
		if not data.has(key):
			continue
		var error: String = RobotLook._number("%s.%s" % [field, key], data[key], RANGES[key])
		if error != "":
			return {"error": error}
		skin[key] = float(data[key])
	return skin


## A body material for one robot, with no type's skin yet.
static func make_material() -> ShaderMaterial:
	var material: ShaderMaterial = ShaderMaterial.new()
	material.shader = SHADER
	apply(material, PLAIN)
	paint(material, Color(0.8, 0.8, 0.8), 1.0, 0.0, Color.WHITE, 1.0)
	return material


## Sets the pattern and face uniforms of `material` from `skin`.
static func apply(material: ShaderMaterial, skin: Dictionary) -> void:
	material.set_shader_parameter("pattern", PATTERNS.find(skin["pattern"]))
	material.set_shader_parameter("pattern_scale", skin["scale"])
	material.set_shader_parameter("pattern_width", skin["width"])
	material.set_shader_parameter("accent_color", skin["accent_color"])
	material.set_shader_parameter("face_color", skin["face_color"])
	material.set_shader_parameter("face_depth", skin["face_depth"])
	material.set_shader_parameter("face_axis", FACE_AXIS)


## Sets the frame's colour: the type's `base` colour, dimmed by `brightness`
## (0..1, the damage dim), mixed by `flash` (0..1) towards `flash_color`, and
## emitted `energy` times over (the wind-up glow).
static func paint(material: ShaderMaterial, base: Color, brightness: float, flash: float,
		flash_color: Color, energy: float) -> void:
	material.set_shader_parameter("base_color", base)
	material.set_shader_parameter("brightness", brightness)
	material.set_shader_parameter("flash", flash)
	material.set_shader_parameter("flash_color", flash_color)
	material.set_shader_parameter("energy", energy)


## The colour the unpatterned body shows this frame, as the shader works it
## out: the base dimmed, then mixed towards the flash.
static func shown_color(material: ShaderMaterial) -> Color:
	var base: Color = material.get_shader_parameter("base_color")
	var brightness: float = material.get_shader_parameter("brightness")
	var flash_color: Color = material.get_shader_parameter("flash_color")
	return (base * brightness).lerp(flash_color, float(material.get_shader_parameter("flash")))


## The emission multiplier this frame.
static func energy(material: ShaderMaterial) -> float:
	return float(material.get_shader_parameter("energy"))


## Whether `point`, in the robot's own frame and units of its drawn size, is on
## the face plate of `skin`; mirrors the shader.
static func is_face(point: Vector3, skin: Dictionary) -> bool:
	return point.dot(FACE_AXIS) > float(skin["face_depth"])
