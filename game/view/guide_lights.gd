class_name GuideLights
extends RefCounted

## The guide light strips of one built level (#1463, GFX-2, GFX-5): placed by
## `GuideLightPlacement` from the look's `guide_lights` rules, coloured by
## each box's kind, and drawn by `LevelViewMeshes` in the box's bevel surface,
## so they cost no draw call and no light of their own (GFX-4, PRF-2). The
## strips glow through the wall shader's `strip_energy`, which `set_on` turns
## down to nothing, so a check can compare the mine with and without them.
## Presentation only: it reads the union and never writes it (MP-2).

## The wall shader's uniform the strips glow by.
const ENERGY_PARAMETER: String = "strip_energy"

## Set when the look's rules were rejected; empty otherwise.
var error: String = ""
## Whether the look has the section at all.
var enabled: bool = false
## The union the strips were placed in; read only.
var union: BoxUnion = null
var rules: Dictionary = {}
## The kind of each box, or empty without rules.
var kinds: Array[String] = []
## Every strip, in `GuideLightPlacement` layout.
var strips: Array[Dictionary] = []
var _per_box: Array[Array] = []
var _materials: Array[ShaderMaterial] = []
var _on: bool = true


## The strips `look` gives `level`. No section draws nothing and is no error;
## a bad section names the field and also draws nothing.
static func for_look(level: BoxUnion, look: Dictionary, reactor: Variant) -> GuideLights:
	var lights: GuideLights = GuideLights.new()
	lights.union = level
	for index: int in level.boxes.size():
		lights._per_box.append([])
	if not look.has(GuideLightRules.KEY):
		return lights
	var parsed: Dictionary = GuideLightRules.parse(look[GuideLightRules.KEY])
	if parsed.has("error"):
		lights.error = parsed["error"]
		return lights
	lights.enabled = true
	lights.rules = parsed
	lights.kinds = GuideLightPlacement.kinds(level, parsed, reactor)
	lights.strips = GuideLightPlacement.strips(level, parsed, lights.kinds)
	for strip: Dictionary in lights.strips:
		lights._per_box[int(strip["box"])].append(strip)
	return lights


## The strips of box `index`.
func strips_of(index: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if index >= 0 and index < _per_box.size():
		result.assign(_per_box[index])
	return result


## The colour box `index`'s strips glow in, before the energy.
func color_of(index: int) -> Color:
	if not enabled or index < 0 or index >= kinds.size():
		return Color.BLACK
	return (rules[GuideLightRules.COLORS_KEY] as Dictionary)[kinds[index]]


## The energy the strips glow at now: the look's, or 0 when switched off.
func energy() -> float:
	return float(rules["energy"]) if enabled and _on else 0.0


## Makes `material` glow the strips drawn in it, and follow `set_on`.
func use_in(material: ShaderMaterial) -> void:
	_materials.append(material)
	material.set_shader_parameter(ENERGY_PARAMETER, energy())


## Switches the strips' glow on or off in every material they are drawn in.
func set_on(on: bool) -> void:
	_on = on
	for material: ShaderMaterial in _materials:
		material.set_shader_parameter(ENERGY_PARAMETER, energy())


func is_on() -> bool:
	return _on
