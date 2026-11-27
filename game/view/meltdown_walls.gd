class_name MeltdownWalls
extends RefCounted

## The mine's emergency look once the reactor has died (#1454, GFX-6, GFX-4,
## PRF-2, PRF-4, CMF-8): the walls glow a slow warning pulse, their ambient
## turns towards a warning colour, and the guide strips (#1463) take an alert
## colour and pulse with them, all ramped in from the moment of death.
##
## Everything happens in the wall shader the level already draws with
## (`level_wall.gdshader`): no full-screen pass, no post-process, no light and
## no draw call is added. Each frame `show` sets one uniform, `meltdown`, on
## each of the level's two materials (walls and bevels). It holds (ramp, wall
## emission, strip brightness); the colours are set once, in `use_in`.
##
## A view: it is handed the seconds since the reactor died, as `MeltdownCue`
## is, and reads nothing of the simulation (ARC-1, MP-2). Its look comes from
## the `meltdown` section of `level_look.json` (`MeltdownWallRules`, ARC-4);
## without the section, or with a bad one, the materials keep the uniform's
## default and the mine draws exactly as before.

## The wall shader's uniform `show` sets every frame.
const PARAMETER: String = "meltdown"
const GLOW_PARAMETER: String = "meltdown_glow"
const AMBIENT_PARAMETER: String = "meltdown_ambient"
const SHIFT_PARAMETER: String = "meltdown_ambient_shift"
const STRIP_PARAMETER: String = "meltdown_strip"
## The uniform's value with no meltdown: no ramp, no glow, strips at full.
const OFF: Vector3 = Vector3(0.0, 0.0, 1.0)

## Set when the look's section was rejected; empty otherwise.
var error: String = ""
## Whether the look has a usable section.
var enabled: bool = false
var rules: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _value: Vector3 = OFF


## The emergency look `look` gives, drawn in `materials` (`ShaderMaterial`s).
## No section draws nothing and is no error; a bad one pushes a warning naming
## the field.
static func for_look(look: Dictionary, materials: Array = []) -> MeltdownWalls:
	var walls: MeltdownWalls = MeltdownWalls.new()
	if look.has(MeltdownWallRules.KEY):
		var parsed: Dictionary = MeltdownWallRules.parse(look[MeltdownWallRules.KEY])
		if parsed.has("error"):
			walls.error = parsed["error"]
			push_warning("LevelView draws no meltdown look; %s" % walls.error)
		else:
			walls.enabled = true
			walls.rules = parsed
	for material: Variant in materials:
		walls.use_in(material as ShaderMaterial)
	return walls


## The uniform's value `elapsed_s` seconds after the reactor died, under
## `rules`: (ramp 0..1, wall emission, strip brightness). Before the death
## (negative) it is `OFF`. The pulse is a raised cosine starting at its low
## point, so the look eases in without a step.
static func amount(rules: Dictionary, elapsed_s: float) -> Vector3:
	if elapsed_s < 0.0 or rules.is_empty():
		return OFF
	var ramp: float = smoothstep(0.0, float(rules["ramp_s"]), elapsed_s)
	var wave: float = 0.5 - 0.5 * cos(TAU * elapsed_s / float(rules["period_s"]))
	var emission: float = ramp * lerpf(float(rules["low_emission"]), float(rules["high_emission"]), wave)
	var strip: float = 1.0 - ramp * float(rules["strip_swing"]) * (1.0 - wave)
	return Vector3(ramp, emission, strip)


## Makes `material` draw the emergency look and follow `show`.
func use_in(material: ShaderMaterial) -> void:
	_materials.append(material)
	if not enabled:
		return
	material.set_shader_parameter(GLOW_PARAMETER, rules["wall_color"])
	material.set_shader_parameter(AMBIENT_PARAMETER, _full(rules["ambient_color"]))
	material.set_shader_parameter(SHIFT_PARAMETER, float(rules["ambient_shift"]))
	material.set_shader_parameter(STRIP_PARAMETER, rules["strip_color"])
	material.set_shader_parameter(PARAMETER, _value)


## Shows the look `elapsed_s` seconds after the reactor died; negative turns
## it off. Sets the uniform only when its value changed.
func show(elapsed_s: float) -> void:
	if not enabled:
		return
	var value: Vector3 = amount(rules, elapsed_s)
	if value == _value:
		return
	_value = value
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(PARAMETER, value)


## The uniform's value now.
func value() -> Vector3:
	return _value


## The materials it draws in; checks read their uniform back.
func materials() -> Array[ShaderMaterial]:
	return _materials


## `color` scaled so its largest part is 1: the shader keeps each box's own
## ambient brightness and takes only the hue from it.
static func _full(color: Color) -> Color:
	var peak: float = maxf(color.r, maxf(color.g, color.b))
	return Color(color.r / peak, color.g / peak, color.b / peak) if peak > 0.0 else Color.BLACK
