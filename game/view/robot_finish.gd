class_name RobotFinish
extends RefCounted

## A robot type's metal body and thruster glow (#1307, GFX-2, LGT-1, LGT-2):
## the optional `finish` and `thrust` objects of a `robot_look.json` entry.
## Kept apart from `RobotLook` and `RobotSkin` so each stays small, and so a
## new type needs data, not code (ARC-4).
##
##     "finish": {"albedo": [r, g, b], "roughness": 0.4, "metallic": 0.8,
##                "panel_scale": 2.0, "panel_depth": 0.5, "wear": 0.3}
##     "thrust": {"idle": 0.15, "full_mps": 10.0, "energy": 3.0}
##
## With a `finish` the body is lit, not emissive: the headlight shows its metal,
## panel seams and worn patches, and only the skin's accent lines glow in the
## type's `emission_color`, so in the dark a robot is seen by its eye and
## lines first (LGT-1). Without one the body glows as it did before #1307.
## Every key of either object is optional; a missing key takes `NO_FINISH` or
## `NO_THRUST`.
##
## `panel_scale` is panels per unit of the robot's drawn size, `panel_depth`
## how dark a seam is (0 none), `wear` the share of the surface worn.
##
## A part marked `"thruster": true` glows in the type's colour by its speed:
## `idle` of `energy` when still, all of `energy` at `full_mps` and over.

const FINISH_RANGES: Dictionary[String, Array] = {
	"roughness": [0.0, 1.0],
	"metallic": [0.0, 1.0],
	"panel_scale": [0.5, 12.0],
	"panel_depth": [0.0, 1.0],
	"wear": [0.0, 1.0],
}
const THRUST_RANGES: Dictionary[String, Array] = {
	"idle": [0.0, 1.0],
	"full_mps": [0.5, 60.0],
	"energy": [0.0, 8.0],
}
## The lit body when an entry gives `finish` but leaves a key out. `lit` false
## is the emissive body of before #1307.
const NO_FINISH: Dictionary = {
	"lit": false, "albedo": Color(0.35, 0.35, 0.37), "roughness": 0.45, "metallic": 0.8,
	"panel_scale": 2.0, "panel_depth": 0.5, "wear": 0.25,
}
const NO_THRUST: Dictionary = {"idle": 0.15, "full_mps": 10.0, "energy": 2.0}


## The finish in `value`, lit, with the albedo as `Color`, or a dictionary
## holding only `"error"`, which names the field.
static func parse_finish(field: String, value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"error": "\"%s\" must be an object" % field}
	var data: Dictionary = value
	var numbers: Dictionary = {}
	var finish: Dictionary = NO_FINISH.duplicate()
	finish["lit"] = true
	for key: Variant in data:
		if typeof(key) == TYPE_STRING and key == "albedo":
			var error: String = RobotLook._color(field + ".albedo", data[key])
			if error != "":
				return {"error": error}
			finish["albedo"] = RobotLook._to_color(data[key])
		else:
			numbers[key] = data[key]
	var parsed: Dictionary = RobotLook._parse_numbers(field, numbers, FINISH_RANGES, [])
	if parsed.has("error"):
		return parsed
	finish.merge(parsed, true)
	return finish


## The thrust in `value`, or a dictionary holding only `"error"`.
static func parse_thrust(field: String, value: Variant) -> Dictionary:
	var parsed: Dictionary = RobotLook._parse_numbers(field, value, THRUST_RANGES, [])
	if parsed.has("error"):
		return parsed
	return NO_THRUST.merged(parsed, true)


## Sets the lit-body uniforms of `material` (see `robot_skin.gdshader`).
static func apply(material: ShaderMaterial, finish: Dictionary) -> void:
	material.set_shader_parameter("lit_body", 1.0 if finish["lit"] else 0.0)
	material.set_shader_parameter("metal_albedo", finish["albedo"])
	material.set_shader_parameter("metal_roughness", finish["roughness"])
	material.set_shader_parameter("metal_metallic", finish["metallic"])
	material.set_shader_parameter("panel_scale", finish["panel_scale"])
	material.set_shader_parameter("panel_depth", finish["panel_depth"])
	material.set_shader_parameter("wear", finish["wear"])


## Emission energy of a thruster on a robot moving at `speed_mps`.
static func thrust_energy(thrust: Dictionary, speed_mps: float) -> float:
	var share: float = clampf(speed_mps / float(thrust["full_mps"]), 0.0, 1.0)
	return float(thrust["energy"]) * lerpf(float(thrust["idle"]), 1.0, share)


## A thruster material: unshaded glow, so it reads as a flame, not a surface.
static func make_thruster_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.emission_enabled = true
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


## Paints `material` in `color` at `energy`.
static func paint_thruster(material: StandardMaterial3D, color: Color, energy: float) -> void:
	material.emission = color
	material.emission_energy_multiplier = energy
	# Unshaded draws the albedo: scale it so a still robot's jets are dim.
	material.albedo_color = color * clampf(energy, 0.0, 1.0)
